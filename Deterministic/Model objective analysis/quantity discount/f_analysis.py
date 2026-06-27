"""
F Data Analysis — Distance, Similarity, and Cross-Model Comparison
===================================================================
For each group of 30 trials:
  - Flattens each trial's F matrix into a binary vector
  - Computes pairwise cosine distance & similarity across all 30 trials
  - Summarises: mean, std, variance of distance, similarity, and
    active slots (total and per disease)
  - Compares up to 3 model groups side-by-side in plots

Usage
-----
  python f_analysis.py \\
      --group1 /path/to/model_A  --name1 "Model A" \\
      --group2 /path/to/model_B  --name2 "Model B" \\
      --group3 /path/to/model_C  --name3 "Model C"   # optional

  # Two groups:
  python f_analysis.py \\
      --group1 /path/to/DE  --name1 "DE" \\
      --group2 /path/to/SB  --name2 "SB"

Output (saved to --out-dir, default = current directory)
------
  - Console summary table
  - f_analysis_results.csv
  - f_analysis_plots.png
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
from sklearn.metrics.pairwise import cosine_similarity


# ── F extraction ──────────────────────────────────────────────────────────────

def extract_f(filepath: Path) -> dict:
    """
    Load one JSON file and return:
      {
        "vector":      np.array of 0/1 values (flattened F),
        "by_disease":  {"Hib": 10, "PCV": 6, ...},   # active slot counts
        "total_active": 76,
        "keys":        [(disease, t_start, t_end), ...]  # vector index labels
      }
    """
    with open(filepath) as f:
        data = json.load(f)

    F = data["F"]

    # Build a sorted, stable key order so vectors are comparable across files
    keys = []
    for disease in sorted(F.keys()):
        for t_start in sorted(F[disease].keys(), key=int):
            for t_end in sorted(F[disease][t_start].keys(), key=int):
                keys.append((disease, t_start, t_end))

    vector = np.array([
        1 if F[d][s][e] > 0.5 else 0
        for d, s, e in keys
    ], dtype=float)

    # Active slots and pairwise overlap per disease
    by_disease_slots   = {}   # count of active slots
    by_disease_overlap = {}   # total overlapping periods across all slot pairs

    for disease in sorted(F.keys()):
        active = [
            (int(s), int(e))
            for s in F[disease]
            for e in F[disease][s]
            if F[disease][s][e] > 0.5
        ]
        by_disease_slots[disease]   = len(active)
        by_disease_overlap[disease] = _pairwise_overlap(active)

    return {
        "vector":              vector,
        "by_disease_slots":    by_disease_slots,
        "by_disease_overlap":  by_disease_overlap,
        "total_active":        int(vector.sum()),
        "total_overlap":       sum(by_disease_overlap.values()),
        "keys":                keys,
    }


def _pairwise_overlap(slots: list) -> int:
    """
    Given a list of (t_start, t_end) inclusive intervals,
    return the total number of overlapping period-units summed
    across all unique pairs.

    e.g. (1,5) and (3,7) overlap at periods 3,4,5 → contributes 3.
    """
    total = 0
    for i in range(len(slots)):
        for j in range(i + 1, len(slots)):
            s1, e1 = slots[i]
            s2, e2 = slots[j]
            total += max(0, min(e1, e2) - max(s1, s2) + 1)
    return total


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
            trials.append(extract_f(fp))
        except Exception as e:
            print(f"  [error] {fp.name}: {e}")

    print(f"  Loaded {len(trials)} files  →  '{name}'  ({directory})")
    return {"name": name, "trials": trials}


# ── distance & similarity ─────────────────────────────────────────────────────

def compute_pairwise(trials: list) -> dict:
    """
    Given a list of trial dicts, compute the full pairwise cosine
    similarity/distance matrix and return per-trial summary stats.

    Returns:
      {
        "sim_matrix":  np.array (n x n),
        "dist_matrix": np.array (n x n),
        "per_trial": [
          {"avg_sim": ..., "avg_dist": ..., "min_dist": ..., "max_dist": ...},
          ...
        ]
      }
    """
    matrix = np.vstack([t["vector"] for t in trials])   # (n_trials, n_features)
    sim_matrix  = cosine_similarity(matrix)
    dist_matrix = 1.0 - sim_matrix
    n = len(trials)

    per_trial = []
    for i in range(n):
        # Exclude self (diagonal)
        other_sims  = [sim_matrix[i, j]  for j in range(n) if j != i]
        other_dists = [dist_matrix[i, j] for j in range(n) if j != i]
        per_trial.append({
            "avg_sim":  float(np.mean(other_sims))  if other_sims  else 0.0,
            "avg_dist": float(np.mean(other_dists)) if other_dists else 0.0,
        })

    return {
        "sim_matrix":  sim_matrix,
        "dist_matrix": dist_matrix,
        "per_trial":   per_trial,
    }


# ── group summary ─────────────────────────────────────────────────────────────

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
    """
    Compute mean/std/variance across 30 trials for:
      - avg_sim, avg_dist, min_dist, max_dist   (from pairwise comparison)
      - total_active slots
      - active slots per disease
    """
    trials = group["trials"]
    if not trials:
        return {"name": group["name"]}

    pw = compute_pairwise(trials)

    all_diseases = sorted({d for t in trials for d in t["by_disease_slots"]})

    return {
        "name":         group["name"],
        "pairwise":     pw,
        "n_trials":     len(trials),

        # Distance / similarity stats across trials
        "avg_sim":      compute_stats([p["avg_sim"]  for p in pw["per_trial"]]),
        "avg_dist":     compute_stats([p["avg_dist"] for p in pw["per_trial"]]),

        # Active slots and overlap per disease
        "total_active":   compute_stats([t["total_active"]  for t in trials]),
        "total_overlap":  compute_stats([t["total_overlap"] for t in trials]),
        "by_disease_slots": {
            d: compute_stats([t["by_disease_slots"].get(d, 0) for t in trials])
            for d in all_diseases
        },
        "by_disease_overlap": {
            d: compute_stats([t["by_disease_overlap"].get(d, 0) for t in trials])
            for d in all_diseases
        },
    }


# ── console output ────────────────────────────────────────────────────────────

def print_table(summaries: list):
    names = [s["name"] for s in summaries]
    sep   = "=" * 100

    def f4(v): return f"{v:.4f}"
    def f2(v): return f"{v:.2f}"

    print(f"\n{sep}")
    print("  F ANALYSIS — DISTANCE & SIMILARITY (cosine, averaged across trials)")
    print(sep)

    header = f"  {'Metric':<28}"
    for n in names:
        header += f"  {n[:16]:>16s} {'Std':>10s} {'Variance':>12s}"
    print(header)
    print("  " + "-" * 98)

    for metric, label in [
        ("avg_sim",  "Avg Cosine Similarity"),
        ("avg_dist", "Avg Cosine Distance"),
    ]:
        row = f"  {label:<28}"
        for s in summaries:
            st = s[metric]
            row += f"  {f4(st['mean']):>16s} {f4(st['std']):>10s} {f4(st['variance']):>12s}"
        print(row)

    print(f"\n{sep}")
    print("  ACTIVE SLOTS (F=1 entries)")
    print(sep)

    header2 = f"  {'Category':<28}"
    for n in names:
        header2 += f"  {'Mean':>10s} {'Std':>10s} {'Variance':>12s}"
    print(header2)
    print("  " + "-" * 98)

    # Totals
    for label, key in [("Total active slots", "total_active"), ("Total overlap periods", "total_overlap")]:
        row = f"  {label:<28}"
        for s in summaries:
            st = s[key]
            row += f"  {f2(st['mean']):>10s} {f2(st['std']):>10s} {f2(st['variance']):>12s}"
        print(row)

    all_diseases = sorted({d for s in summaries for d in s["by_disease_slots"]})

    print(f"\n  {'--- Active slots per disease ---':<28}")
    for d in all_diseases:
        row = f"  {d:<28}"
        for s in summaries:
            st = s["by_disease_slots"].get(d)
            if st:
                row += f"  {f2(st['mean']):>10s} {f2(st['std']):>10s} {f2(st['variance']):>12s}"
            else:
                row += f"  {'—':>10s} {'—':>10s} {'—':>12s}"
        print(row)

    print(f"\n  {'--- Overlap periods per disease ---':<28}")
    for d in all_diseases:
        row = f"  {d:<28}"
        for s in summaries:
            st = s["by_disease_overlap"].get(d)
            if st:
                row += f"  {f2(st['mean']):>10s} {f2(st['std']):>10s} {f2(st['variance']):>12s}"
            else:
                row += f"  {'—':>10s} {'—':>10s} {'—':>12s}"
        print(row)

    print(f"\n{sep}\n")


# ── CSV export ────────────────────────────────────────────────────────────────

def export_csv(summaries: list, out_path: Path):
    rows = []
    for s in summaries:
        for metric in ("avg_sim", "avg_dist", "total_active", "total_overlap"):
            st = s[metric]
            rows.append({"model": s["name"], "dimension": "summary",
                         "category": metric, **st})
        for disease, st in s["by_disease_slots"].items():
            rows.append({"model": s["name"], "dimension": "slots_per_disease",
                         "category": disease, **st})
        for disease, st in s["by_disease_overlap"].items():
            rows.append({"model": s["name"], "dimension": "overlap_per_disease",
                         "category": disease, **st})
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




def _ci95(s, key):
    """Return 95% CI half-width for a stats dict."""
    st = s[key]
    return 1.96 * st["std"] / np.sqrt(st["n"]) if st["n"] > 1 else 0.0


def _ci95_lookup(s, cat, lookup_fn):
    st_dict = lookup_fn(s, cat)
    if not st_dict:
        return 0.0
    n = st_dict.get("n", 1)
    return 1.96 * st_dict["std"] / np.sqrt(n) if n > 1 else 0.0


def grouped_bar_ci(ax, categories, summaries, lookup_fn,
                   title, ylabel, colors, fmt_fn=None, x_labels=None):
    """Grouped bar chart — mean ± 95% CI only."""
    n  = len(summaries)
    x  = np.arange(len(categories))
    w  = 0.7 / n
    os = np.linspace(-(n - 1) / 2, (n - 1) / 2, n) * w

    for i, (s, color) in enumerate(zip(summaries, colors)):
        means = [lookup_fn(s, c).get("mean", 0.0)  for c in categories]
        ci95s = [_ci95_lookup(s, c, lookup_fn)      for c in categories]
        ax.bar(x + os[i], means, w, label=s["name"],
               color=color, edgecolor="white", linewidth=0.4, alpha=0.88, zorder=3)
        ax.errorbar(x + os[i], means, yerr=ci95s,
                    fmt="none", color="black", capsize=3, linewidth=1, zorder=4)

    ax.set_xticks(x)
    ax.set_xticklabels(x_labels or categories, rotation=35, ha="right", fontsize=8.5)
    if fmt_fn:
        ax.yaxis.set_major_formatter(mticker.FuncFormatter(fmt_fn))
    ax.set_title(title, fontsize=10, fontweight="bold", pad=6)
    ax.set_ylabel(ylabel, fontsize=9)
    ax.grid(axis="y", alpha=0.25, zorder=0)
    ax.legend(fontsize=8)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)


def make_plots(summaries: list, out_path: Path):
    colors       = COLORS[:len(summaries)]
    all_diseases = sorted({d for s in summaries for d in s["by_disease_slots"]})

    # ── lookup helpers returning a stats dict ──────────────────────────────────
    def get_sim(s, cat):
        return s["avg_sim"] if cat == "avg_sim" else {}

    def get_dist(s, cat):
        return s["avg_dist"] if cat == "avg_dist" else {}

    def get_overlap(s, cat):
        return s["by_disease_overlap"].get(cat, {})

    # ── 3 subplots: similarity | distance | overlap ────────────────────────────
    fig, axes = plt.subplots(1, 3, figsize=(18, 6))
    fig.suptitle(
        "F Analysis — Distance, Similarity & Overlapping Periods\nMean ± 95% CI across 30 Trials",
        fontsize=13, fontweight="bold", y=1.02
    )

    # Plot 1: Avg Cosine Similarity
    grouped_bar_ci(
        axes[0], ["avg_sim"], summaries, get_sim,
        "Avg Cosine Similarity\nMean ± 95% CI", "Cosine Similarity", colors,
        fmt_fn=lambda x, _: f"{x:.3f}",
        x_labels=["Avg Similarity"],
    )

    # Plot 2: Avg Cosine Distance
    grouped_bar_ci(
        axes[1], ["avg_dist"], summaries, get_dist,
        "Avg Cosine Distance\nMean ± 95% CI", "Cosine Distance", colors,
        fmt_fn=lambda x, _: f"{x:.3f}",
        x_labels=["Avg Distance"],
    )

    # Plot 3: Overlapping Periods by Disease
    grouped_bar_ci(
        axes[2], all_diseases, summaries, get_overlap,
        "Overlapping Tender Periods by Disease\nMean ± 95% CI", "Overlap periods", colors,
    )

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
    export_csv(summaries,  out_dir / "f_analysis_results.csv")
    make_plots(summaries,  out_dir / "f_analysis_plots.png")


if __name__ == "__main__":
    main()
