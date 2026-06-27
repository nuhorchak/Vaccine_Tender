"""
Market Participation Analysis
==============================
Computes mean, standard deviation, and variance of total Q
(by vaccine and by manufacturer) across 30 trials per model group.
Compares up to 3 model groups side-by-side with plots.

Usage
-----
  python market_participation_analysis.py \
      --group1 /path/to/model_A  --name1 "Model A" \
      --group2 /path/to/model_B  --name2 "Model B" \
      --group3 /path/to/model_C  --name3 "Model C"

  # Two groups also works (--group3 is optional):
  python market_participation_analysis.py \
      --group1 /path/to/DE  --name1 "DE" \
      --group2 /path/to/SB  --name2 "SB"

Output (saved to --out-dir, default = current directory)
------
  - Console table: mean, std, variance per vaccine and manufacturer
  - market_participation_results.csv
  - market_participation_plots.png
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


# ── Q extraction ──────────────────────────────────────────────────────────────

def extract_q(filepath: Path) -> dict:
    """
    Load one JSON file.
    Returns total Q summed by vaccine and by manufacturer.
    """
    with open(filepath) as f:
        data = json.load(f)

    Q = data["Q"]
    by_vac = defaultdict(float)
    by_mfr = defaultdict(float)
    total  = 0.0

    for vac, mfr_dict in Q.items():
        for mfr, start_dict in mfr_dict.items():
            for _, end_dict in start_dict.items():
                for _, disc_dict in end_dict.items():
                    for _, qty in disc_dict.items():
                        by_vac[vac] += qty
                        by_mfr[mfr] += qty
                        total       += qty

    return {
        "by_vaccine":      dict(by_vac),
        "by_manufacturer": dict(by_mfr),
        "total":           total,
    }


# ── group loading ─────────────────────────────────────────────────────────────

def load_group(directory: Path, name: str) -> dict:
    """Load all .json files in a directory as individual trials."""
    files = sorted(directory.glob("*.json"))
    if not files:
        print(f"  [warning] No .json files found in {directory}")
        return {"name": name, "trials": []}

    trials = []
    for fp in files:
        try:
            trials.append(extract_q(fp))
        except Exception as e:
            print(f"  [error] {fp.name}: {e}")

    print(f"  Loaded {len(trials)} files  →  '{name}'  ({directory})")
    return {"name": name, "trials": trials}


# ── statistics ────────────────────────────────────────────────────────────────

def compute_stats(values: list) -> dict:
    a  = np.array(values, dtype=float)
    n  = len(a)
    s  = float(a.std())
    return {
        "mean":     float(a.mean()),
        "std":      s,
        "variance": float(a.var()),
        "ci95":     1.96 * s / np.sqrt(n) if n > 1 else 0.0,
        "min":      float(a.min()),
        "max":      float(a.max()),
        "n":        n,
    }

def summarise_group(group: dict) -> dict:
    trials = group["trials"]
    if not trials:
        return {"name": group["name"], "total": {}, "by_vaccine": {}, "by_manufacturer": {}}

    all_vacs = sorted({k for t in trials for k in t["by_vaccine"]})
    all_mfrs = sorted({k for t in trials for k in t["by_manufacturer"]})

    return {
        "name":  group["name"],
        "total": compute_stats([t["total"] for t in trials]),
        "by_vaccine": {
            v: compute_stats([t["by_vaccine"].get(v, 0.0) for t in trials])
            for v in all_vacs
        },
        "by_manufacturer": {
            m: compute_stats([t["by_manufacturer"].get(m, 0.0) for t in trials])
            for m in all_mfrs
        },
    }


# ── console output ────────────────────────────────────────────────────────────

def print_table(summaries: list):
    names = [s["name"] for s in summaries]
    sep   = "=" * 100

    def fmt(v): return f"{v:>16,.0f}"

    print(f"\n{sep}")
    print("  TOTAL Q PER TRIAL")
    print(sep)
    header = f"  {'':30s}"
    for n in names:
        header += f"  {n:>16s}"
    print(header)
    print("  " + "-" * 98)
    for stat in ("mean", "std", "variance"):
        row = f"  {stat.capitalize():<30s}"
        for s in summaries:
            row += fmt(s["total"].get(stat, 0))
        print(row)

    for dim_key, dim_label in [("by_vaccine", "BY VACCINE"), ("by_manufacturer", "BY MANUFACTURER")]:
        all_keys = sorted({k for s in summaries for k in s[dim_key]})
        print(f"\n{sep}")
        print(f"  {dim_label}")
        print(sep)

        # Sub-header
        header = f"  {'':28s}"
        for n in names:
            header += f"  {n[:14]:>14s} {'Std':>12s} {'Variance':>16s}"
        print(header)
        print("  " + "-" * 98)

        for key in all_keys:
            row = f"  {key:<28s}"
            for s in summaries:
                st = s[dim_key].get(key)
                if st:
                    row += f"  {st['mean']:>14,.0f} {st['std']:>12,.0f} {st['variance']:>16,.0f}"
                else:
                    row += f"  {'—':>14s} {'—':>12s} {'—':>16s}"
            print(row)

    print(f"\n{sep}\n")


# ── CSV export ────────────────────────────────────────────────────────────────

def export_csv(summaries: list, out_path: Path):
    rows = []
    for s in summaries:
        st = s["total"]
        rows.append({"model": s["name"], "dimension": "total", "category": "total",
                     "mean": st["mean"], "std": st["std"], "variance": st["variance"],
                     "min": st["min"], "max": st["max"], "n": st["n"]})
        for dim, key in [("vaccine", "by_vaccine"), ("manufacturer", "by_manufacturer")]:
            for cat, st in s[key].items():
                rows.append({"model": s["name"], "dimension": dim, "category": cat,
                             "mean": st["mean"], "std": st["std"], "variance": st["variance"],
                             "min": st["min"], "max": st["max"], "n": st["n"]})
    pd.DataFrame(rows).to_csv(out_path, index=False)
    print(f"CSV saved  →  {out_path}")


# ── plotting ──────────────────────────────────────────────────────────────────

COLORS = [
    "#000000",  # black        (okabe-ito 1)
    "#E69F00",  # orange       (okabe-ito 2)
    "#56B4E9",  # sky blue     (okabe-ito 3)
    "#009E73",  # green        (okabe-ito 4)
    "#F0E442",  # yellow       (okabe-ito 5)
    "#0072B2",  # blue         (okabe-ito 6)
    "#D55E00",  # vermillion   (okabe-ito 7)
    "#CC79A7",  # pink         (okabe-ito 8)
    "#228833",  # dark green   (tol_bright)
    "#AA3377",  # purple       (tol_bright)
]

def millions(x, _):
    if x >= 1e6:  return f"{x/1e6:.1f}M"
    if x >= 1e3:  return f"{x/1e3:.0f}K"
    return f"{x:.0f}"

def grouped_bar(ax, categories, summaries, dim_key, title, ylabel, colors):
    """Grouped bar chart — mean ± 95% CI only."""
    n  = len(summaries)
    x  = np.arange(len(categories))
    w  = 0.7 / n
    os = np.linspace(-(n - 1) / 2, (n - 1) / 2, n) * w

    for i, (s, color) in enumerate(zip(summaries, colors)):
        vals  = [s[dim_key].get(c, {}).get("mean", 0.0) for c in categories]
        ci95s = [s[dim_key].get(c, {}).get("ci95", 0.0) for c in categories]
        ax.bar(x + os[i], vals, w, label=s["name"],
               color=color, edgecolor="white", linewidth=0.4, alpha=0.88, zorder=3)
        ax.errorbar(x + os[i], vals, yerr=ci95s,
                    fmt="none", color="black", capsize=3, linewidth=1, zorder=4)

    ax.set_xticks(x)
    ax.set_xticklabels(categories, rotation=35, ha="right", fontsize=8.5)
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(millions))
    ax.set_title(title, fontsize=10, fontweight="bold", pad=6)
    ax.set_ylabel(ylabel, fontsize=9)
    ax.grid(axis="y", alpha=0.25, zorder=0)
    ax.legend(fontsize=8)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def make_plots(summaries: list, out_path: Path):
    colors   = COLORS[:len(summaries)]
    all_vacs = sorted({k for s in summaries for k in s["by_vaccine"]})
    all_mfrs = sorted({k for s in summaries for k in s["by_manufacturer"]})

    fig, axes = plt.subplots(1, 2, figsize=(18, 7))
    fig.suptitle("Total Q Across 30 Trials — Model Comparison\nMean ± 95% CI",
                 fontsize=13, fontweight="bold", y=1.02)

    grouped_bar(axes[0], all_vacs, summaries, "by_vaccine",
                "By Vaccine — Mean ± 95% CI", "Mean Q (doses)", colors)
    grouped_bar(axes[1], all_mfrs, summaries, "by_manufacturer",
                "By Manufacturer — Mean ± 95% CI", "Mean Q (doses)", colors)

    plt.tight_layout()
    plt.savefig(out_path, dpi=150, bbox_inches="tight")
    print(f"Plot saved →  {out_path}")
    plt.close()


# ── CLI ───────────────────────────────────────────────────────────────────────


# ── CLI ───────────────────────────────────────────────────────────────────────

def parse_args():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--group1", required=True,  metavar="DIR")
    p.add_argument("--name1",  default="Group 1", metavar="NAME")
    p.add_argument("--group2", required=True,  metavar="DIR")
    p.add_argument("--name2",  default="Group 2", metavar="NAME")
    for i in range(3, 11):
        p.add_argument(f"--group{i}", required=False, metavar="DIR",
                       help=f"Optional group {i}")
        p.add_argument(f"--name{i}",  default=f"Group {i}", metavar="NAME")
    p.add_argument("--out-dir", default=".", metavar="DIR",
                   help="Where to save CSV and PNG (default: current directory)")
    return p.parse_args()


def main():
    args    = parse_args()
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
    print_table(summaries)
    export_csv(summaries,  out_dir / "market_participation_results.csv")
    make_plots(summaries,  out_dir / "market_participation_plots.png")


if __name__ == "__main__":
    main()
