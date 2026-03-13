"""
plot_benchmarks.py  -  Comprehensive benchmark visualisation for pForest on Tofino2.

Usage:
    python3 src/plot_benchmarks.py                         # auto-pick latest run
    python3 src/plot_benchmarks.py --report benchmark_reports/benchmark_all_*.json
    python3 src/plot_benchmarks.py --outdir plots/

Outputs a directory of PNG files (one per section) + a merged PDF.
"""

from __future__ import annotations
import argparse
import json
import math
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import matplotlib.ticker as mticker
from matplotlib.colors import LinearSegmentedColormap
import numpy as np

# ---------------------------------------------------------------------------
# Constants / style
# ---------------------------------------------------------------------------
ROOT = Path(__file__).resolve().parent.parent
REPORTS_DIR = ROOT / "benchmark_reports"

TOFINO2_MAX_STAGES  = 20
TOFINO2_SRAM_TOTAL  = 80 * 20   # 80 SRAM per stage × 20 stages  (approx)
TOFINO2_TCAM_TOTAL  = 12 * 20
RESOURCE_CAP_STAGES = 16         # soft cap used in benchmark

# Colour palette (accessible)
C_BLUE   = "#2E86AB"
C_ORANGE = "#E07B54"
C_GREEN  = "#57A773"
C_RED    = "#D62246"
C_PURPLE = "#7B2D8B"
C_GREY   = "#7F8C8D"
C_YELLOW = "#F4D03F"

COMPILE_COLORS = {
    "SUCCESS": C_GREEN,
    "TIMEOUT": C_ORANGE,
    "ERROR":   C_RED,
    "SKIPPED": C_GREY,
    "N/A":     "#cccccc",
}

plt.rcParams.update({
    "figure.facecolor": "white",
    "axes.facecolor":   "#f7f7f7",
    "axes.grid":        True,
    "grid.color":       "white",
    "grid.linewidth":   0.8,
    "font.family":      "DejaVu Sans",
    "font.size":        10,
    "axes.titlesize":   11,
    "axes.labelsize":   10,
    "legend.fontsize":  9,
    "figure.dpi":       120,
})

# ---------------------------------------------------------------------------
# Data loading & merging
# ---------------------------------------------------------------------------

def _get_hw(r: Dict) -> Optional[Dict]:
    """Return the mau sub-dict if HW data was captured."""
    c = r.get("compile", {})
    mau_outer = c.get("mau", {})
    mau_inner = mau_outer.get("mau", {})
    if mau_inner.get("total_sram") is not None:
        return mau_inner
    return None

def _get_summary_hw(r: Dict) -> Optional[Dict]:
    """Return the summary (table_summary.log) sub-dict if present."""
    c = r.get("compile", {})
    mau_outer = c.get("mau", {})
    s = mau_outer.get("summary", {})
    return s if s else None


def load_and_merge(json_paths: List[Path]) -> List[Dict]:
    """
    Load multiple report files.  For each config_id keep the entry that has the
    most HW data (latest run with working parser wins).
    """
    by_id: Dict[str, Dict] = {}
    for path in sorted(json_paths):           # oldest → newest
        with open(path) as f:
            data = json.load(f)
        for r in data.get("results", []):
            cid = r["config_id"]
            existing = by_id.get(cid)
            if existing is None:
                by_id[cid] = r
            else:
                # Prefer whichever has HW data
                if _get_hw(r) is not None and _get_hw(existing) is None:
                    # Merge: keep new HW into existing ML etc.
                    existing["compile"] = r["compile"]
                # If this run has better compile status (SUCCESS > TIMEOUT), keep it
                new_status  = r.get("compile", {}).get("status", "")
                old_status  = existing.get("compile", {}).get("status", "")
                if new_status == "SUCCESS" and old_status != "SUCCESS":
                    # Only overwrite compile block if we aren't losing HW data
                    if _get_hw(existing) is None:
                        existing["compile"] = r["compile"]
    return list(by_id.values())


def split_experiments(results: List[Dict]):
    feat    = [r for r in results if r["config_id"].startswith("feat_")]
    tree    = [r for r in results if not r["config_id"].startswith("feat_")]
    feat.sort(key=lambda r: r.get("ml", {}).get("num_features", 0))
    return feat, tree


# ---------------------------------------------------------------------------
# Helper: save figure
# ---------------------------------------------------------------------------

def _save(fig: plt.Figure, outdir: Path, name: str, pdf_pages=None):
    outdir.mkdir(parents=True, exist_ok=True)
    fig.savefig(outdir / f"{name}.png", bbox_inches="tight")
    if pdf_pages is not None:
        pdf_pages.savefig(fig, bbox_inches="tight")
    plt.close(fig)
    print(f"  saved {name}.png")


def _pct_val(s: str) -> float:
    try:
        return float(s.rstrip("%"))
    except Exception:
        return 0.0


# ---------------------------------------------------------------------------
# Section 1 – Feature sweep: ML metrics
# ---------------------------------------------------------------------------

def plot_feature_sweep_ml(feat: List[Dict], outdir: Path, pdf=None):
    ks   = [r["ml"]["num_features"] for r in feat]
    acc  = [r["ml"]["accuracy"]        for r in feat]
    f1   = [r["ml"]["f1_macro"]        for r in feat]
    roc  = [r["ml"]["roc_auc"]         for r in feat]
    prec = [r["ml"]["precision_macro"] for r in feat]
    rec  = [r["ml"]["recall_macro"]    for r in feat]

    fig, axes = plt.subplots(1, 3, figsize=(15, 4.5))
    fig.suptitle("Feature Sweep – ML Performance (2 trees, depth 2)", fontsize=13, fontweight="bold")

    # subplot 1: overview metrics
    ax = axes[0]
    ax.plot(ks, acc,  "o-", color=C_BLUE,   label="Accuracy",        lw=2, ms=7)
    ax.plot(ks, f1,   "s-", color=C_GREEN,  label="F1 macro",        lw=2, ms=7)
    ax.plot(ks, roc,  "^-", color=C_ORANGE, label="ROC-AUC",         lw=2, ms=7)
    ax.plot(ks, prec, "D-", color=C_PURPLE, label="Precision macro",  lw=2, ms=6, alpha=0.8)
    ax.plot(ks, rec,  "v-", color=C_RED,    label="Recall macro",     lw=2, ms=6, alpha=0.8)
    ax.set_xlabel("Number of features (k)")
    ax.set_ylabel("Score")
    ax.set_title("Accuracy, F1, ROC-AUC, Prec, Rec")
    ax.set_ylim(min(acc + f1 + roc) - 0.005, 1.005)
    ax.set_xticks(ks)
    ax.legend(loc="lower right", fontsize=8)

    # subplot 2: per-class precision & recall (dynamic class names)
    ax = axes[1]
    class_names = list(feat[0]["ml"]["precision_per_class"].keys())
    per_class_colors = [C_BLUE, C_ORANGE, C_GREEN, C_RED, C_PURPLE]
    all_vals = []
    for ci, cls in enumerate(class_names):
        col = per_class_colors[ci % len(per_class_colors)]
        pvals = [r["ml"]["precision_per_class"][cls] for r in feat]
        rvals = [r["ml"]["recall_per_class"][cls]    for r in feat]
        ax.plot(ks, pvals, "o-",  color=col, label=f"Prec {cls}", lw=2,   ms=7)
        ax.plot(ks, rvals, "s--", color=col, label=f"Rec  {cls}", lw=1.5, ms=6)
        all_vals.extend(pvals + rvals)
    ax.set_xlabel("Number of features (k)")
    ax.set_ylabel("Score")
    ax.set_title("Per-class Precision & Recall")
    ax.set_ylim(min(all_vals) - 0.005, 1.005)
    ax.set_xticks(ks)
    ax.legend(loc="lower right", fontsize=8)

    # subplot 3: train time
    ax = axes[2]
    train_t = [r["ml"]["train_time_s"] for r in feat]
    bars = ax.bar(ks, train_t, color=C_BLUE, alpha=0.8, width=0.6)
    ax.set_xlabel("Number of features (k)")
    ax.set_ylabel("Training time (s)")
    ax.set_title("RF Training Time")
    ax.set_xticks(ks)
    for bar, v in zip(bars, train_t):
        ax.text(bar.get_x() + bar.get_width() / 2, v + 0.3, f"{v:.1f}s",
                ha="center", va="bottom", fontsize=8)

    fig.tight_layout()
    _save(fig, outdir, "01_feature_sweep_ml", pdf)


# ---------------------------------------------------------------------------
# Section 2 – Feature sweep: hardware resources
# ---------------------------------------------------------------------------

def plot_feature_sweep_hw(feat: List[Dict], outdir: Path, pdf=None):
    compiled = [r for r in feat if _get_hw(r) is not None]
    if not compiled:
        print("  [skip] no HW data for feature sweep")
        return

    ks        = [r["ml"]["num_features"] for r in compiled]
    sram      = [_get_hw(r)["total_sram"]           for r in compiled]
    tcam      = [_get_hw(r)["total_tcam"]            for r in compiled]
    vliw      = [_get_hw(r)["total_vliw_instr"]      for r in compiled]
    log_ids   = [_get_hw(r)["total_logical_table_ids"] for r in compiled]
    mram      = [_get_hw(r)["total_map_ram"]         for r in compiled]
    n_active  = [_get_hw(r)["n_active_stages"]       for r in compiled]
    crit      = [r["compile"]["mau"]["critical_path"] for r in compiled]
    ingr      = [r["compile"]["mau"]["n_stages_ingress"] for r in compiled]
    comp_t    = [r["compile"]["compile_time_s"]       for r in compiled]

    fig, axes = plt.subplots(2, 3, figsize=(16, 9))
    fig.suptitle("Feature Sweep – Tofino2 Hardware Resources (2 trees, depth 2)",
                 fontsize=13, fontweight="bold")

    xpos = np.arange(len(ks))
    xlabels = [f"k={k}" for k in ks]

    # --- SRAM & TCAM stacked bar ---
    ax = axes[0, 0]
    b1 = ax.bar(xpos, sram, color=C_BLUE,   label="SRAM", alpha=0.85)
    b2 = ax.bar(xpos, tcam, bottom=sram, color=C_ORANGE, label="TCAM", alpha=0.85)
    b3 = ax.bar(xpos, mram, bottom=[s+t for s,t in zip(sram,tcam)],
                color=C_GREEN, label="Map RAM", alpha=0.7)
    ax.set_xticks(xpos); ax.set_xticklabels(xlabels)
    ax.set_ylabel("Units used")
    ax.set_title("Memory Resources (SRAM / TCAM / Map RAM)")
    ax.legend()
    for i, (s, t, m) in enumerate(zip(sram, tcam, mram)):
        ax.text(i, s + t + m + 2, f"S{s}/T{t}", ha="center", fontsize=8)

    # --- VLIW instructions ---
    ax = axes[0, 1]
    bars = ax.bar(xpos, vliw, color=C_PURPLE, alpha=0.85)
    ax.set_xticks(xpos); ax.set_xticklabels(xlabels)
    ax.set_ylabel("VLIW instructions used")
    ax.set_title("VLIW Instruction Slots")
    for bar, v in zip(bars, vliw):
        ax.text(bar.get_x() + bar.get_width()/2, v + 0.3, str(v),
                ha="center", va="bottom", fontsize=9)

    # --- Logical table IDs ---
    ax = axes[0, 2]
    bars = ax.bar(xpos, log_ids, color=C_YELLOW, edgecolor="grey", alpha=0.9)
    ax.set_xticks(xpos); ax.set_xticklabels(xlabels)
    ax.set_ylabel("Logical table IDs used")
    ax.set_title("Logical Table IDs")
    for bar, v in zip(bars, log_ids):
        ax.text(bar.get_x() + bar.get_width()/2, v + 0.2, str(v),
                ha="center", va="bottom", fontsize=9)

    # --- Active stages & critical path ---
    ax = axes[1, 0]
    ax.plot(ks, n_active, "o-", color=C_BLUE,   label="Active stages", lw=2, ms=8)
    ax.plot(ks, crit,     "s-", color=C_RED,    label="Critical path", lw=2, ms=8)
    ax.plot(ks, ingr,     "^-", color=C_GREEN,  label="Ingress stages",lw=2, ms=8)
    ax.axhline(RESOURCE_CAP_STAGES, color=C_RED, ls="--", lw=1.2, alpha=0.6, label=f"Cap={RESOURCE_CAP_STAGES}")
    ax.axhline(TOFINO2_MAX_STAGES,  color="black", ls=":", lw=1, alpha=0.5, label="Max=20")
    ax.set_xlabel("k features")
    ax.set_ylabel("Stages")
    ax.set_title("Pipeline Stage Usage")
    ax.set_xticks(ks)
    ax.legend(fontsize=8)

    # --- Compile time ---
    ax = axes[1, 1]
    bars = ax.bar(xpos, comp_t, color=C_GREEN, alpha=0.85)
    ax.set_xticks(xpos); ax.set_xticklabels(xlabels)
    ax.set_ylabel("Compile time (s)")
    ax.set_title("P4 Compilation Time")
    for bar, v in zip(bars, comp_t):
        ax.text(bar.get_x() + bar.get_width()/2, v + 1, f"{v:.0f}s",
                ha="center", va="bottom", fontsize=9)

    # --- Resource efficiency: accuracy vs SRAM ---
    ax = axes[1, 2]
    acc = [r["ml"]["accuracy"] for r in compiled]
    sc = ax.scatter(sram, acc, s=[v * 5 for v in vliw],
                    c=ks, cmap="viridis", alpha=0.85, edgecolors="grey", linewidths=0.5)
    cb = fig.colorbar(sc, ax=ax, shrink=0.8)
    cb.set_label("k features")
    for i, (x, y, k) in enumerate(zip(sram, acc, ks)):
        ax.annotate(f"k={k}", (x, y), textcoords="offset points", xytext=(6, 4),
                    fontsize=8)
    ax.set_xlabel("Total SRAM units")
    ax.set_ylabel("Test Accuracy")
    ax.set_title("Accuracy vs SRAM\n(bubble size ∝ VLIW instr)")

    fig.tight_layout()
    _save(fig, outdir, "02_feature_sweep_hw", pdf)


# ---------------------------------------------------------------------------
# Section 3 – Per-stage utilisation heatmaps
# ---------------------------------------------------------------------------

def plot_stage_heatmaps(feat: List[Dict], outdir: Path, pdf=None):
    compiled = [r for r in feat if _get_hw(r) is not None]
    if not compiled:
        return

    resources = ["SRAM", "TCAM", "Map RAM", "VLIW Instr", "Meter ALU", "Logical TableID"]
    n_stages  = TOFINO2_MAX_STAGES
    stages    = list(range(n_stages))

    # One heatmap per compiled config
    ncols = len(compiled)
    fig, axes = plt.subplots(len(resources), ncols,
                             figsize=(5 * ncols, 2.5 * len(resources)),
                             squeeze=False)
    fig.suptitle("Per-Stage Resource Utilisation % (feature sweep, compiled configs)",
                 fontsize=13, fontweight="bold")

    cmap = LinearSegmentedColormap.from_list("green_red",
                                             ["#e8f8e8", "#57A773", "#E07B54", "#D62246"])

    for col_idx, r in enumerate(compiled):
        k    = r["ml"]["num_features"]
        pct  = _get_hw(r).get("stage_utilisation_pct", {})
        for row_idx, res in enumerate(resources):
            ax = axes[row_idx][col_idx]
            vals = []
            for s in range(n_stages):
                v = _pct_val(pct.get(str(s), {}).get(res, "0.00%"))
                vals.append(v)
            data = np.array(vals).reshape(n_stages, 1)
            im = ax.imshow(data, aspect="auto", cmap=cmap, vmin=0, vmax=100,
                           interpolation="nearest")
            ax.set_yticks(range(n_stages))
            ax.set_yticklabels([str(s) for s in stages], fontsize=6)
            ax.set_xticks([])
            if row_idx == 0:
                ax.set_title(f"k={k}", fontsize=10, fontweight="bold")
            if col_idx == 0:
                ax.set_ylabel(res, fontsize=8)
            # Annotate non-zero cells
            for s, v in enumerate(vals):
                if v > 0:
                    ax.text(0, s, f"{v:.0f}", ha="center", va="center",
                            fontsize=6, color="white" if v > 50 else "black")
            # Colorbar only on last column
            if col_idx == len(compiled) - 1:
                plt.colorbar(im, ax=ax, fraction=0.3, pad=0.02).set_label("%", fontsize=7)

    fig.tight_layout()
    _save(fig, outdir, "03_stage_utilisation_heatmap", pdf)


# ---------------------------------------------------------------------------
# Section 4 – Tree/depth sweep: ML heatmaps
# ---------------------------------------------------------------------------

def plot_tree_sweep_ml(tree: List[Dict], outdir: Path, pdf=None):
    if not tree:
        return

    trees_list = sorted(set(r["num_trees"]  for r in tree))
    depth_list = sorted(set(r["max_depth"]  for r in tree))

    def make_grid(metric_fn):
        grid = np.full((len(depth_list), len(trees_list)), np.nan)
        for r in tree:
            ti = trees_list.index(r["num_trees"])
            di = depth_list.index(r["max_depth"])
            try:
                grid[di, ti] = metric_fn(r)
            except Exception:
                pass
        return grid

    metrics = [
        ("Accuracy",        lambda r: r["ml"]["accuracy"]),
        ("F1 macro",        lambda r: r["ml"]["f1_macro"]),
        ("ROC-AUC",         lambda r: r["ml"]["roc_auc"]),
        ("Precision macro", lambda r: r["ml"]["precision_macro"]),
        ("Recall macro",    lambda r: r["ml"]["recall_macro"]),
        ("Train time (s)",  lambda r: r["ml"]["train_time_s"]),
    ]

    fig, axes = plt.subplots(2, 3, figsize=(16, 10))
    fig.suptitle("Tree/Depth Sweep – ML Performance Heatmaps", fontsize=13, fontweight="bold")

    for ax, (title, fn) in zip(axes.flat, metrics):
        grid = make_grid(fn)
        is_time = "time" in title.lower()
        cmap = "YlOrRd" if is_time else "RdYlGn"
        im = ax.imshow(grid, cmap=cmap, aspect="auto",
                       vmin=np.nanmin(grid), vmax=np.nanmax(grid))
        ax.set_xticks(range(len(trees_list)))
        ax.set_xticklabels([f"{t}t" for t in trees_list])
        ax.set_yticks(range(len(depth_list)))
        ax.set_yticklabels([f"d{d}" for d in depth_list])
        ax.set_xlabel("Trees")
        ax.set_ylabel("Depth")
        ax.set_title(title)
        for di in range(len(depth_list)):
            for ti in range(len(trees_list)):
                v = grid[di, ti]
                if not np.isnan(v):
                    fmt = f"{v:.3f}" if not is_time else f"{v:.0f}s"
                    ax.text(ti, di, fmt, ha="center", va="center",
                            fontsize=8, color="black")
        plt.colorbar(im, ax=ax, shrink=0.8)

    fig.tight_layout()
    _save(fig, outdir, "04_tree_sweep_ml_heatmaps", pdf)


# ---------------------------------------------------------------------------
# Section 5 – Tree/depth sweep: compile status grid + compile time
# ---------------------------------------------------------------------------

def plot_tree_sweep_compile(tree: List[Dict], outdir: Path, pdf=None):
    if not tree:
        return

    trees_list = sorted(set(r["num_trees"] for r in tree))
    depth_list = sorted(set(r["max_depth"] for r in tree))

    status_grid = np.full((len(depth_list), len(trees_list)), "N/A", dtype=object)
    time_grid   = np.full((len(depth_list), len(trees_list)), np.nan)
    est_grid    = np.full((len(depth_list), len(trees_list)), np.nan)

    for r in tree:
        ti = trees_list.index(r["num_trees"])
        di = depth_list.index(r["max_depth"])
        status_grid[di, ti] = r.get("compile", {}).get("status", "N/A")
        t = r.get("compile", {}).get("compile_time_s")
        if t:
            time_grid[di, ti] = t
        est = r.get("est_pipeline_stages")
        if est:
            est_grid[di, ti] = est

    fig, axes = plt.subplots(1, 3, figsize=(16, 5))
    fig.suptitle("Tree/Depth Sweep – Compilation Status & Estimated Stages",
                 fontsize=13, fontweight="bold")

    # Status grid (colour patches)
    ax = axes[0]
    ax.set_xlim(-0.5, len(trees_list) - 0.5)
    ax.set_ylim(-0.5, len(depth_list) - 0.5)
    for di in range(len(depth_list)):
        for ti in range(len(trees_list)):
            st = status_grid[di, ti]
            col = COMPILE_COLORS.get(st, "#cccccc")
            rect = mpatches.FancyBboxPatch((ti - 0.4, di - 0.4), 0.8, 0.8,
                                           boxstyle="round,pad=0.05",
                                           facecolor=col, edgecolor="white", lw=1.5)
            ax.add_patch(rect)
            ax.text(ti, di, st, ha="center", va="center", fontsize=8, fontweight="bold",
                    color="white" if st == "SUCCESS" else "black")
    ax.set_xticks(range(len(trees_list)))
    ax.set_xticklabels([f"{t} trees" for t in trees_list])
    ax.set_yticks(range(len(depth_list)))
    ax.set_yticklabels([f"depth {d}" for d in depth_list])
    ax.set_xlabel("Trees"); ax.set_ylabel("Depth")
    ax.set_title("Compilation Status")
    legend_patches = [mpatches.Patch(color=v, label=k) for k, v in COMPILE_COLORS.items()
                      if k in set(status_grid.flatten())]
    ax.legend(handles=legend_patches, loc="upper right", fontsize=8)

    # Compile time heatmap
    ax = axes[1]
    masked = np.ma.masked_invalid(time_grid)
    im = ax.imshow(masked, cmap="YlOrRd", aspect="auto",
                   vmin=0, vmax=np.nanmax(time_grid) if not np.all(np.isnan(time_grid)) else 1)
    ax.set_xticks(range(len(trees_list)))
    ax.set_xticklabels([f"{t}t" for t in trees_list])
    ax.set_yticks(range(len(depth_list)))
    ax.set_yticklabels([f"d{d}" for d in depth_list])
    ax.set_xlabel("Trees"); ax.set_ylabel("Depth")
    ax.set_title("Compile Time (s)\n(blank = timeout / not run)")
    for di in range(len(depth_list)):
        for ti in range(len(trees_list)):
            v = time_grid[di, ti]
            if not np.isnan(v):
                ax.text(ti, di, f"{v:.0f}s", ha="center", va="center", fontsize=8)
    plt.colorbar(im, ax=ax, shrink=0.8).set_label("seconds")

    # Estimated stages heatmap
    ax = axes[2]
    masked2 = np.ma.masked_invalid(est_grid)
    im2 = ax.imshow(masked2, cmap="RdYlGn_r", aspect="auto",
                    vmin=0, vmax=TOFINO2_MAX_STAGES)
    ax.set_xticks(range(len(trees_list)))
    ax.set_xticklabels([f"{t}t" for t in trees_list])
    ax.set_yticks(range(len(depth_list)))
    ax.set_yticklabels([f"d{d}" for d in depth_list])
    ax.set_xlabel("Trees"); ax.set_ylabel("Depth")
    ax.set_title(f"Estimated Pipeline Stages\n(cap = {RESOURCE_CAP_STAGES})")
    ax.axhline(RESOURCE_CAP_STAGES - 0.5, color="red", lw=2, label=f"Cap={RESOURCE_CAP_STAGES}")
    for di in range(len(depth_list)):
        for ti in range(len(trees_list)):
            v = est_grid[di, ti]
            if not np.isnan(v):
                ax.text(ti, di, str(int(v)), ha="center", va="center", fontsize=9)
    plt.colorbar(im2, ax=ax, shrink=0.8).set_label("stages")

    fig.tight_layout()
    _save(fig, outdir, "05_tree_sweep_compile", pdf)


# ---------------------------------------------------------------------------
# Section 6 – Confusion matrices
# ---------------------------------------------------------------------------

def plot_confusion_matrices(feat: List[Dict], outdir: Path, pdf=None):
    ncols = min(len(feat), 4)
    nrows = math.ceil(len(feat) / ncols)
    fig, axes = plt.subplots(nrows, ncols, figsize=(4.5 * ncols, 4 * nrows))
    if len(feat) == 1:
        axes = np.array([[axes]])
    elif nrows == 1:
        axes = axes.reshape(1, -1)
    fig.suptitle("Confusion Matrices – Feature Sweep (2 trees, depth 2)",
                 fontsize=13, fontweight="bold")

    for idx, r in enumerate(feat):
        ax  = axes[idx // ncols][idx % ncols]
        cm  = r["ml"]["confusion_matrix"]
        mat = np.array(cm["matrix"])
        labels = cm["labels"]
        n_total = mat.sum()
        norm    = mat / n_total

        im = ax.imshow(norm, cmap="Blues", vmin=0, vmax=norm.max())
        ax.set_xticks(range(len(labels))); ax.set_xticklabels(labels, rotation=20, fontsize=8)
        ax.set_yticks(range(len(labels))); ax.set_yticklabels(labels, fontsize=8)
        ax.set_xlabel("Predicted"); ax.set_ylabel("True")
        acc = r["ml"]["accuracy"]
        ax.set_title(f"k={r['ml']['num_features']}  acc={acc:.4f}", fontsize=9)

        for i in range(len(labels)):
            for j in range(len(labels)):
                cnt  = mat[i, j]
                frac = norm[i, j]
                col  = "white" if frac > 0.4 else "black"
                ax.text(j, i, f"{cnt:,}\n({frac:.2%})",
                        ha="center", va="center", fontsize=7.5, color=col)
        plt.colorbar(im, ax=ax, shrink=0.7)

    # Hide unused subplots
    for idx in range(len(feat), nrows * ncols):
        axes[idx // ncols][idx % ncols].set_visible(False)

    fig.tight_layout()
    _save(fig, outdir, "06_confusion_matrices", pdf)


# ---------------------------------------------------------------------------
# Section 7 – Feature importances
# ---------------------------------------------------------------------------

def plot_feature_importances(feat: List[Dict], outdir: Path, pdf=None):
    ncols = min(len(feat), 3)
    nrows = math.ceil(len(feat) / ncols)
    fig, axes = plt.subplots(nrows, ncols, figsize=(6 * ncols, 4 * nrows))
    if len(feat) == 1:
        axes = np.array([[axes]])
    elif nrows == 1:
        axes = axes.reshape(1, -1)
    fig.suptitle("Feature Importances (Gini) – Feature Sweep",
                 fontsize=13, fontweight="bold")

    for idx, r in enumerate(feat):
        ax  = axes[idx // ncols][idx % ncols]
        imp = sorted(r["ml"]["feature_importances"], key=lambda x: x["importance"], reverse=True)
        names = [x["feature"] for x in imp]
        vals  = [x["importance"] for x in imp]
        colors = [C_BLUE if v == max(vals) else C_GREY for v in vals]
        bars = ax.barh(range(len(names)), vals, color=colors, alpha=0.85)
        ax.set_yticks(range(len(names)))
        ax.set_yticklabels(names, fontsize=8)
        ax.invert_yaxis()
        ax.set_xlabel("Gini Importance")
        ax.set_title(f"k={r['ml']['num_features']} features", fontsize=9)
        for bar, v in zip(bars, vals):
            ax.text(v + 0.005, bar.get_y() + bar.get_height()/2,
                    f"{v:.3f}", va="center", fontsize=7.5)

    for idx in range(len(feat), nrows * ncols):
        axes[idx // ncols][idx % ncols].set_visible(False)

    fig.tight_layout()
    _save(fig, outdir, "07_feature_importances", pdf)


# ---------------------------------------------------------------------------
# Section 8 – Combined resource scaling overview
# ---------------------------------------------------------------------------

def plot_resource_overview(feat: List[Dict], tree: List[Dict], outdir: Path, pdf=None):
    compiled_feat = [r for r in feat if _get_hw(r) is not None]
    compiled_tree = [r for r in tree if _get_hw(r) is not None]

    all_compiled = compiled_feat + compiled_tree
    if not all_compiled:
        print("  [skip] no compiled configs with HW data for overview")
        return

    labels  = [r["config_id"] for r in all_compiled]
    sram    = [_get_hw(r)["total_sram"]            for r in all_compiled]
    tcam    = [_get_hw(r)["total_tcam"]            for r in all_compiled]
    vliw    = [_get_hw(r)["total_vliw_instr"]      for r in all_compiled]
    mram    = [_get_hw(r)["total_map_ram"]          for r in all_compiled]
    logids  = [_get_hw(r)["total_logical_table_ids"] for r in all_compiled]
    active  = [_get_hw(r)["n_active_stages"]        for r in all_compiled]
    n_active_max = TOFINO2_MAX_STAGES

    fig, axes = plt.subplots(2, 2, figsize=(14, 9))
    fig.suptitle("Compiled Configurations – Resource Overview", fontsize=13, fontweight="bold")

    xpos = np.arange(len(labels))

    # Stacked memory bar
    ax = axes[0, 0]
    ax.bar(xpos, sram, label="SRAM",    color=C_BLUE,   alpha=0.85)
    ax.bar(xpos, mram, bottom=sram, label="Map RAM", color=C_GREEN,  alpha=0.75)
    ax.bar(xpos, tcam, bottom=[s+m for s,m in zip(sram,mram)],
           label="TCAM", color=C_ORANGE, alpha=0.85)
    ax.set_xticks(xpos); ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
    ax.set_ylabel("Units")
    ax.set_title("Memory Usage (SRAM + Map RAM + TCAM)")
    ax.legend()

    # VLIW + logical IDs
    ax = axes[0, 1]
    w = 0.35
    ax.bar(xpos - w/2, vliw,   width=w, label="VLIW instr",      color=C_PURPLE, alpha=0.85)
    ax.bar(xpos + w/2, logids, width=w, label="Logical table IDs",color=C_YELLOW, edgecolor="grey", alpha=0.9)
    ax.set_xticks(xpos); ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
    ax.set_ylabel("Count")
    ax.set_title("VLIW Instructions & Logical Table IDs")
    ax.legend()

    # Active stages
    ax = axes[1, 0]
    crit_vals = []
    for r in all_compiled:
        s = r.get("compile", {}).get("mau", {})
        crit_vals.append(s.get("critical_path", active[all_compiled.index(r)]))
    ax.bar(xpos, active,     label="Active stages",  color=C_BLUE,   alpha=0.85)
    ax.plot(xpos, crit_vals, "ro-", label="Critical path", lw=2, ms=8, alpha=0.9)
    ax.axhline(RESOURCE_CAP_STAGES, color=C_RED, ls="--", lw=1.5, alpha=0.6,
               label=f"Cap={RESOURCE_CAP_STAGES}")
    ax.axhline(n_active_max, color="black", ls=":", lw=1, alpha=0.5, label="Max=20")
    ax.set_xticks(xpos); ax.set_xticklabels(labels, rotation=30, ha="right", fontsize=8)
    ax.set_ylabel("Stages")
    ax.set_title("Active Stages & Critical Path Length")
    ax.set_ylim(0, n_active_max + 2)
    ax.legend(fontsize=8)

    # Accuracy vs resources radar-style scatter
    ax = axes[1, 1]
    acc_vals = [r["ml"]["accuracy"] for r in all_compiled]
    sc = ax.scatter(sram, acc_vals, s=[v*8 for v in active],
                    c=vliw, cmap="plasma", alpha=0.85, edgecolors="grey", linewidths=0.5,
                    zorder=3)
    cb = fig.colorbar(sc, ax=ax, shrink=0.8)
    cb.set_label("VLIW instr")
    for i, r in enumerate(all_compiled):
        ax.annotate(r["config_id"], (sram[i], acc_vals[i]),
                    textcoords="offset points", xytext=(6, 4), fontsize=7)
    ax.set_xlabel("Total SRAM")
    ax.set_ylabel("Test Accuracy")
    ax.set_title("Accuracy vs SRAM\n(bubble = active stages, colour = VLIW)")

    fig.tight_layout()
    _save(fig, outdir, "08_resource_overview", pdf)


# ---------------------------------------------------------------------------
# Section 9 – Full ML comparison table plot
# ---------------------------------------------------------------------------

def plot_summary_table(results: List[Dict], outdir: Path, pdf=None):
    """Render a summary table of all configs as a matplotlib table figure."""
    rows = []
    col_headers = ["Config", "Trees", "Depth", "k feat",
                   "Accuracy", "F1 macro", "ROC-AUC", "Compile",
                   "SRAM", "TCAM", "VLIW", "CritPath"]
    for r in results:
        ml  = r.get("ml", {})
        hw  = _get_hw(r)
        sm  = r.get("compile", {}).get("mau", {})
        rows.append([
            r["config_id"],
            r["num_trees"],
            r["max_depth"],
            ml.get("num_features", "?"),
            f"{ml.get('accuracy', 0):.4f}",
            f"{ml.get('f1_macro',  0):.4f}",
            f"{ml.get('roc_auc',   0):.4f}",
            r.get("compile", {}).get("status", "?"),
            hw["total_sram"]            if hw else "–",
            hw["total_tcam"]            if hw else "–",
            hw["total_vliw_instr"]      if hw else "–",
            sm.get("critical_path", "–") if sm else "–",
        ])

    fig, ax = plt.subplots(figsize=(18, 0.45 * len(rows) + 2))
    ax.axis("off")
    tbl = ax.table(
        cellText=rows,
        colLabels=col_headers,
        cellLoc="center",
        loc="center",
    )
    tbl.auto_set_font_size(False)
    tbl.set_fontsize(8)
    tbl.scale(1, 1.4)

    # Colour header row
    for j in range(len(col_headers)):
        tbl[0, j].set_facecolor("#2E86AB")
        tbl[0, j].set_text_props(color="white", fontweight="bold")

    # Colour compile status cells
    status_col = col_headers.index("Compile")
    for i, row in enumerate(rows, start=1):
        st = row[status_col]
        tbl[i, status_col].set_facecolor(COMPILE_COLORS.get(st, "#eeeeee"))
        if st == "SUCCESS":
            tbl[i, status_col].set_text_props(color="white", fontweight="bold")

    fig.suptitle("Full Benchmark Summary – All Configurations", fontsize=13, fontweight="bold", y=0.98)
    fig.tight_layout()
    _save(fig, outdir, "00_summary_table", pdf)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Plot pForest benchmark results")
    parser.add_argument("--report", nargs="+", type=Path,
                        help="JSON report file(s). Default: all in benchmark_reports/")
    parser.add_argument("--outdir", type=Path, default=ROOT / "plots",
                        help="Output directory for PNG/PDF (default: plots/)")
    parser.add_argument("--no-pdf", action="store_true", help="Skip merged PDF output")
    args = parser.parse_args()

    if args.report:
        json_paths = args.report
    else:
        json_paths = sorted(REPORTS_DIR.glob("benchmark_all_experiments_*.json"))
        if not json_paths:
            json_paths = sorted(REPORTS_DIR.glob("*.json"))
    if not json_paths:
        print("ERROR: no report files found. Pass --report path/to/report.json")
        sys.exit(1)

    print(f"Loading {len(json_paths)} report file(s)…")
    results = load_and_merge(json_paths)
    print(f"  → {len(results)} unique configs loaded")

    feat, tree = split_experiments(results)
    print(f"  → feature sweep: {len(feat)} configs,  tree/depth sweep: {len(tree)} configs")

    outdir = args.outdir
    outdir.mkdir(parents=True, exist_ok=True)

    pdf_path = outdir / "pforest_benchmark_report.pdf"
    if args.no_pdf:
        pdf_pages = None
    else:
        from matplotlib.backends.backend_pdf import PdfPages
        pdf_pages = PdfPages(pdf_path)

    print("\nGenerating plots…")
    plot_summary_table(results,                    outdir, pdf_pages)
    plot_feature_sweep_ml(feat,                    outdir, pdf_pages)
    plot_feature_sweep_hw(feat,                    outdir, pdf_pages)
    plot_stage_heatmaps(feat,                      outdir, pdf_pages)
    plot_tree_sweep_ml(tree,                       outdir, pdf_pages)
    plot_tree_sweep_compile(tree,                  outdir, pdf_pages)
    plot_confusion_matrices(feat,                  outdir, pdf_pages)
    plot_feature_importances(feat,                 outdir, pdf_pages)
    plot_resource_overview(feat, tree,             outdir, pdf_pages)

    if pdf_pages is not None:
        pdf_pages.close()
        print(f"\nMerged PDF → {pdf_path}")

    print(f"All plots saved to {outdir}/")


if __name__ == "__main__":
    main()
