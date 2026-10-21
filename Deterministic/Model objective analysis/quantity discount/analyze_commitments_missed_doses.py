#!/usr/bin/env python3
"""
Aggregate commitment (Q) and missed-doses (S) totals across multiple
demand-variation trial runs, per scenario, for one chosen model, and chart
mean +/- std by scenario.

===============================================================================
FILE LAYOUT THIS SCRIPT EXPECTS
===============================================================================
    DATA_DIR/                          e.g. "results\\buyer discounts"
        1 segment/
            UG/
                MVP_DE_results_T_10_delta_5_scen_1_trial_1_inv_1_cap._1_cap.inc._1.json
                MVP_DE_results_T_10_delta_5_scen_1_trial_2_inv_1_cap._1_cap.inc._1.json
                ... (30 trial files)
            SB/
                ...
            MP/
                ...
        2 segments/
            UG/ SB/ MP/  (same as above)
        ... (any number of other scenario subfolders)

- DATA_DIR is whatever you pass with --data-dir.
- Scenario folders are auto-discovered: every subfolder of DATA_DIR is treated
  as one scenario (so you don't need to hardcode "1 segment", "2 segments",
  etc. here -- just make sure DATA_DIR only contains scenario folders).
- You pick which model to analyze with --model {UG,SB,MP}. Only that
  subfolder is read within each scenario.
- Trial number is parsed out of the filename itself via the "trial_<N>"
  segment (e.g. "..._trial_7_..." -> trial 7), so file order on disk doesn't
  matter and the script can tell you if any of the 30 are missing.

Each JSON file is expected to have the same shape as the files you shared
earlier: a dict with top-level keys including "Q" and "S", each an arbitrarily
nested dict whose leaves are numeric values (doses). The script sums *all*
numeric leaves under "Q" and under "S" to get one total-commitment and one
total-missed-doses number per trial file.
===============================================================================
"""

import argparse
import csv
import json
import re
import statistics
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")  # no display needed; just save PNGs
import matplotlib.pyplot as plt


EXPECTED_TRIALS = 30
MODEL_CHOICES = ["UG", "SB", "MP"]

# The top-level JSON keys to aggregate. Add/remove here if you later want
# the same 30-trial aggregation for other variables (e.g. "X", "Z").
VARIABLES = {
    "Q": "Aggregate commitment (Q)",
    "S": "Aggregate missed doses (S)",
}

TRIAL_NUM_RE = re.compile(r"trial_(\d+)")


def natural_sort_key(name: str):
    """Sort scenario folder names like '1 segment', '2 segments', '10 segments'
    numerically on the leading number rather than alphabetically."""
    m = re.match(r"\s*(\d+)", name)
    return (int(m.group(1)) if m else float("inf"), name)


def discover_scenarios(data_dir: Path) -> list[str]:
    """Every subfolder of data_dir is treated as one scenario."""
    scenarios = [p.name for p in data_dir.iterdir() if p.is_dir()]
    return sorted(scenarios, key=natural_sort_key)


def find_trial_files(data_dir: Path, scenario: str, model: str) -> list[Path]:
    """Return the trial JSON files for one scenario + model, sorted by trial number."""
    model_dir = data_dir / scenario / model
    if not model_dir.is_dir():
        return []
    files = list(model_dir.glob("*.json"))

    def sort_key(f: Path):
        m = TRIAL_NUM_RE.search(f.name)
        return int(m.group(1)) if m else 10**9  # unparseable names sort last

    return sorted(files, key=sort_key)


def trial_number(f: Path):
    m = TRIAL_NUM_RE.search(f.name)
    return int(m.group(1)) if m else None


def flatten_leaves(node):
    """Yield every numeric leaf value in an arbitrarily nested dict."""
    if isinstance(node, dict):
        for v in node.values():
            yield from flatten_leaves(v)
    elif isinstance(node, (int, float)):
        yield node
    # non-numeric, non-dict leaves (shouldn't occur in this data) are skipped


def sum_variable(doc: dict, var_key: str) -> float:
    """Sum all numeric leaves under doc[var_key]. Returns 0.0 if key missing."""
    if var_key not in doc:
        return 0.0
    return sum(flatten_leaves(doc[var_key]))


def load_trial_totals(files: list[Path], var_key: str) -> dict[int, float]:
    """Returns {trial_number: total}. Files whose trial number can't be parsed
    are keyed by a negative running index so they still get included."""
    totals = {}
    fallback_idx = -1
    for f in files:
        try:
            with open(f) as fh:
                doc = json.load(fh)
        except (json.JSONDecodeError, OSError) as e:
            print(f"  WARNING: could not read {f.name}: {e}", file=sys.stderr)
            continue
        tnum = trial_number(f)
        if tnum is None:
            print(f"  WARNING: could not parse trial number from {f.name}", file=sys.stderr)
            tnum = fallback_idx
            fallback_idx -= 1
        totals[tnum] = sum_variable(doc, var_key)
    return totals


def summarize(totals: list[float]) -> dict:
    if not totals:
        return {"n": 0, "mean": float("nan"), "std": float("nan"),
                "min": float("nan"), "max": float("nan")}
    return {
        "n": len(totals),
        "mean": statistics.mean(totals),
        "std": statistics.stdev(totals) if len(totals) > 1 else 0.0,
        "min": min(totals),
        "max": max(totals),
    }


def run_analysis(data_dir: Path, model: str, out_dir: Path):
    out_dir.mkdir(parents=True, exist_ok=True)

    scenarios = discover_scenarios(data_dir)
    if not scenarios:
        print(f"ERROR: no subfolders found under {data_dir}", file=sys.stderr)
        sys.exit(1)
    print(f"Discovered {len(scenarios)} scenario folder(s): {scenarios}")
    print(f"Model: {model}\n")

    # results[var_key][scenario] = summary dict
    results = {var_key: {} for var_key in VARIABLES}
    # trial_totals[var_key][scenario] = {trial_number: total}
    trial_totals = {var_key: {} for var_key in VARIABLES}

    for scenario in scenarios:
        files = find_trial_files(data_dir, scenario, model)
        found_trial_nums = sorted(t for t in (trial_number(f) for f in files) if t is not None)
        missing = sorted(set(range(1, EXPECTED_TRIALS + 1)) - set(found_trial_nums))

        msg = f"[{scenario}/{model}] found {len(files)} file(s)"
        if len(files) != EXPECTED_TRIALS:
            msg += f"  <-- expected {EXPECTED_TRIALS}"
        if missing:
            msg += f"  (missing trial #s: {missing})"
        print(msg)

        for var_key in VARIABLES:
            totals_by_trial = load_trial_totals(files, var_key)
            trial_totals[var_key][scenario] = totals_by_trial
            results[var_key][scenario] = summarize(list(totals_by_trial.values()))

    # ---- CSV export: one row per (scenario, trial, variable) ----
    csv_path = out_dir / f"trial_level_totals_{model}.csv"
    with open(csv_path, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["model", "scenario", "variable", "trial_number", "total"])
        for var_key in VARIABLES:
            for scenario in scenarios:
                for tnum, val in sorted(trial_totals[var_key][scenario].items()):
                    writer.writerow([model, scenario, var_key, tnum, val])
    print(f"\nWrote per-trial totals to {csv_path}")

    # ---- CSV export: summary (mean/std/min/max) per scenario per variable ----
    summary_path = out_dir / f"scenario_summary_{model}.csv"
    with open(summary_path, "w", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["model", "variable", "scenario", "n_trials", "mean", "std", "min", "max"])
        for var_key in VARIABLES:
            for scenario in scenarios:
                s = results[var_key][scenario]
                writer.writerow([model, var_key, scenario, s["n"], s["mean"], s["std"], s["min"], s["max"]])
    print(f"Wrote scenario summary to {summary_path}")

    # ---- Charts: mean +/- std bar chart per variable ----
    for var_key, title in VARIABLES.items():
        means = [results[var_key][s]["mean"] for s in scenarios]
        stds = [results[var_key][s]["std"] for s in scenarios]

        fig, ax = plt.subplots(figsize=(9, 5.5))
        bars = ax.bar(scenarios, means, yerr=stds, capsize=5,
                       color="#4C72B0", edgecolor="black", linewidth=0.5)
        ax.set_title(f"{title} by scenario \u2014 model {model} (mean \u00b1 std across trials)")
        ax.set_ylabel("Doses")
        ax.set_xlabel("Scenario")
        plt.xticks(rotation=20, ha="right")
        ax.ticklabel_format(style="plain", axis="y")

        for bar, s in zip(bars, scenarios):
            n = results[var_key][s]["n"]
            height = bar.get_height()
            ax.annotate(f"n={n}", xy=(bar.get_x() + bar.get_width() / 2, height),
                        xytext=(0, 8), textcoords="offset points",
                        ha="center", fontsize=8, color="#333333")

        fig.tight_layout()
        chart_path = out_dir / f"{var_key}_by_scenario_{model}.png"
        fig.savefig(chart_path, dpi=150)
        plt.close(fig)
        print(f"Saved chart: {chart_path}")

    # ---- Console summary table ----
    print(f"\n=== SUMMARY for model {model} (mean [std], across trials found) ===")
    for var_key, title in VARIABLES.items():
        print(f"\n{title}")
        for scenario in scenarios:
            s = results[var_key][scenario]
            print(f"  {scenario:28s} mean={s['mean']:>15,.1f}  std={s['std']:>13,.1f}  "
                  f"min={s['min']:>15,.1f}  max={s['max']:>15,.1f}  (n={s['n']})")


def main():
    parser = argparse.ArgumentParser(
        description="Aggregate Q (commitments) and S (missed doses) across trial runs, "
                     "per scenario, for one selected model (UG/SB/MP)."
    )
    parser.add_argument(
        "--data-dir", type=Path, required=True,
        help=r"Top-level results folder containing scenario subfolders, "
             r'e.g. "results\buyer discounts". Each scenario subfolder must '
             r"contain UG/, SB/, MP/ model subfolders with the trial JSON files."
    )
    parser.add_argument(
        "--model", choices=MODEL_CHOICES, required=True,
        help="Which model's results to analyze: UG, SB, or MP."
    )
    parser.add_argument(
        "--out-dir", type=Path, default=Path("./analysis_output"),
        help="Where to write CSVs and chart PNGs. Default: ./analysis_output"
    )
    args = parser.parse_args()

    if not args.data_dir.is_dir():
        print(f"ERROR: data dir not found: {args.data_dir}", file=sys.stderr)
        sys.exit(1)

    run_analysis(args.data_dir, args.model, args.out_dir)


if __name__ == "__main__":
    main()
