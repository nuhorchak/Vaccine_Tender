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
  - market_participation_by_vaccine.png
  - market_participation_by_manufacturer.png
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

# Family-level colors matched to the reference chart palette
FAMILY_COLORS = {
    "UG": "#4C9BE8",  # blue
    "SB": "#D2691E",  # orange-brown
    "MP": "#3CB371",  # teal-green
}

FAMILY_HATCHES = {
    "UG": "",      # solid
    "SB": "///",   # diagonal stripes
    "MP": "...",   # dots
}

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


def _aggregate_by_prefix(summaries: list, dim_key: str) -> dict:
    """
    Collapse the 9 model groups into 3 by stripping the variant suffix
    (e.g. 'UG-Penta Hexa' → 'UG', 'SB-No Penta Hexa' → 'SB').
    Returns {family_name: {category: stats_dict}} where each stats_dict
    is re-computed over all matching trials pooled together.
    """
    from collections import defaultdict

    # Map each summary to its family prefix (text before the first '-' or space)
    def family(name: str) -> str:
        return name.split("-")[0].split()[0]

    # Pool raw per-trial values by family
    family_trials: dict[str, dict[str, list]] = defaultdict(lambda: defaultdict(list))
    for s in summaries:
        fam = family(s["name"])
        for cat, st in s[dim_key].items():
            # Reconstruct approximate per-trial values from mean/std/n using a
            # surrogate: we store (mean, std, n) and later pool via grand stats.
            family_trials[fam][cat].append(st)

    # Grand statistics: pool means weighted by n, combine variances
    aggregated = {}
    for fam, cats in family_trials.items():
        aggregated[fam] = {}
        for cat, stat_list in cats.items():
            ns    = np.array([st["n"]   for st in stat_list], dtype=float)
            means = np.array([st["mean"] for st in stat_list], dtype=float)
            stds  = np.array([st["std"]  for st in stat_list], dtype=float)
            N     = ns.sum()
            grand_mean = (ns * means).sum() / N
            # Pooled variance (between + within)
            grand_var  = ((ns * (stds**2 + (means - grand_mean)**2)).sum()) / N
            grand_std  = float(np.sqrt(grand_var))
            grand_n    = int(N)
            aggregated[fam][cat] = {
                "mean":     float(grand_mean),
                "std":      grand_std,
                "variance": float(grand_var),
                "ci95":     1.96 * grand_std / np.sqrt(grand_n) if grand_n > 1 else 0.0,
                "n":        grand_n,
            }
    return aggregated


def _stacked_share_chart(ax, categories: list, agg: dict, families: list,
                         colors: list, title: str, ylabel: str):
    """
    100 % stacked grouped bar chart.
    Each group of bars (one per vaccine/manufacturer) is normalised to 100 %
    so the y-axis shows share, not absolute doses.
    Error bars show 95 % CI on the share.
    """
    n   = len(families)
    x   = np.arange(len(categories))
    w   = 0.7 / n
    os  = np.linspace(-(n - 1) / 2, (n - 1) / 2, n) * w

    for i, (fam, color) in enumerate(zip(families, colors)):
        cat_stats = agg.get(fam, {})
        total_mean = sum(cat_stats.get(c, {}).get("mean", 0.0) for c in categories)
        if total_mean == 0:
            continue

        shares = []
        ci_shares = []
        for c in categories:
            st   = cat_stats.get(c, {})
            mean = st.get("mean", 0.0)
            ci95 = st.get("ci95", 0.0)
            shares.append(mean / total_mean * 100)
            ci_shares.append(ci95 / total_mean * 100)

        # ax.bar(x + os[i], shares, w, label=fam,
        #        color=color, edgecolor="white", linewidth=0.5, alpha=0.90, zorder=3)
        ax.bar(
        x + os[i],
        shares,
        w,
        label=fam,
        color=color,
        hatch=FAMILY_HATCHES.get(fam, ""),
        edgecolor="black",      # hatch visibility in grayscale
        linewidth=0.6,
        alpha=0.90,
        zorder=3,
        )
        ax.errorbar(x + os[i], shares, yerr=ci_shares,
                    fmt="none", color="black", capsize=3, linewidth=1, zorder=4)

    ax.set_xticks(x)
    ax.set_xticklabels(categories, rotation=40, ha="right", fontsize=8.5)
    ax.yaxis.set_major_formatter(mticker.FuncFormatter(lambda v, _: f"{v:.0f}%"))
    ax.set_title(title, fontsize=10, fontweight="bold", pad=6)
    ax.set_ylabel(ylabel, fontsize=9)
    ax.set_ylim(0, None)
    ax.grid(axis="y", alpha=0.25, zorder=0)
    # ax.legend(fontsize=9, framealpha=0.8)
    ax.legend(
        title="Model",
        fontsize=9,
        framealpha=0.8,
        )
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def make_plots(summaries: list, out_dir: Path):
    # ── aggregate 9 groups → 3 family prefixes ──────────────────────────────
    agg_vac = _aggregate_by_prefix(summaries, "by_vaccine")
    agg_mfr = _aggregate_by_prefix(summaries, "by_manufacturer")

    families  = [f for f in ['UG', 'SB', 'MP'] if f in agg_vac]
    colors    = [FAMILY_COLORS.get(f, COLORS[i]) for i, f in enumerate(families)]
    # Sort vaccines by total mean volume across all families (desc) so highest is leftmost
    raw_vacs = sorted({k for fam in agg_vac.values() for k in fam})
    vac_totals = {
        v: sum(agg_vac[fam].get(v, {}).get('mean', 0.0) for fam in families)
        for v in raw_vacs
    }
    all_vacs = sorted(raw_vacs, key=lambda v: vac_totals[v], reverse=True)

    # Rank manufacturers by total mean volume across all families (desc),
    # then mask real names as Producer 1, Producer 2, ...
    raw_mfrs = sorted({k for fam in agg_mfr.values() for k in fam})
    mfr_totals = {
        m: sum(agg_mfr[fam].get(m, {}).get('mean', 0.0) for fam in families)
        for m in raw_mfrs
    }
    ranked_mfrs = sorted(raw_mfrs, key=lambda m: mfr_totals[m], reverse=True)
    mfr_label_map = {m: f'Producer {i+1}' for i, m in enumerate(ranked_mfrs)}

    # Remap agg_mfr keys to masked labels
    agg_mfr_masked = {
        fam: {mfr_label_map[m]: st for m, st in cats.items()}
        for fam, cats in agg_mfr.items()
    }
    all_mfrs = [mfr_label_map[m] for m in ranked_mfrs]

    SUPTITLE = ("Market Participation Across 30 Trials — Model Comparison\n"
                "Mean share ± 95% CI  (aggregated by model family)")

    # ── Chart 1: By Vaccine ─────────────────────────────────────────────────
    fig1, ax1 = plt.subplots(figsize=(12, 6))
    fig1.suptitle(SUPTITLE, fontsize=12, fontweight="bold", y=1.03)
    _stacked_share_chart(
        ax1, all_vacs, agg_vac, families, colors,
        title="By vaccine",
        ylabel="Mean market participation share (%)",
    )
    fig1.tight_layout()
    path1 = out_dir / "market_participation_by_vaccine.png"
    fig1.savefig(path1, dpi=300, bbox_inches="tight")
    print(f"Plot saved →  {path1}")
    plt.close(fig1)

    # ── Chart 2: By Manufacturer ────────────────────────────────────────────
    fig2, ax2 = plt.subplots(figsize=(12, 6))
    fig2.suptitle(SUPTITLE, fontsize=12, fontweight="bold", y=1.03)
    _stacked_share_chart(
        ax2, all_mfrs, agg_mfr_masked, families, colors,
        title="By manufacturer",
        ylabel="Mean market participation share (%)",
    )
    fig2.tight_layout()
    path2 = out_dir / "market_participation_by_manufacturer.png"
    fig2.savefig(path2, dpi=300, bbox_inches="tight")
    print(f"Plot saved →  {path2}")
    plt.close(fig2)


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
    make_plots(summaries,  out_dir)


if __name__ == "__main__":
    main()
