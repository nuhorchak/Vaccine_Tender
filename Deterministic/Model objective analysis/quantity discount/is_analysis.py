"""
Inventory (I) and Missed Doses (S) Analysis
=============================================
For each group of 30 trials:

  I  — Vaccine inventory (indexed by vaccine, time t=1..10)
       Summarised as: mean inventory across t=1..10 per vaccine per trial,
       then mean / std / 95% CI across the 30 trials.

  S  — Missed doses (indexed by antigen/disease, time t=0..10)
       Rolling-horizon variable: only t=10 is the true final shortfall.
       Summarised as: value at t=10 per disease per trial,
       then mean / std / 95% CI across the 30 trials.

Both variables are plotted on a shared 3x2 grid for easy model comparison.

Usage
-----
  python is_analysis.py \\
      --group1 /path/to/model_A  --name1 "Model A" \\
      --group2 /path/to/model_B  --name2 "Model B" \\
      --group3 /path/to/model_C  --name3 "Model C"   # optional

Output  (--out-dir, default = current directory)
------
  - Console summary table
  - is_analysis_results.csv
  - is_analysis_plots.png
"""

import json
import argparse
import sys
from pathlib import Path

import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker


# ── extraction ────────────────────────────────────────────────────────────────

def extract_is(filepath: Path) -> dict:
    """
    Load one JSON file and return:
      {
        "I_by_vaccine":  {"PCV": 1072059.7, ...},   # mean of t=1..10
        "S_by_disease":  {"Diphtheria": 1588860.7, ...},  # value at t=10
      }
    """
    with open(filepath) as f:
        data = json.load(f)

    # ── I: mean across t=1..10 per vaccine ──
    I = data["I"]
    I_by_vaccine = {}
    for vaccine in sorted(I.keys()):
        vals = [
            I[vaccine][t]["1"]
            for t in I[vaccine]
            if t != "0"
        ]
        I_by_vaccine[vaccine] = float(np.mean(vals)) if vals else 0.0

    # ── S: value at t=10 per disease ──
    S = data["S"]
    S_by_disease = {}
    for disease in sorted(S.keys()):
        S_by_disease[disease] = float(S[disease].get("10", {}).get("1", 0.0))

    return {
        "I_by_vaccine": I_by_vaccine,
        "S_by_disease": S_by_disease,
    }


# ── group loading ─────────────────────────────────────────────────────────────

def load_group(directory: Path, name: str) -> dict:
    files = sorted(directory.glob("*.json"))
    if not files:
        print(f"  [warning] No .json files found in {directory}")
        return {"name": name, "trials": []}

    trials = []
    for fp in files:
        try:
            trials.append(extract_is(fp))
        except Exception as e:
            print(f"  [error] {fp.name}: {e}")

    print(f"  Loaded {len(trials)} files  →  '{name}'  ({directory})")
    return {"name": name, "trials": trials}


# ── statistics ────────────────────────────────────────────────────────────────

def compute_stats(values: list) -> dict:
    a   = np.array(values, dtype=float)
    n   = len(a)
    m   = float(a.mean())
    s   = float(a.std())
    # 95% CI half-width using z=1.96 (suitable for n=30)
    ci  = 1.96 * s / np.sqrt(n) if n > 1 else 0.0
    return {
        "mean": m, "std": s, "variance": float(a.var()),
        "ci95": ci, "min": float(a.min()), "max": float(a.max()), "n": n,
    }

def summarise_group(group: dict) -> dict:
    trials = group["trials"]
    if not trials:
        return {"name": group["name"]}

    all_vaccines = sorted({k for t in trials for k in t["I_by_vaccine"]})
    all_diseases = sorted({k for t in trials for k in t["S_by_disease"]})

    return {
        "name": group["name"],
        "I": {
            v: compute_stats([t["I_by_vaccine"].get(v, 0.0) for t in trials])
            for v in all_vaccines
        },
        "S": {
            d: compute_stats([t["S_by_disease"].get(d, 0.0) for t in trials])
            for d in all_diseases
        },
        "I_total": compute_stats([
            sum(t["I_by_vaccine"].values()) for t in trials
        ]),
        "S_total": compute_stats([
            sum(t["S_by_disease"].values()) for t in trials
        ]),
    }


# ── console output ────────────────────────────────────────────────────────────

def print_table(summaries: list):
    names = [s["name"] for s in summaries]
    sep   = "=" * 110

    def f(v): return f"{v:>14,.0f}"
    def fp(v): return f"{v:>12,.0f}"

    for var, dim_key, label, what in [
        ("I", "I", "INVENTORY (I) — mean across t=1..10 per vaccine",
         "Mean inventory (doses)"),
        ("S", "S", "MISSED DOSES (S) — value at t=10 per disease",
         "Missed doses at t=10"),
    ]:
        print(f"\n{sep}")
        print(f"  {label}")
        print(sep)

        header = f"  {'':28s}"
        for n in names:
            header += f"  {n[:14]:>14s} {'±95% CI':>12s} {'Std':>12s}"
        print(header)
        print("  " + "-" * 108)

        # Total row
        row = f"  {'TOTAL':<28s}"
        for s in summaries:
            st = s[f"{var}_total"]
            row += f"  {f(st['mean'])} {fp(st['ci95'])} {fp(st['std'])}"
        print(row)
        print("  " + "-" * 108)

        all_keys = sorted({k for s in summaries for k in s[dim_key]})
        for key in all_keys:
            row = f"  {key:<28s}"
            for s in summaries:
                st = s[dim_key].get(key)
                if st:
                    row += f"  {f(st['mean'])} {fp(st['ci95'])} {fp(st['std'])}"
                else:
                    row += f"  {'—':>14s} {'—':>12s} {'—':>12s}"
            print(row)

    print(f"\n{sep}\n")


# ── CSV export ────────────────────────────────────────────────────────────────

def export_csv(summaries: list, out_path: Path):
    rows = []
    for s in summaries:
        for var, dim_key in [("I", "I"), ("S", "S")]:
            st = s[f"{var}_total"]
            rows.append({"model": s["name"], "variable": var,
                         "category": "TOTAL", **st})
            for cat, st in s[dim_key].items():
                rows.append({"model": s["name"], "variable": var,
                             "category": cat, **st})
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
    if abs(x) >= 1e9:  return f"{x/1e9:.1f}B"
    if abs(x) >= 1e6:  return f"{x/1e6:.1f}M"
    if abs(x) >= 1e3:  return f"{x/1e3:.0f}K"
    return f"{x:.0f}"

def grouped_bar_ci(ax, categories, summaries, dim_key,
                   title, ylabel, colors, exclude_zero_mean=False):
    """
    Grouped bar chart with 95% CI error bars.
    exclude_zero_mean: skip categories where ALL models have mean=0
    """
    if exclude_zero_mean:
        categories = [
            c for c in categories
            if any(s[dim_key].get(c, {}).get("mean", 0) != 0 for s in summaries)
        ]
    if not categories:
        ax.set_visible(False)
        return

    n  = len(summaries)
    x  = np.arange(len(categories))
    w  = 0.7 / n
    os = np.linspace(-(n - 1) / 2, (n - 1) / 2, n) * w

    for i, (s, color) in enumerate(zip(summaries, colors)):
        means = [s[dim_key].get(c, {}).get("mean",  0.0) for c in categories]
        ci95s = [s[dim_key].get(c, {}).get("ci95",  0.0) for c in categories]
        ax.bar(x + os[i], means, w, label=s["name"],
               color=color, edgecolor="white", linewidth=0.4, alpha=0.88, zorder=3)
        ax.errorbar(x + os[i], means, yerr=ci95s,
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


def grouped_bar_stat(ax, categories, summaries, dim_key, stat,
                     title, ylabel, colors, exclude_zero_mean=False):
    """Simple grouped bar for std or variance (no error bars)."""
    if exclude_zero_mean:
        categories = [
            c for c in categories
            if any(s[dim_key].get(c, {}).get("mean", 0) != 0 for s in summaries)
        ]
    if not categories:
        ax.set_visible(False)
        return

    n  = len(summaries)
    x  = np.arange(len(categories))
    w  = 0.7 / n
    os = np.linspace(-(n - 1) / 2, (n - 1) / 2, n) * w

    for i, (s, color) in enumerate(zip(summaries, colors)):
        vals = [s[dim_key].get(c, {}).get(stat, 0.0) for c in categories]
        ax.bar(x + os[i], vals, w, label=s["name"],
               color=color, edgecolor="white", linewidth=0.4, alpha=0.88, zorder=3)

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
    colors = COLORS[:len(summaries)]
    names  = [s["name"] for s in summaries]

    fig, axes = plt.subplots(1, 2, figsize=(14, 7))
    fig.suptitle(
        "Inventory (I) & Missed Doses (S) — Aggregate Total\nMean ± 95% CI across 30 Trials",
        fontsize=13, fontweight="bold", y=1.01
    )

    for ax, var, title, ylabel in [
        (axes[0], "I_total",
         "Total Inventory (I)\n(mean of t=1..10, summed across all vaccines)",
         "Total inventory (doses)"),
        (axes[1], "S_total",
         "Total Missed Doses (S)\n(value at t=10, summed across all diseases)",
         "Total missed doses"),
    ]:
        x     = np.arange(len(summaries))
        means = [s[var]["mean"] for s in summaries]
        ci95s = [s[var]["ci95"] for s in summaries]

        bars = ax.bar(x, means, color=colors, edgecolor="white",
                      linewidth=0.5, alpha=0.88, width=0.5, zorder=3)
        ax.errorbar(x, means, yerr=ci95s,
                    fmt="none", color="black", capsize=6, linewidth=1.5, zorder=4)

        # Value labels above bars
        for bar, m, ci in zip(bars, means, ci95s):
            ax.text(bar.get_x() + bar.get_width() / 2,
                    m + ci + (max(means) * 0.01),
                    millions(m, None),
                    ha="center", va="bottom", fontsize=9, fontweight="bold")

        ax.set_xticks(x)
        ax.set_xticklabels(names, fontsize=10)
        ax.yaxis.set_major_formatter(mticker.FuncFormatter(millions))
        ax.set_title(title, fontsize=10, fontweight="bold", pad=8)
        ax.set_ylabel(ylabel, fontsize=9)
        ax.grid(axis="y", alpha=0.25, zorder=0)
        ax.spines["top"].set_visible(False)
        ax.spines["right"].set_visible(False)

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
    export_csv(summaries,  out_dir / "is_analysis_results.csv")
    make_plots(summaries,  out_dir / "is_analysis_plots.png")


if __name__ == "__main__":
    main()
