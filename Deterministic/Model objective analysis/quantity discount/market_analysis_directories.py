"""
Model Results Analysis — Directory Groups (30 trials each)
=============================================================
Computes mean, standard deviation, variance, and 95% CI of F, Q, W, X, I,
and S -- by vaccine, by producer, and by antigen -- across all JSON files
in a directory (one directory = one model group, e.g. 30 demand trials).
Compares up to 10 groups side-by-side with tables, CSVs, and plots.

IMPORTANT -- Q correction
-------------------------
Q_vptaum is an AGGREGATE commitment over a tender window [t, tau], not a
per-period quantity. The same (vaccine, producer) pair frequently has
multiple overlapping tender windows (e.g. windows starting at t=1,2,3...
all covering some of the same periods), and each window's Q already equals
the cumulative X delivered within that window. Summing every Q entry
naively -- as a straight walk of the JSON would do -- therefore
multiply-counts the same real doses once for every overlapping window that
contains them.

This script instead uses the MAX single-window Q per (vaccine, producer)
pair as that pair's true committed volume: the largest window already
captures the full cumulative delivery, so any shorter or differently-timed
window for the same pair is a partial restatement of the same underlying
data, not additional volume. If you have an existing analysis built on a
naive Q sum, expect this script's Q totals to be meaningfully lower and
more accurate.

Usage
-----
  python market_analysis_directories.py \
      --group1 /path/to/UG_trials   --name1 "UG" \
      --group2 /path/to/SB_trials   --name2 "SB" \
      --group3 /path/to/MP_trials   --name3 "MP" \
      --out-dir ./results

  # Also works with 2 groups, or with sub-variants you want aggregated
  # by family later (name them e.g. "UG-Penta Hexa", "UG-No Penta Hexa" --
  # see --aggregate-families below).

Output (saved to --out-dir, default = current directory)
------
  - Console tables: mean / std / variance / CI95 per group, for the
    headline totals and for each of Q, X, S broken down by vaccine /
    producer / antigen
  - market_analysis_results.csv       (long-format, all stats, all dims)
  - market_analysis_by_vaccine.png    (Q, mean share ± 95% CI)
  - market_analysis_by_producer.png   (Q, mean share ± 95% CI, producer
                                        names masked as "Producer N")
  - market_analysis_S_by_antigen.png  (S, mean value ± 95% CI)

Flags
-----
  --aggregate-families   Collapse groups into families by stripping the
                          text after the first '-' or space in each name
                          (e.g. "UG-Penta Hexa" -> "UG") before plotting.
                          Off by default -- each --groupN is plotted as
                          its own series unless this is passed.
"""

import json
import argparse
import sys
from pathlib import Path
from collections import defaultdict

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker


# ── generic tree walker ────────────────────────────────────────────────────

def walk(d, path=()):
    """Recursively yield (path_tuple, leaf_value) for every leaf in a nested dict."""
    if isinstance(d, dict):
        for k, v in d.items():
            yield from walk(v, path + (k,))
    else:
        yield path, d


# ── per-file extraction ─────────────────────────────────────────────────────

def extract_trial(filepath: Path) -> dict:
    """
    Load one model result JSON (one trial) and extract F, Q (corrected),
    W, X, S totals and breakdowns.
    """
    with open(filepath) as f:
        data = json.load(f)

    # --- F: active tender-periods (count of nonzero binary entries) -------
    f_count = sum(1 for _, v in walk(data.get("F", {})) if v > 1e-9)

    # --- W: active producer commitments, overall and by producer ----------
    w_by_producer = defaultdict(int)
    for path, v in walk(data.get("W", {})):
        if v > 1e-9:
            w_by_producer[path[0]] += 1
    w_count = sum(w_by_producer.values())

    # --- Q: CORRECTED -- max single-window value per (vaccine, producer) --
    q_max_by_pair = defaultdict(float)
    for path, v in walk(data.get("Q", {})):
        # path = (vaccine, producer, t, tau, discount_segment)
        key = (path[0], path[1])
        if v > q_max_by_pair[key]:
            q_max_by_pair[key] = v

    q_by_vaccine = defaultdict(float)
    q_by_producer = defaultdict(float)
    for (vac, prod), val in q_max_by_pair.items():
        q_by_vaccine[vac] += val
        q_by_producer[prod] += val
    q_total = sum(q_max_by_pair.values())

    # --- X: delivered doses, overall and by vaccine ------------------------
    x_by_vaccine = defaultdict(float)
    x_total = 0.0
    for path, v in walk(data.get("X", {})):
        x_by_vaccine[path[0]] += v
        x_total += v

    # --- I: inventory, excluding period-0 sentinel/outlier values ---------
    i_total = 0.0
    for path, v in walk(data.get("I", {})):
        if v < 1e9:
            i_total += v

    # --- S: missed doses, overall and by antigen ---------------------------
    s_by_antigen = defaultdict(float)
    s_total = 0.0
    for path, v in walk(data.get("S", {})):
        s_by_antigen[path[0]] += v
        s_total += v

    return {
        "F_total": f_count,
        "W_total": w_count,
        "W_by_producer": dict(w_by_producer),
        "Q_total": q_total,
        "Q_by_vaccine": dict(q_by_vaccine),
        "Q_by_producer": dict(q_by_producer),
        "X_total": x_total,
        "X_by_vaccine": dict(x_by_vaccine),
        "I_total": i_total,
        "S_total": s_total,
        "S_by_antigen": dict(s_by_antigen),
        "XQ_ratio": (x_total / q_total) if q_total > 1e-9 else float("nan"),
    }


# ── group loading ─────────────────────────────────────────────────────────

def load_group(directory: Path, name: str) -> dict:
    """Load all .json files in a directory as individual trials."""
    files = sorted(directory.glob("*.json"))
    if not files:
        print(f"  [warning] No .json files found in {directory}")
        return {"name": name, "trials": []}

    trials = []
    for fp in files:
        try:
            trials.append(extract_trial(fp))
        except Exception as e:
            print(f"  [error] {fp.name}: {e}")

    print(f"  Loaded {len(trials)} files  ->  '{name}'  ({directory})")
    return {"name": name, "trials": trials}


# ── statistics ────────────────────────────────────────────────────────────

def compute_stats(values: list) -> dict:
    a = np.array(values, dtype=float)
    n = len(a)
    s = float(a.std())
    return {
        "mean": float(a.mean()),
        "std": s,
        "variance": float(a.var()),
        "ci95": 1.96 * s / np.sqrt(n) if n > 1 else 0.0,
        "min": float(a.min()),
        "max": float(a.max()),
        "n": n,
    }


def summarise_group(group: dict) -> dict:
    trials = group["trials"]
    empty = {"name": group["name"], "totals": {}, "by_vaccine_Q": {},
             "by_vaccine_X": {}, "by_producer_Q": {}, "by_producer_W": {},
             "by_antigen_S": {}}
    if not trials:
        return empty

    def summarise_dim(key):
        all_keys = sorted({k for t in trials for k in t[key]})
        return {k: compute_stats([t[key].get(k, 0.0) for t in trials]) for k in all_keys}

    return {
        "name": group["name"],
        "totals": {
            metric: compute_stats([t[metric] for t in trials])
            for metric in ("F_total", "W_total", "Q_total", "X_total", "I_total", "S_total", "XQ_ratio")
        },
        "by_vaccine_Q": summarise_dim("Q_by_vaccine"),
        "by_vaccine_X": summarise_dim("X_by_vaccine"),
        "by_producer_Q": summarise_dim("Q_by_producer"),
        "by_producer_W": summarise_dim("W_by_producer"),
        "by_antigen_S": summarise_dim("S_by_antigen"),
    }


# ── console output ────────────────────────────────────────────────────────

def print_totals_table(summaries: list):
    names = [s["name"] for s in summaries]
    sep = "=" * 110

    print(f"\n{sep}\n  HEADLINE TOTALS -- MEAN (STD) PER TRIAL\n{sep}")
    header = f"  {'Metric':16s}" + "".join(f"{n:>22s}" for n in names)
    print(header)
    print("  " + "-" * 108)
    for label, key in [
        ("F (tenders)", "F_total"), ("W (commitments)", "W_total"),
        ("Q (corrected)", "Q_total"), ("X (delivered)", "X_total"),
        ("I (inventory)", "I_total"), ("S (missed)", "S_total"),
        ("X/Q ratio", "XQ_ratio"),
    ]:
        row = f"  {label:16s}"
        for s in summaries:
            st = s["totals"].get(key)
            if not st:
                row += f"{'n/a':>22s}"
            elif key == "XQ_ratio":
                row += f"{st['mean']*100:18.1f}% ({st['std']*100:.1f}%)"
            else:
                row += f"{st['mean']:>14,.0f} ({st['std']:>6,.0f})"
        print(row)


def print_breakdown_table(summaries: list, dim_key: str, title: str, top_n: int = 15):
    names = [s["name"] for s in summaries]
    all_keys = sorted(
        {k for s in summaries for k in s[dim_key]},
        key=lambda k: -max(s[dim_key].get(k, {}).get("mean", 0) for s in summaries),
    )[:top_n]

    sep = "=" * 110
    print(f"\n{sep}\n  {title} -- MEAN (STD), TOP {top_n}\n{sep}")
    header = f"  {'':18s}" + "".join(f"{n:>22s}" for n in names)
    print(header)
    print("  " + "-" * 108)
    for key in all_keys:
        row = f"  {key:18s}"
        for s in summaries:
            st = s[dim_key].get(key)
            row += f"{st['mean']:>14,.0f} ({st['std']:>6,.0f})" if st else f"{'-':>22s}"
        print(row)


# ── CSV export ────────────────────────────────────────────────────────────

def export_csv(summaries: list, out_path: Path):
    rows = []
    for s in summaries:
        for metric, st in s["totals"].items():
            rows.append({"group": s["name"], "dimension": "total", "category": metric, **st})
        for dim, key in [("vaccine_Q", "by_vaccine_Q"), ("vaccine_X", "by_vaccine_X"),
                          ("producer_Q", "by_producer_Q"), ("producer_W", "by_producer_W"),
                          ("antigen_S", "by_antigen_S")]:
            for cat, st in s[key].items():
                rows.append({"group": s["name"], "dimension": dim, "category": cat, **st})
    pd.DataFrame(rows).to_csv(out_path, index=False)
    print(f"\nCSV saved -> {out_path}")


# ── plotting ──────────────────────────────────────────────────────────────

COLORS = [
    "#000000", "#E69F00", "#56B4E9", "#009E73", "#F0E442",
    "#0072B2", "#D55E00", "#CC79A7", "#228833", "#AA3377",
]


def millions(x, _):
    if x >= 1e6:
        return f"{x/1e6:.1f}M"
    if x >= 1e3:
        return f"{x/1e3:.0f}K"
    return f"{x:.0f}"


def _aggregate_by_prefix(summaries: list, dim_key: str) -> dict:
    """Collapse groups into families by stripping text after '-' or space."""
    def family(name: str) -> str:
        return name.split("-")[0].split()[0]

    family_trials = defaultdict(lambda: defaultdict(list))
    for s in summaries:
        fam = family(s["name"])
        for cat, st in s[dim_key].items():
            family_trials[fam][cat].append(st)

    aggregated = {}
    for fam, cats in family_trials.items():
        aggregated[fam] = {}
        for cat, stat_list in cats.items():
            ns = np.array([st["n"] for st in stat_list], dtype=float)
            means = np.array([st["mean"] for st in stat_list], dtype=float)
            stds = np.array([st["std"] for st in stat_list], dtype=float)
            N = ns.sum()
            if N == 0:
                continue
            grand_mean = (ns * means).sum() / N
            grand_var = ((ns * (stds ** 2 + (means - grand_mean) ** 2)).sum()) / N
            grand_std = float(np.sqrt(grand_var))
            grand_n = int(N)
            aggregated[fam][cat] = {
                "mean": float(grand_mean), "std": grand_std, "variance": float(grand_var),
                "ci95": 1.96 * grand_std / np.sqrt(grand_n) if grand_n > 1 else 0.0,
                "n": grand_n,
            }
    return aggregated


def _grouped_bar_with_ci(ax, categories, agg, series_names, colors, title, ylabel, as_share=False):
    n = len(series_names)
    x = np.arange(len(categories))
    w = 0.8 / n

    for i, (name, color) in enumerate(zip(series_names, colors)):
        cat_stats = agg.get(name, {})
        if as_share:
            total_mean = sum(cat_stats.get(c, {}).get("mean", 0.0) for c in categories)
            if total_mean == 0:
                continue
            vals = [cat_stats.get(c, {}).get("mean", 0.0) / total_mean * 100 for c in categories]
            errs = [cat_stats.get(c, {}).get("ci95", 0.0) / total_mean * 100 for c in categories]
        else:
            vals = [cat_stats.get(c, {}).get("mean", 0.0) for c in categories]
            errs = [cat_stats.get(c, {}).get("ci95", 0.0) for c in categories]

        offset = (i - (n - 1) / 2) * w
        ax.bar(x + offset, vals, w, label=name, color=color, edgecolor="black", linewidth=0.4, alpha=0.9)
        ax.errorbar(x + offset, vals, yerr=errs, fmt="none", color="black", capsize=3, linewidth=1)

    ax.set_xticks(x)
    ax.set_xticklabels(categories, rotation=40, ha="right", fontsize=8.5)
    if as_share:
        ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"{v:.0f}%"))
    else:
        ax.yaxis.set_major_formatter(mticker.FuncFormatter(millions))
    ax.set_title(title, fontsize=11, fontweight="bold")
    ax.set_ylabel(ylabel, fontsize=9)
    ax.grid(axis="y", alpha=0.25)
    ax.legend(fontsize=8, title="Group")
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def make_plots(summaries: list, out_dir: Path, aggregate_families: bool, top_n: int):
    if aggregate_families:
        agg_vac = _aggregate_by_prefix(summaries, "by_vaccine_Q")
        agg_ant = _aggregate_by_prefix(summaries, "by_antigen_S")
        agg_prod = _aggregate_by_prefix(summaries, "by_producer_Q")
        series_names = sorted(agg_vac.keys())
    else:
        agg_vac = {s["name"]: s["by_vaccine_Q"] for s in summaries}
        agg_ant = {s["name"]: s["by_antigen_S"] for s in summaries}
        agg_prod = {s["name"]: s["by_producer_Q"] for s in summaries}
        series_names = [s["name"] for s in summaries]

    colors = [COLORS[i % len(COLORS)] for i in range(len(series_names))]

    # -- mask producer identities as Producer 1, 2, ... ranked by total volume --
    raw_prods = sorted({k for cats in agg_prod.values() for k in cats})
    prod_totals = {p: sum(agg_prod[s].get(p, {}).get("mean", 0.0) for s in series_names) for p in raw_prods}
    ranked_prods = sorted(raw_prods, key=lambda p: -prod_totals[p])
    prod_label_map = {p: f"Producer {i+1}" for i, p in enumerate(ranked_prods)}
    agg_prod_masked = {s: {prod_label_map[p]: st for p, st in cats.items()} for s, cats in agg_prod.items()}
    all_prods_masked = [prod_label_map[p] for p in ranked_prods][:top_n]

    all_vacs = sorted({k for cats in agg_vac.values() for k in cats},
                       key=lambda v: -sum(agg_vac[s].get(v, {}).get("mean", 0.0) for s in series_names))[:top_n]
    all_ants = sorted({k for cats in agg_ant.values() for k in cats},
                       key=lambda a: -sum(agg_ant[s].get(a, {}).get("mean", 0.0) for s in series_names))[:top_n]

    # Chart 1: Q by vaccine (share, matches original script's style)
    fig, ax = plt.subplots(figsize=(12, 6))
    fig.suptitle("Q (corrected) by vaccine -- mean share +/- 95% CI", fontsize=12, fontweight="bold", y=1.03)
    _grouped_bar_with_ci(ax, all_vacs, agg_vac, series_names, colors,
                          "By vaccine", "Mean share of Q (%)", as_share=True)
    fig.tight_layout()
    p = out_dir / "market_analysis_by_vaccine.png"
    fig.savefig(p, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Plot saved -> {p}")

    # Chart 2: Q by producer (share, masked)
    fig, ax = plt.subplots(figsize=(12, 6))
    fig.suptitle("Q (corrected) by producer -- mean share +/- 95% CI", fontsize=12, fontweight="bold", y=1.03)
    _grouped_bar_with_ci(ax, all_prods_masked, agg_prod_masked, series_names, colors,
                          "By producer", "Mean share of Q (%)", as_share=True)
    fig.tight_layout()
    p = out_dir / "market_analysis_by_producer.png"
    fig.savefig(p, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Plot saved -> {p}")

    # Chart 3: S by antigen (absolute values, not share -- missed doses matter in absolute terms)
    fig, ax = plt.subplots(figsize=(11, 6))
    fig.suptitle("S (missed doses) by antigen -- mean +/- 95% CI", fontsize=12, fontweight="bold", y=1.03)
    _grouped_bar_with_ci(ax, all_ants, agg_ant, series_names, colors,
                          "By antigen", "Mean missed doses", as_share=False)
    fig.tight_layout()
    p = out_dir / "market_analysis_S_by_antigen.png"
    fig.savefig(p, dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"Plot saved -> {p}")


# ── CLI ───────────────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--group1", required=True, metavar="DIR")
    p.add_argument("--name1", default="Group 1", metavar="NAME")
    p.add_argument("--group2", required=True, metavar="DIR")
    p.add_argument("--name2", default="Group 2", metavar="NAME")
    for i in range(3, 11):
        p.add_argument(f"--group{i}", required=False, metavar="DIR", help=f"Optional group {i}")
        p.add_argument(f"--name{i}", default=f"Group {i}", metavar="NAME")
    p.add_argument("--out-dir", default=".", metavar="DIR",
                    help="Where to save CSV and PNG (default: current directory)")
    p.add_argument("--aggregate-families", action="store_true",
                    help="Collapse groups into families by name prefix before plotting")
    p.add_argument("--top-n", type=int, default=15, help="Max categories shown in plots (default: 15)")
    return p.parse_args()


def main():
    args = parse_args()
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    specs = [(args.group1, args.name1), (args.group2, args.name2)]
    for i in range(3, 11):
        grp = getattr(args, f"group{i}", None)
        if grp:
            specs.append((grp, getattr(args, f"name{i}")))

    groups = []
    for path_str, name in specs:
        d = Path(path_str)
        if not d.exists():
            print(f"[error] Directory not found: {d}")
            sys.exit(1)
        groups.append(load_group(d, name))

    summaries = [summarise_group(g) for g in groups]

    print_totals_table(summaries)
    print_breakdown_table(summaries, "by_vaccine_Q", "Q (CORRECTED) BY VACCINE", top_n=args.top_n)
    print_breakdown_table(summaries, "by_producer_Q", "Q (CORRECTED) BY PRODUCER", top_n=args.top_n)
    print_breakdown_table(summaries, "by_antigen_S", "S (MISSED DOSES) BY ANTIGEN", top_n=args.top_n)

    export_csv(summaries, out_dir / "market_analysis_results.csv")
    make_plots(summaries, out_dir, args.aggregate_families, args.top_n)

    print(f"\nDone. All output saved to {out_dir.resolve()}")


if __name__ == "__main__":
    main()