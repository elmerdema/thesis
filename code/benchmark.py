"""
pForest Resource & Accuracy Benchmark
======================================
Runs two systematic experiments to characterise model quality vs. Tofino2 resource usage.

Experiment 1  --  Feature-count sweep
  Fixed topology: 2 trees, depth 2.
  Vary the number of Marina telemetry features from 3 to 8.
  Features are chosen greedily by importance (top-k of a probe RF).

Experiment 2  --  Tree / depth configuration sweep
  At least 3 trees (so majority voting is meaningful).
  Sweeps (num_trees, max_depth) pairs whose estimated pipeline-stage cost is
  <= RESOURCE_CAP_STAGES.  Caps prevent wasting compile slots on obviously
  infeasible designs.

For every configuration the benchmark:
  1. Trains a Random Forest and records full ML diagnostics.
  2. Validates accuracy >= 70 % (retries up to MAX_TRAIN_ATTEMPTS times).
  3. Generates pforest.p4 via the TNA Jinja2 generator.
  4. Writes a minimal compile.sh and runs the Intel SDE p4_build script.
  5. Parses the compiler's MAU resource log for actual hardware stage usage.
  6. Emits a structured JSON report and human-readable summary tables.

Usage
-----
  # Feature sweep (Experiment 1)
  python3 src/benchmark.py --experiment features --arch t2na

  # Tree/depth sweep (Experiment 2)
  python3 src/benchmark.py --experiment trees --arch t2na

  # Both in sequence
  python3 src/benchmark.py --experiment all --arch t2na

  # Skip compilation (ML-only, faster)
  python3 src/benchmark.py --experiment all --no-compile

  # Increase compile timeout (seconds, default 600)
  python3 src/benchmark.py --experiment trees --compile-timeout 900
"""

import argparse
import datetime
import json
import math
import os
import re
import shutil
import subprocess
import sys
import textwrap
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

ROOT_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT_DIR))

from src.p4_generator_tna import generate_pforest_tna, MARINA_TELEMETRY_FEATURES
from src.randomforest.rf_model import build_and_train_random_forest, DATASETS, DEFAULT_DATASET
from src.randomforest.randomForestEncode import rf_encoding

# ---------------------------------------------------------------------------
# Constants / tuneable knobs
# ---------------------------------------------------------------------------

# Experiment 1 parameters
FEATURE_SWEEP_TREES  = 2
FEATURE_SWEEP_DEPTH  = 2
FEATURE_SWEEP_KLIST  = list(range(3, 9))          # k = 3 … 8

# Experiment 2 parameters
TREE_SWEEP_MIN_TREES  = 3
TREE_SWEEP_MAX_TREES  = 7
TREE_SWEEP_MIN_DEPTH  = 1
TREE_SWEEP_MAX_DEPTH  = 5
# Estimated pipeline stages = num_trees * (max_depth + 1).
# Tofino2 has 20 MAU stages; leave ≥4 for forwarding / Marina tables.
RESOURCE_CAP_STAGES   = 16

# Translator mode: compiler packs ingress-only ternary tables much more
# efficiently (benchmarks show ~8 actual stages regardless of config).
# Allow larger sweep ranges and a higher stage cap.
TRANSLATOR_TREE_SWEEP_MAX_TREES = 11
TRANSLATOR_TREE_SWEEP_MAX_DEPTH = 7
TRANSLATOR_RESOURCE_CAP_STAGES  = 20   # full 20 stages available

CERTAINTY_DEFAULT     = 75          # percent
MAX_TRAIN_ATTEMPTS    = 5           # retries per configuration
ACCURACY_THRESHOLD    = 0.70        # minimum acceptable test accuracy

COMPILE_TIMEOUT       = 1200        # seconds (default)

# Default architecture
DEFAULT_ARCH          = "t2na"

REPORT_DIR            = ROOT_DIR / "benchmark_reports"


# ---------------------------------------------------------------------------
# Low-level helpers
# ---------------------------------------------------------------------------

def _ts() -> str:
    """Return current timestamp string suitable for file names."""
    return datetime.datetime.now().strftime("%Y%m%d_%H%M%S")


def _fmt_pct(v: Optional[float]) -> str:
    return f"{v * 100:.2f}%" if v is not None else "N/A"


def _fmt_f(v: Optional[float], digits: int = 4) -> str:
    return f"{v:.{digits}f}" if v is not None else "N/A"


# ---------------------------------------------------------------------------
# Probe: get stable feature-importance ranking for the feature sweep
# ---------------------------------------------------------------------------

def get_feature_ranking(trees: int = 8, depth: int = 3, dataset: Optional[str] = None, no_grid_search: bool = False) -> List[str]:
    """
    Train a single probe RF with all 8 Marina telemetry features to get a
    stable importance ranking.  Returns feature names sorted best-first.
    """
    print("\n[Probe] Computing feature importance ranking …")
    rf = build_and_train_random_forest(
        num_trees=trees,
        max_depth=depth,
        debug=False,
        feature_names=list(MARINA_TELEMETRY_FEATURES),
        dataset=dataset,
        no_grid_search=no_grid_search,
    )
    ranked = [f for f, _ in rf.feature_importances_ranked]
    print(f"[Probe] Ranking: {ranked}")
    return ranked


# ---------------------------------------------------------------------------
# ML training with retry
# ---------------------------------------------------------------------------

def train_with_retry(
    num_trees: int,
    max_depth: int,
    feature_names: Optional[List[str]] = None,
    min_features: int = 3,
    max_features: Optional[int] = None,
    max_attempts: int = MAX_TRAIN_ATTEMPTS,
    label: str = "model",
    dataset: Optional[str] = None,
    no_grid_search: bool = False,
) -> Optional[Any]:
    """
    Train until accuracy >= ACCURACY_THRESHOLD or attempts are exhausted.
    Returns the sklearn RF object (with extra attributes attached) or None.
    """
    for attempt in range(1, max_attempts + 1):
        try:
            rf = build_and_train_random_forest(
                num_trees=num_trees,
                max_depth=max_depth,
                debug=False,
                feature_names=feature_names,
                min_features=min_features,
                max_features=max_features,
                dataset=dataset,
                no_grid_search=no_grid_search,
            )
            acc = float(getattr(rf, "test_accuracy", 0.0))
            if acc >= ACCURACY_THRESHOLD:
                print(
                    f"  [{label}] attempt {attempt}/{max_attempts}  "
                    f"acc={acc:.4f}  f1={rf.test_f1_macro:.4f}  ✓"
                )
                return rf
            else:
                print(
                    f"  [{label}] attempt {attempt}/{max_attempts}  "
                    f"acc={acc:.4f} < threshold {ACCURACY_THRESHOLD:.2f}  retrying …"
                )
        except Exception as exc:
            print(f"  [{label}] attempt {attempt}/{max_attempts}  ERROR: {exc}")

    print(f"  [{label}] FAILED after {max_attempts} attempts")
    return None


# ---------------------------------------------------------------------------
# Compile.sh generation (standalone, no dependency on generate_pforest.py)
# ---------------------------------------------------------------------------

def write_compile_sh(p4src_dir: Path, arch: str) -> None:
    """Write a minimal compile.sh into p4src_dir for the given arch."""
    target   = "tofino" if arch == "tna" else "tofino2"
    # Uses pforest_compile.sh wrapper (NOPASSWD in sudoers) so the
    # benchmark can run unattended overnight without password prompts.
    compile_script = textwrap.dedent(f"""\
        #!/bin/bash
        set -e
        echo "Compiling pForest for {target} …"
        sudo /usr/local/sde/bin/pforest_compile.sh "$(pwd)"
        echo "Compilation succeeded"
    """)
    sh_path = p4src_dir / "compile.sh"
    sh_path.write_text(compile_script)
    sh_path.chmod(0o755)


# ---------------------------------------------------------------------------
# MAU resource log parser
# ---------------------------------------------------------------------------

def _sde_artifact_dir(arch: str) -> Path:
    """Path to the SDE-installed pforest artifact directory (always authoritative)."""
    target = "tofino" if arch == "tna" else "tofino2"
    sde    = os.environ.get("SDE_INSTALL", "/usr/local/sde")
    return Path(sde) / f"pforest.{target}"


def _find_log(arch: str, filename: str) -> Optional[Path]:
    """Locate a compiler log file; checks SDE_INSTALL, /usr/local/sde, and local p4src copy."""
    target = "tofino" if arch == "tna" else "tofino2"
    sde    = os.environ.get("SDE_INSTALL", "")
    candidates = []
    # SDE_INSTALL env var (if set)
    if sde:
        candidates.append(Path(sde) / f"pforest.{target}" / "pipe" / "logs" / filename)
    # Hard-coded canonical SDE install location (p4_build always writes here)
    candidates.append(Path("/usr/local/sde") / f"pforest.{target}" / "pipe" / "logs" / filename)
    # Local p4src copy (created by compile.sh)
    candidates.append(ROOT_DIR / "p4src" / f"pforest.{target}" / "pipe" / "logs" / filename)
    for p in candidates:
        if p.exists():
            return p
    return None


def _parse_pipe_table(lines: List[str], start_idx: int) -> Tuple[List[str], List[List[str]], int]:
    """
    Parse a pipe-delimited table starting at start_idx.
    Returns (headers, rows, end_idx).
    A row that contains only dashes in every cell ends the table.
    """
    headers: List[str] = []
    rows: List[List[str]] = []
    i = start_idx
    header_done = False

    while i < len(lines):
        line = lines[i].strip()
        # Skip separator lines (all dashes / equals between pipes)
        if re.match(r"^[-=|+ ]+$", line):
            i += 1
            continue
        if "|" not in line:
            break
        cells = [c.strip() for c in line.split("|") if c.strip() != ""]
        if not cells:
            i += 1
            continue
        if not header_done:
            headers = cells
            header_done = True
        else:
            rows.append(cells)
        i += 1

    return headers, rows, i


def _join_wrapped_pipe_lines(lines: List[str]) -> List[str]:
    """
    The SDE mau.resources.log wraps wide pipe-table rows across two physical lines.
    First line of a row starts with '|'.  Continuation lines do NOT start with '|'
    but still contain '|'.  Join them so each logical row is a single string.
    """
    joined: List[str] = []
    for line in lines:
        stripped = line.rstrip()
        if stripped.startswith("|"):
            joined.append(stripped)
        elif "|" in stripped and joined and joined[-1].strip().startswith("|"):
            # continuation: append to previous row
            joined[-1] = joined[-1].rstrip() + " " + stripped.strip()
        else:
            joined.append(stripped)
    return joined


def _parse_mau_resources_log(log_path: Path) -> Dict[str, Any]:
    """
    Parse mau.resources.log which contains two pipe tables:
      1. Raw resource counts  per stage (+ Totals row)
      2. Percentage utilisation per stage (+ Average row)
    Then a free-text 'Allocated Resource Usage' section with per-table data.
    """
    content = log_path.read_text(errors="replace")
    # The SDE log wraps wide table rows onto two physical lines; join them first
    lines   = _join_wrapped_pipe_lines(content.splitlines())

    result: Dict[str, Any] = {
        "log_path":               str(log_path),
        # Summary totals (from Totals row of table 1)
        "total_sram":             None,
        "total_tcam":             None,
        "total_map_ram":          None,
        "total_meter_alu":        None,
        "total_stats_alu":        None,
        "total_vliw_instr":       None,
        "total_hash_bits":        None,
        "total_logical_table_ids":None,
        # Stages that have non-zero content (SRAM+TCAM+RAMs > 0)
        "active_stages":          [],
        "n_active_stages":        None,
        # All 20 stages are present in the log; we record the max stage index used
        "max_stage_index":        None,
        # Per-stage % utilisation (dict stage_str -> dict resource -> pct_str)
        "stage_utilisation_pct":  {},
        # Average row from table 2
        "avg_utilisation_pct":    {},
        # Per-table allocation
        "table_allocations":      [],
    }

    # ── Table 1: raw counts ────────────────────────────────────────────────
    # Find the first header row that has "Stage Number"
    table1_start = None
    for idx, line in enumerate(lines):
        if "Stage Number" in line and "Exact Match" in line:
            table1_start = idx
            break

    if table1_start is not None:
        # Collect all rows until blank line or non-pipe line after rows have started
        raw_rows: List[List[str]] = []
        headers1: List[str] = []
        i = table1_start
        header_parsed = False
        found_totals  = False
        while i < len(lines):
            line = lines[i]
            stripped = line.strip()
            if re.match(r"^[-=|+ ]+$", stripped) or stripped == "":
                i += 1
                # Separator after the Totals row marks end of table 1 — stop here
                if found_totals:
                    break
                continue
            if "|" not in line:
                break
            cells = [c.strip() for c in line.split("|") if c.strip() != ""]
            if not cells:
                i += 1
                continue
            if not header_parsed:
                headers1 = cells
                header_parsed = True
                i += 1
                continue
            raw_rows.append(cells)
            # After appending the Totals row, flag so we stop at the next separator
            if cells and cells[0].strip().lower() in ("totals", "total"):
                found_totals = True
            i += 1

        # Map column names → indices
        col = {h: idx for idx, h in enumerate(headers1)}
        stage_col  = col.get("Stage Number", 0)
        sram_col   = col.get("SRAM")
        tcam_col   = col.get("TCAM")
        mram_col   = col.get("Map RAM")
        vliw_col   = col.get("VLIW Instr")
        hbit_col   = col.get("Hash Bit")
        malu_col   = col.get("Meter ALU")
        salu_col   = col.get("Stats ALU")
        ltid_col   = col.get("Logical TableID")

        def _safe_int(row: List[str], cidx: Optional[int]) -> int:
            if cidx is None or cidx >= len(row):
                return 0
            try:
                return int(row[cidx])
            except ValueError:
                return 0

        per_stage_raw: Dict[str, Dict[str, int]] = {}
        totals_row: Optional[List[str]] = None

        for row in raw_rows:
            if not row:
                continue
            stage_val = row[stage_col] if stage_col < len(row) else ""
            if stage_val.lower() in ("totals", "total", "average", "avg", ""):
                if stage_val.lower() in ("totals", "total"):
                    totals_row = row
                continue
            # Skip separator / non-numeric stage values
            try:
                stage_int = int(stage_val)
            except ValueError:
                continue

            per_stage_raw[str(stage_int)] = {
                "sram":   _safe_int(row, sram_col),
                "tcam":   _safe_int(row, tcam_col),
                "map_ram": _safe_int(row, mram_col),
                "vliw":   _safe_int(row, vliw_col),
                "hash_bits": _safe_int(row, hbit_col),
                "meter_alu": _safe_int(row, malu_col),
                "stats_alu": _safe_int(row, salu_col),
                "logical_ids": _safe_int(row, ltid_col),
            }

        # Active stages = stages with SRAM or TCAM > 0
        active = [
            int(s) for s, v in per_stage_raw.items()
            if v["sram"] > 0 or v["tcam"] > 0 or v["vliw"] > 1
        ]
        result["active_stages"]    = sorted(active)
        result["n_active_stages"]  = len(active)
        result["max_stage_index"]  = max(int(s) for s in per_stage_raw) if per_stage_raw else None
        result["per_stage_raw"]    = per_stage_raw

        if totals_row:
            result["total_sram"]            = _safe_int(totals_row, sram_col)
            result["total_tcam"]            = _safe_int(totals_row, tcam_col)
            result["total_map_ram"]         = _safe_int(totals_row, mram_col)
            result["total_vliw_instr"]      = _safe_int(totals_row, vliw_col)
            result["total_hash_bits"]       = _safe_int(totals_row, hbit_col)
            result["total_meter_alu"]       = _safe_int(totals_row, malu_col)
            result["total_stats_alu"]       = _safe_int(totals_row, salu_col)
            result["total_logical_table_ids"] = _safe_int(totals_row, ltid_col)

    # ── Table 2: % utilisation ─────────────────────────────────────────────
    # Find the second occurrence of "Stage Number" header
    table2_starts = [idx for idx, l in enumerate(lines)
                     if "Stage Number" in l and "Exact Match" in l]
    if len(table2_starts) >= 2:
        i = table2_starts[1]
        headers2: List[str] = []
        h2_done = False
        while i < len(lines):
            line = lines[i]
            stripped = line.strip()
            if re.match(r"^[-=|+ ]+$", stripped) or stripped == "":
                i += 1
                continue
            if "|" not in line:
                break
            cells = [c.strip() for c in line.split("|") if c.strip() != ""]
            if not cells:
                i += 1
                continue
            if not h2_done:
                headers2 = cells
                h2_done = True
                i += 1
                continue

            stage_val = cells[0] if cells else ""
            if stage_val.lower() in ("average", "avg"):
                # Build avg dict
                result["avg_utilisation_pct"] = {
                    headers2[j]: cells[j]
                    for j in range(1, min(len(headers2), len(cells)))
                }
                i += 1
                break
            try:
                stage_int = int(stage_val)
            except ValueError:
                i += 1
                continue

            result["stage_utilisation_pct"][str(stage_int)] = {
                headers2[j]: cells[j]
                for j in range(1, min(len(headers2), len(cells)))
            }
            i += 1

    # ── Allocated Resource Usage: per-table ───────────────────────────────
    alloc_start = None
    for idx, line in enumerate(lines):
        if "Allocated Resource Usage" in line:
            alloc_start = idx
            break

    if alloc_start is not None:
        tbl_headers: List[str] = []
        tbl_header_done = False
        # Column indices we care about
        name_col = stage_col2 = sram2 = tcam2 = xbar2 = vliw2 = None

        for line in lines[alloc_start:]:
            stripped = line.strip()
            if re.match(r"^[-=|+ ]+$", stripped) or stripped == "":
                continue
            if "|" not in line:
                if tbl_header_done and result["table_allocations"]:
                    break
                continue
            cells = [c.strip() for c in line.split("|") if c.strip() != ""]
            if not cells:
                continue
            if not tbl_header_done:
                tbl_headers += cells  # headers span multiple pipe lines
                # Check if all key columns are present
                flat = " ".join(tbl_headers)
                if "Table" in flat and "Stage" in flat and "RAMs" in flat:
                    tbl_header_done = True
                    # Find column indices by scanning tbl_headers
                    def _hcol(keyword: str) -> Optional[int]:
                        for ci, h in enumerate(tbl_headers):
                            if keyword.lower() in h.lower():
                                return ci
                        return None
                    name_col   = _hcol("Table")
                    stage_col2 = _hcol("Stage")
                    sram2      = _hcol("RAMs")
                    tcam2      = _hcol("TCAMs")
                    xbar2      = _hcol("Crossbar")
                    vliw2      = _hcol("VLIW")
                continue

            if len(cells) < 3:
                continue
            try:
                name  = cells[name_col]  if name_col  is not None and name_col  < len(cells) else ""
                stg   = cells[stage_col2] if stage_col2 is not None and stage_col2 < len(cells) else ""
                rams  = int(cells[sram2])  if sram2 is not None and sram2 < len(cells) else 0
                tcams = int(cells[tcam2])  if tcam2 is not None and tcam2 < len(cells) else 0
                xbar  = int(cells[xbar2])  if xbar2 is not None and xbar2 < len(cells) else 0
                vliw  = int(cells[vliw2])  if vliw2 is not None and vliw2 < len(cells) else 0
                stage_i = int(stg)
                result["table_allocations"].append({
                    "table": name, "stage": stage_i,
                    "sram": rams, "tcam": tcams,
                    "crossbar_bytes": xbar, "vliw_slots": vliw,
                })
            except (ValueError, TypeError, IndexError):
                continue

    return result


def _parse_table_summary_log(log_path: Path) -> Dict[str, Any]:
    """
    Parse table_summary.log for:
      - n_stages_total, n_stages_ingress, n_stages_egress
      - critical_path_length
      - n_tables
      - per-stage table names (final allocation pass)
    """
    content = log_path.read_text(errors="replace")
    lines   = content.splitlines()

    result: Dict[str, Any] = {
        "log_path":          str(log_path),
        "n_stages_total":    None,
        "n_stages_ingress":  None,
        "n_stages_egress":   None,
        "critical_path":     None,
        "n_tables":          None,
        "stage_table_map":   {},   # stage_str -> [table_names]
    }

    # We want the LAST table-allocation pass (it's the final/best)
    # Each pass starts with "Number of stages in table allocation:"
    pass_starts: List[int] = []
    for idx, line in enumerate(lines):
        if "Number of stages in table allocation:" in line:
            pass_starts.append(idx)

    if not pass_starts:
        return result

    # Use the last pass
    start = pass_starts[-1]
    for line in lines[start:start + 6]:
        m = re.search(r"Number of stages in table allocation:\s*(\d+)", line)
        if m:
            result["n_stages_total"] = int(m.group(1))
        m = re.search(r"Number of stages for ingress table allocation:\s*(\d+)", line)
        if m:
            result["n_stages_ingress"] = int(m.group(1))
        m = re.search(r"Number of stages for egress table allocation:\s*(\d+)", line)
        if m:
            result["n_stages_egress"] = int(m.group(1))
        m = re.search(r"Critical path length.*?:\s*(\d+)", line)
        if m:
            result["critical_path"] = int(m.group(1))
        m = re.search(r"Number of tables allocated:\s*(\d+)", line)
        if m:
            result["n_tables"] = int(m.group(1))

    # Also scan a bit further for the table placement table
    for line in lines[start: start + 12]:
        m = re.search(r"Critical path length.*?:\s*(\d+)", line)
        if m:
            result["critical_path"] = int(m.group(1))
        m = re.search(r"Number of tables allocated:\s*(\d+)", line)
        if m:
            result["n_tables"] = int(m.group(1))

    # Parse stage→table mapping from the +------ table block after pass_starts[-1]
    in_table  = False
    stage_map: Dict[str, List[str]] = {}
    for line in lines[start:]:
        if "+-------+" in line or "+---" in line:
            in_table = not in_table
            continue
        if in_table and line.strip().startswith("|"):
            parts = [p.strip() for p in line.split("|") if p.strip()]
            if len(parts) >= 3:
                try:
                    stage_num = int(parts[0])
                    tbl_name  = parts[2]
                    stage_map.setdefault(str(stage_num), []).append(tbl_name)
                except (ValueError, IndexError):
                    pass

    result["stage_table_map"] = stage_map
    return result


def parse_compiler_resources(arch: str) -> Dict[str, Any]:
    """
    High-level entry: parse both mau.resources.log and table_summary.log
    from the SDE artifact directory, then assemble a clean resource report.
    """
    out: Dict[str, Any] = {
        "mau_log_found":    False,
        "summary_log_found": False,
    }

    mau_log_path     = _find_log(arch, "mau.resources.log")
    summary_log_path = _find_log(arch, "table_summary.log")

    if mau_log_path:
        out["mau_log_found"] = True
        mau = _parse_mau_resources_log(mau_log_path)
        out["mau"] = mau
        # Flatten key numbers to top-level for easy table display
        out["n_active_stages"]         = mau.get("n_active_stages")
        out["max_stage_index"]         = mau.get("max_stage_index")
        out["total_sram"]              = mau.get("total_sram")
        out["total_tcam"]              = mau.get("total_tcam")
        out["total_map_ram"]           = mau.get("total_map_ram")
        out["total_meter_alu"]         = mau.get("total_meter_alu")
        out["total_vliw_instr"]        = mau.get("total_vliw_instr")
        out["total_logical_table_ids"] = mau.get("total_logical_table_ids")
        out["active_stages"]           = mau.get("active_stages", [])
        out["n_table_allocs"]          = len(mau.get("table_allocations", []))
    else:
        out["note_mau"] = f"mau.resources.log not found for arch={arch}"

    if summary_log_path:
        out["summary_log_found"] = True
        summ = _parse_table_summary_log(summary_log_path)
        out["summary"] = summ
        out["n_stages_total"]    = summ.get("n_stages_total")
        out["n_stages_ingress"]  = summ.get("n_stages_ingress")
        out["n_stages_egress"]   = summ.get("n_stages_egress")
        out["critical_path"]     = summ.get("critical_path")
        out["n_tables_placed"]   = summ.get("n_tables")
    else:
        out["note_summary"] = f"table_summary.log not found for arch={arch}"

    return out


# ---------------------------------------------------------------------------
# P4 generation helpers
# ---------------------------------------------------------------------------

def _ensure_p4src_dirs() -> None:
    (ROOT_DIR / "p4src" / "include").mkdir(parents=True, exist_ok=True)


def generate_p4(
    num_trees: int,
    max_depth: int,
    certainty: int,
    arch: str,
    features: List[str],
    mode: str = "reporter",
) -> bool:
    """Generate pforest.p4.  Returns True on success."""
    try:
        _ensure_p4src_dirs()
        generate_pforest_tna(
            num_trees=num_trees,
            max_depth=max_depth,
            certainty=certainty * 10,
            output_file=str(ROOT_DIR / "p4src" / "pforest.p4"),
            enable_drift=(num_trees >= 2),
            arch=arch,
            features=features,
            mode=mode,
        )
        return True
    except Exception as exc:
        print(f"  [P4 gen] ERROR: {exc}")
        return False


# ---------------------------------------------------------------------------
# Compilation runner
# ---------------------------------------------------------------------------

def compile_p4(
    arch: str,
    config_label: str,
    timeout: int = COMPILE_TIMEOUT,
) -> Dict[str, Any]:
    """
    Write compile.sh, execute it, and return a compilation-result dict:
      status        : "SUCCESS" | "FAILED" | "TIMEOUT" | "ERROR"
      compile_time_s: wall-clock seconds
      stdout_tail   : last 40 lines of combined output
      mau           : dict from parse_mau_resources()
    """
    p4src_dir = ROOT_DIR / "p4src"
    write_compile_sh(p4src_dir, arch)

    start   = time.time()
    status  = "FAILED"
    output  = ""
    mau     = {}

    try:
        proc = subprocess.run(
            ["./compile.sh"],
            cwd=str(p4src_dir),
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        output = proc.stdout + "\n" + proc.stderr
        elapsed = time.time() - start

        if "Compilation succeeded" in output or proc.returncode == 0:
            status = "SUCCESS"
            mau    = parse_compiler_resources(arch)
        else:
            status = "FAILED"
            # Persist error log for post-mortem
            err_log = p4src_dir / f"compile_error_{config_label}.txt"
            err_log.write_text(output)
            print(f"  [Compile] FAILED – log saved to {err_log.relative_to(ROOT_DIR)}")

    except subprocess.TimeoutExpired:
        status  = "TIMEOUT"
        elapsed = timeout
        print(f"  [Compile] TIMEOUT after {timeout}s")
    except Exception as exc:
        status  = "ERROR"
        elapsed = time.time() - start
        print(f"  [Compile] ERROR: {exc}")
        output  = str(exc)

    lines      = [l for l in output.splitlines() if l.strip()]
    stdout_tail = lines[-40:] if len(lines) > 40 else lines

    return {
        "status":         status,
        "compile_time_s": round(elapsed, 1),
        "stdout_tail":    stdout_tail,
        "mau":            mau,
    }


# ---------------------------------------------------------------------------
# Core benchmark function for a single configuration
# ---------------------------------------------------------------------------

def benchmark_single_config(
    num_trees: int,
    max_depth: int,
    forced_features: Optional[List[str]],
    arch: str,
    certainty: int = CERTAINTY_DEFAULT,
    compile_enabled: bool = True,
    compile_timeout: int = COMPILE_TIMEOUT,
    min_features: int = 3,
    max_features: Optional[int] = None,
    label: str = "",
    dataset: Optional[str] = None,
    no_grid_search: bool = False,
    mode: str = "reporter",
) -> Dict[str, Any]:
    """
    Run one complete benchmark cycle and return a result dict.

    Parameters
    ----------
    num_trees        : Trees per forest
    max_depth        : Max tree depth
    forced_features  : Explicit feature list; None → auto-select
    arch             : "tna" or "t2na"
    certainty        : Certainty threshold (0-100)
    compile_enabled  : Whether to actually run p4_build
    compile_timeout  : Seconds before giving up on compile
    min_features     : Passed to rf_model when forced_features is None
    max_features     : Passed to rf_model when forced_features is None
    label            : Human-readable name for logging
    """
    est_stages = num_trees * (max_depth + 1)
    if mode == "translator":
        # Translator: ingress-only pipeline + forward + majority_vote tables
        est_stages += 2
    cfg_id     = label or f"{num_trees}t_d{max_depth}"
    if forced_features:
        cfg_id += f"_k{len(forced_features)}"

    print(f"\n{'─'*68}")
    print(f"  CONFIG: {cfg_id}   trees={num_trees}  depth={max_depth}  "
          f"arch={arch.upper()}")
    if forced_features:
        print(f"  features={forced_features}")
    print(f"  est_stages={est_stages}  certainty={certainty}%")
    print(f"{'─'*68}")

    result: Dict[str, Any] = {
        "config_id":           cfg_id,
        "num_trees":           num_trees,
        "max_depth":           max_depth,
        "certainty":           certainty,
        "arch":                arch,
        "mode":                mode,
        "dataset":             dataset or DEFAULT_DATASET,
        "forced_features":     forced_features,
        "est_pipeline_stages": est_stages,
        "timestamp":           datetime.datetime.now().isoformat(),
        # ML section (populated after training)
        "ml": {},
        # Compile section (populated after compilation)
        "compile": {"status": "SKIPPED"},
    }

    # ── 1. Train ──────────────────────────────────────────────────────────
    t_train_start = time.time()
    print(f"  [Train] Starting …")
    rf = train_with_retry(
        num_trees=num_trees,
        max_depth=max_depth,
        feature_names=forced_features,
        min_features=min_features,
        max_features=max_features,
        label=cfg_id,
        dataset=dataset,
        no_grid_search=no_grid_search,
    )
    t_train_s = round(time.time() - t_train_start, 1)

    if rf is None:
        result["ml"] = {"status": "TRAINING_FAILED", "train_time_s": t_train_s}
        result["compile"] = {"status": "SKIPPED_TRAIN_FAILED"}
        return result

    actual_features = list(rf.selected_feature_names)
    print(f"  [Train] Done in {t_train_s}s  |  features: {actual_features}")

    # ── 2. Record ML diagnostics ──────────────────────────────────────────
    cm      = rf.test_confusion_matrix   # [[TN,FP],[FN,TP]]
    classes = getattr(rf, "class_names", ["class_0", "class_1"])

    result["ml"] = {
        "status":                   "OK",
        "train_time_s":             t_train_s,
        "random_seed":              int(rf.random_seed),
        "num_features":             len(actual_features),
        "features":                 actual_features,
        "accuracy":                 round(float(rf.test_accuracy), 6),
        "f1_macro":                 round(float(rf.test_f1_macro), 6),
        "precision_macro":          round(float(rf.test_precision_macro), 6),
        "recall_macro":             round(float(rf.test_recall_macro), 6),
        "roc_auc":                  (round(float(rf.test_roc_auc), 6)
                                     if rf.test_roc_auc is not None else None),
        "f1_per_class":             {c: round(v, 6)
                                     for c, v in zip(classes, rf.test_f1_per_class)},
        "precision_per_class":      {c: round(v, 6)
                                     for c, v in zip(classes, rf.test_precision_per_class)},
        "recall_per_class":         {c: round(v, 6)
                                     for c, v in zip(classes, rf.test_recall_per_class)},
        "confusion_matrix":         {
            "labels":               classes,
            "matrix":               cm,
            "TN": cm[0][0], "FP": cm[0][1],
            "FN": cm[1][0], "TP": cm[1][1],
        },
        "feature_importances":      [{"feature": f, "importance": round(v, 6)}
                                     for f, v in rf.feature_importances_ranked],
        "best_hyperparams":         rf.best_params_,
        "dataset_info":             rf.dataset_info,
    }

    acc = result["ml"]["accuracy"]
    f1  = result["ml"]["f1_macro"]
    auc = result["ml"]["roc_auc"]
    print(f"  [ML]   acc={acc:.4f}  f1={f1:.4f}  "
          + (f"auc={auc:.4f}" if auc else "auc=N/A"))
    cm2 = result["ml"]["confusion_matrix"]
    print(f"  [ML]   ConfMatrix  TN={cm2['TN']}  FP={cm2['FP']}  "
          f"FN={cm2['FN']}  TP={cm2['TP']}")

    # ── 3. Generate P4 ────────────────────────────────────────────────────
    print(f"  [P4]   Generating P4 code ({mode}) …")
    p4_ok = generate_p4(num_trees, max_depth, certainty, arch, actual_features, mode=mode)
    if not p4_ok:
        result["compile"] = {"status": "SKIPPED_P4_FAILED"}
        return result

    # Encode forest 0 (forest 1 not needed for resource testing; encodings are symmetric)
    try:
        rf_encoding(rf, forest_id=0, mode=mode)
        if (ROOT_DIR / "p4src" / "s1-commands.txt").exists():
            (ROOT_DIR / "p4src" / "s1-commands.txt").rename(
                ROOT_DIR / "p4src" / "forest0-commands.txt"
            )
    except Exception as exc:
        print(f"  [Encode] WARNING: {exc} (compile will proceed anyway)")

    # ── 4. Compile ────────────────────────────────────────────────────────
    if compile_enabled:
        print(f"  [Compile] Running p4_build (timeout={compile_timeout}s) …")
        compile_result = compile_p4(arch, cfg_id, compile_timeout)
        result["compile"] = compile_result
        status_icon = "✓" if compile_result["status"] == "SUCCESS" else "✗"
        print(f"  [Compile] {status_icon} {compile_result['status']}  "
              f"({compile_result['compile_time_s']}s)")
        if compile_result["status"] == "SUCCESS":
            cr = compile_result["mau"]
            print(f"  [HW]    Stages (ingress/egress/total):  "
                  f"{cr.get('n_stages_ingress','?')} / "
                  f"{cr.get('n_stages_egress','?')} / "
                  f"{cr.get('n_stages_total','?')}  "
                  f"(active MAU rows with SRAM/TCAM: {cr.get('n_active_stages','?')})")
            print(f"  [HW]    SRAM={cr.get('total_sram','?')}  "
                  f"TCAM={cr.get('total_tcam','?')}  "
                  f"MapRAM={cr.get('total_map_ram','?')}  "
                  f"VLIW={cr.get('total_vliw_instr','?')}  "
                  f"MeterALU={cr.get('total_meter_alu','?')}  "
                  f"Tables={cr.get('n_tables_placed','?')}  "
                  f"CritPath={cr.get('critical_path','?')}")
    else:
        print(f"  [Compile] SKIPPED (--no-compile)")

    return result


# ---------------------------------------------------------------------------
# Experiment 1 – Feature sweep
# ---------------------------------------------------------------------------

def run_feature_sweep(
    arch: str,
    compile_enabled: bool = True,
    compile_timeout: int = COMPILE_TIMEOUT,
    dataset: Optional[str] = None,
    no_grid_search: bool = False,
    mode: str = "reporter",
) -> List[Dict[str, Any]]:
    """
    Vary k = 3 … 8 features with num_trees=2, max_depth=2.
    Features are chosen as the top-k by importance from a probe RF.
    """
    print("\n" + "═"*68)
    print("  EXPERIMENT 1 – Feature Count Sweep")
    print(f"  Fixed: {FEATURE_SWEEP_TREES} trees, depth {FEATURE_SWEEP_DEPTH}")
    print(f"  Sweeping k ∈ {FEATURE_SWEEP_KLIST}")
    print("═"*68)

    # Stable feature ranking from a probe run
    os.chdir(ROOT_DIR)
    ranking = get_feature_ranking(dataset=dataset, no_grid_search=no_grid_search)

    results = []
    for k in FEATURE_SWEEP_KLIST:
        top_k = ranking[:k]
        r = benchmark_single_config(
            num_trees=FEATURE_SWEEP_TREES,
            max_depth=FEATURE_SWEEP_DEPTH,
            forced_features=top_k,
            arch=arch,
            certainty=CERTAINTY_DEFAULT,
            compile_enabled=compile_enabled,
            compile_timeout=compile_timeout,
            label=f"feat_k{k}",
            dataset=dataset,
            no_grid_search=no_grid_search,
            mode=mode,
        )
        results.append(r)

    return results


# ---------------------------------------------------------------------------
# Experiment 2 – Tree / depth sweep
# ---------------------------------------------------------------------------

def run_tree_sweep(
    arch: str,
    compile_enabled: bool = True,
    compile_timeout: int = COMPILE_TIMEOUT,
    dataset: Optional[str] = None,
    no_grid_search: bool = False,
    mode: str = "reporter",
) -> List[Dict[str, Any]]:
    """
    Sweep (num_trees, max_depth) pairs.  Skip any pair with
    est_stages = num_trees * (max_depth + 1) > RESOURCE_CAP_STAGES.
    Min trees = TREE_SWEEP_MIN_TREES (for meaningful majority vote).
    """
    if mode == "translator":
        max_trees = TRANSLATOR_TREE_SWEEP_MAX_TREES
        max_depth = TRANSLATOR_TREE_SWEEP_MAX_DEPTH
        stage_cap = TRANSLATOR_RESOURCE_CAP_STAGES
    else:
        max_trees = TREE_SWEEP_MAX_TREES
        max_depth = TREE_SWEEP_MAX_DEPTH
        stage_cap = RESOURCE_CAP_STAGES

    print("\n" + "═"*68)
    print(f"  EXPERIMENT 2 – Tree / Depth Configuration Sweep ({mode})")
    print(f"  trees ∈ [{TREE_SWEEP_MIN_TREES} … {max_trees}]  "
          f"depth ∈ [{TREE_SWEEP_MIN_DEPTH} … {max_depth}]")
    print(f"  Resource cap: est_stages = trees*(depth+1) ≤ {stage_cap}")
    print("═"*68)

    os.chdir(ROOT_DIR)

    # Build grid and report skipped configs upfront
    configs = []
    skipped = []
    for t in range(TREE_SWEEP_MIN_TREES, max_trees + 1):
        for d in range(TREE_SWEEP_MIN_DEPTH, max_depth + 1):
            est = t * (d + 1)
            if est <= stage_cap:
                configs.append((t, d))
            else:
                skipped.append((t, d, est))

    print(f"\n  Configurations to test ({len(configs)}):")
    for t, d in configs:
        print(f"    trees={t}  depth={d}  est_stages={t*(d+1)}")
    if skipped:
        print(f"\n  Configurations skipped ({len(skipped)}) – exceed stage cap:")
        for t, d, est in skipped:
            print(f"    trees={t}  depth={d}  est_stages={est} > {stage_cap}")

    results = []
    for t, d in configs:
        r = benchmark_single_config(
            num_trees=t,
            max_depth=d,
            forced_features=None,       # let model select features
            arch=arch,
            certainty=CERTAINTY_DEFAULT,
            compile_enabled=compile_enabled,
            compile_timeout=compile_timeout,
            min_features=3,
            label=f"{t}t_d{d}",
            dataset=dataset,
            no_grid_search=no_grid_search,
            mode=mode,
        )
        results.append(r)

    return results


# ---------------------------------------------------------------------------
# Report generation
# ---------------------------------------------------------------------------

def _ml_row(r: Dict) -> Tuple:
    ml = r.get("ml", {})
    if ml.get("status") != "OK":
        na = "N/A"
        return (r["config_id"], na, na, na, na, na, str(r["est_pipeline_stages"]))
    return (
        r["config_id"],
        _fmt_pct(ml.get("accuracy")),
        _fmt_pct(ml.get("f1_macro")),
        _fmt_pct(ml.get("precision_macro")),
        _fmt_pct(ml.get("recall_macro")),
        (_fmt_pct(ml.get("roc_auc")) if ml.get("roc_auc") else "N/A"),
        str(r["est_pipeline_stages"]),
    )


def _compile_row(r: Dict) -> Tuple:
    c   = r.get("compile", {})
    mau = c.get("mau", {})
    status = c.get("status", "N/A")
    if status == "SUCCESS":
        stages_ing = mau.get("n_stages_ingress", "?")
        stages_egr = mau.get("n_stages_egress",  "?")
        sram       = mau.get("total_sram",        "?")
        tcam       = mau.get("total_tcam",        "?")
        vliw       = mau.get("total_vliw_instr",  "?")
        tables     = mau.get("n_tables_placed",   "?")
        cpath      = mau.get("critical_path",     "?")
        stages_str = f"{stages_ing}/{stages_egr}"
    else:
        stages_str = sram = tcam = vliw = tables = cpath = "N/A"
    return (
        r["config_id"],
        status,
        f"{c.get('compile_time_s', 'N/A')}s",
        stages_str,
        str(sram),
        str(tcam),
        str(vliw),
        str(tables),
        str(cpath),
        str(r["est_pipeline_stages"]),
    )


def print_summary_tables(results: List[Dict], experiment_name: str) -> None:
    """Print ML + resource summary tables to stdout."""
    header = f"\n{'═'*68}\n  RESULTS: {experiment_name}\n{'═'*68}"
    print(header)

    # ML table
    ml_headers = ["Config", "Accuracy", "F1-macro", "Precision", "Recall", "ROC-AUC", "Est.Stages"]
    ml_rows    = [_ml_row(r) for r in results]
    col_w      = [max(len(h), max((len(str(row[i])) for row in ml_rows), default=0))
                  for i, h in enumerate(ml_headers)]
    sep = "  ".join("─" * w for w in col_w)
    fmt = "  ".join(f"{{:<{w}}}" for w in col_w)

    print("\n  ── ML Metrics ──")
    print("  " + fmt.format(*ml_headers))
    print("  " + sep)
    for row in ml_rows:
        print("  " + fmt.format(*row))

    # Compile table
    c_headers = ["Config", "Compile", "Time", "Stg Ing/Egr", "SRAM", "TCAM", "VLIW", "Tables", "CritPath", "Est.Stages"]
    c_rows    = [_compile_row(r) for r in results]
    col_w2    = [max(len(h), max((len(str(row[i])) for row in c_rows), default=0))
                 for i, h in enumerate(c_headers)]
    sep2 = "  ".join("─" * w for w in col_w2)
    fmt2 = "  ".join(f"{{:<{w}}}" for w in col_w2)

    print("\n  ── Hardware Resources ──")
    print("  " + fmt2.format(*c_headers))
    print("  " + sep2)
    for row in c_rows:
        print("  " + fmt2.format(*row))

    # Feature sweep: per-k ML quick view
    if "Feature" in experiment_name:
        print("\n  ── Feature Detail ──")
        for r in results:
            ml = r.get("ml", {})
            if ml.get("status") != "OK":
                continue
            feats = ", ".join(ml.get("features", []))
            acc   = _fmt_pct(ml.get("accuracy"))
            auc   = _fmt_pct(ml.get("roc_auc")) if ml.get("roc_auc") else "N/A"
            cm    = ml.get("confusion_matrix", {})
            print(f"  k={ml['num_features']:1d}  acc={acc}  auc={auc}  "
                  f"TP={cm.get('TP','?')}  FP={cm.get('FP','?')}  "
                  f"FN={cm.get('FN','?')}  TN={cm.get('TN','?')}")
            print(f"       features: {feats}")

    # Analysis: best ML config (successful compile)
    ok_compile = [r for r in results
                  if r.get("compile", {}).get("status") == "SUCCESS"
                  and r.get("ml", {}).get("status") == "OK"]
    if ok_compile:
        best_acc = max(ok_compile, key=lambda r: r["ml"]["accuracy"])
        best_f1  = max(ok_compile, key=lambda r: r["ml"]["f1_macro"])
        print(f"\n  ── Analysis (compile-verified configs only) ──")
        print(f"  Best accuracy : {best_acc['config_id']}  "
              f"acc={_fmt_pct(best_acc['ml']['accuracy'])}")
        print(f"  Best F1-macro : {best_f1['config_id']}  "
              f"f1={_fmt_pct(best_f1['ml']['f1_macro'])}")
        c_ok_all = [r for r in results if r.get("compile", {}).get("status") == "SUCCESS"]
        print(f"  Compile rate  : {len(c_ok_all)}/{len(results)} passed")


def save_report(
    results: List[Dict],
    experiment_name: str,
    arch: str,
) -> Path:
    """Save full JSON report to benchmark_reports/."""
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    ts       = _ts()
    exp_slug = experiment_name.lower().replace(" ", "_")
    filename = REPORT_DIR / f"benchmark_{exp_slug}_{arch}_{ts}.json"

    report = {
        "meta": {
            "experiment":       experiment_name,
            "arch":             arch,
            "timestamp":        ts,
            "resource_cap":     RESOURCE_CAP_STAGES,
            "accuracy_threshold": ACCURACY_THRESHOLD,
            "certainty_default": CERTAINTY_DEFAULT,
            "n_configs":        len(results),
        },
        "results": results,
        "summary": {
            "n_total":      len(results),
            "n_ml_ok":      sum(1 for r in results if r.get("ml", {}).get("status") == "OK"),
            "n_compile_ok": sum(1 for r in results
                               if r.get("compile", {}).get("status") == "SUCCESS"),
        },
    }

    filename.write_text(json.dumps(report, indent=2))
    print(f"\n  📄 Report saved: {filename.relative_to(ROOT_DIR)}")
    return filename


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(
        description="pForest resource & accuracy benchmark for Tofino2",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=textwrap.dedent("""\
            Examples
            --------
            python3 src/benchmark.py --experiment features --arch t2na
            python3 src/benchmark.py --experiment trees --arch t2na
            python3 src/benchmark.py --experiment all --no-compile
            python3 src/benchmark.py --experiment trees --mode translator
        """),
    )
    parser.add_argument(
        "--experiment", "-e",
        choices=["features", "trees", "all"],
        default="all",
        help="Which experiment to run (default: all)",
    )
    parser.add_argument(
        "--arch", "-a",
        choices=["tna", "t2na"],
        default=DEFAULT_ARCH,
        help="Target Tofino architecture (default: t2na)",
    )
    parser.add_argument(
        "--no-compile",
        action="store_true",
        default=False,
        help="Skip compilation; ML training and P4 generation only",
    )
    parser.add_argument(
        "--compile-timeout",
        type=int,
        default=COMPILE_TIMEOUT,
        metavar="SECONDS",
        help=f"Compilation timeout per config (default: {COMPILE_TIMEOUT}s)",
    )
    parser.add_argument(
        "--dataset", "-d",
        choices=list(DATASETS),
        default=None,
        help=f"Dataset to train on (default: {DEFAULT_DATASET}). "
             f"Available: {', '.join(DATASETS)}",
    )
    parser.add_argument(
        "--no-grid-search",
        action="store_true",
        default=False,
        help="Skip GridSearchCV; train directly with balanced/gini defaults (much faster)",
    )
    parser.add_argument(
        "--mode", "-m",
        choices=["reporter", "translator"],
        default="reporter",
        help="Pipeline mode: reporter (egress classification) or translator "
             "(ingress-only classification) (default: reporter)",
    )
    args = parser.parse_args()

    compile_enabled = not args.no_compile
    arch            = args.arch
    timeout         = args.compile_timeout
    dataset         = args.dataset
    no_grid_search  = args.no_grid_search
    mode            = args.mode

    os.chdir(ROOT_DIR)

    all_results = []

    if args.experiment in ("features", "all"):
        feat_results = run_feature_sweep(
            arch=arch,
            compile_enabled=compile_enabled,
            compile_timeout=timeout,
            dataset=dataset,
            no_grid_search=no_grid_search,
            mode=mode,
        )
        all_results.extend(feat_results)
        print_summary_tables(feat_results, "Experiment 1 – Feature Sweep")
        save_report(feat_results, "experiment1_feature_sweep", arch)

    if args.experiment in ("trees", "all"):
        tree_results = run_tree_sweep(
            arch=arch,
            compile_enabled=compile_enabled,
            compile_timeout=timeout,
            dataset=dataset,
            no_grid_search=no_grid_search,
            mode=mode,
        )
        all_results.extend(tree_results)
        print_summary_tables(tree_results, "Experiment 2 – Tree/Depth Sweep")
        save_report(tree_results, "experiment2_tree_depth_sweep", arch)

    if args.experiment == "all":
        save_report(all_results, "all_experiments", arch)

    print(f"\n{'═'*68}")
    print("  Benchmark complete.")
    print(f"  Reports in: benchmark_reports/")
    print(f"{'═'*68}\n")


if __name__ == "__main__":
    main()
