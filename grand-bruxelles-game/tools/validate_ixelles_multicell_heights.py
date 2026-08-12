#!/usr/bin/env python3
"""Validate the four remaining locked Ixelles cells against semantic UrbIS 3D.

Evidence-only. The long-lived specialist branch may provide provenance-locked input
files, but this tool never grants runtime approval or invents height values.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import re
import statistics
from pathlib import Path

SCHEMA = "grand-bruxelles-ixelles-multicell-height-validation-v1"
LOCKED_CELLS = {
    "bxl-e149000-n169500-s500",
    "bxl-e149500-n168500-s500",
    "bxl-e149500-n169000-s500",
    "bxl-e149500-n169500-s500",
}


def bbox_for_cell(cell: str) -> list[float]:
    m = re.fullmatch(r"bxl-e(\d+)-n(\d+)-s500", cell)
    if not m or cell not in LOCKED_CELLS:
        raise ValueError("cell is outside the locked Ixelles validation block")
    e, n = map(float, m.groups())
    return [e, n, e + 500.0, n + 500.0]


def percentile(values: list[float], p: float) -> float | None:
    if not values:
        return None
    s = sorted(values)
    x = (len(s) - 1) * p
    lo, hi = math.floor(x), math.ceil(x)
    if lo == hi:
        return s[lo]
    return s[lo] * (hi - x) + s[hi] * (x - lo)


def variant_metrics(records: list[dict], key: str) -> dict:
    if not records:
        raise ValueError("no joined comparisons; calibration cannot be asserted")
    signed = [float(r[key]) - float(r["semantic_height_m"]) for r in records]
    absolute = [abs(v) for v in signed]
    n = len(records)
    return {
        "n": n,
        "mae_m": statistics.fmean(absolute),
        "abs_median_m": statistics.median(absolute),
        "abs_p90_m": percentile(absolute, .90),
        "signed_mean_m": statistics.fmean(signed),
        "signed_median_m": statistics.median(signed),
        "within_2m_fraction": sum(v <= 2 for v in absolute) / n,
        "within_4m_fraction": sum(v <= 4 for v in absolute) / n,
        "outliers_gt_8m": sum(v > 8 for v in absolute),
    }


def calibrate_any(comparison: dict, semantic: dict, cell: str) -> dict:
    bbox = bbox_for_cell(cell)
    if comparison.get("cell") != cell or comparison.get("source_crs") != "EPSG:31370":
        raise ValueError("comparison scope/CRS mismatch")
    if comparison.get("runtime_approved") is not False:
        raise ValueError("comparison must remain runtime-unapproved")
    if semantic.get("cell") != cell or semantic.get("bbox_epsg31370") != bbox:
        raise ValueError("semantic evidence scope mismatch")
    if (semantic.get("policy") or {}).get("runtime_approval") is not False:
        raise ValueError("semantic evidence must remain runtime-unapproved")

    records = comparison.get("records", [])
    variants = {k: variant_metrics(records, k) for k in (
        "dsm_height_p50_m", "dsm_height_p75_m", "dsm_height_p90_m", "dsm_policy_candidate_m"
    )}
    ranked = sorted(variants.items(), key=lambda kv: (kv[1]["mae_m"], abs(kv[1]["signed_mean_m"]), kv[0]))
    best_key = ranked[0][0]
    best_name = best_key.removeprefix("dsm_height_").removesuffix("_m") if best_key != "dsm_policy_candidate_m" else "current_policy"
    conflicts = [r for r in records if float(r["abs_delta_m"]) > 4.0]
    severe = [r for r in records if float(r["abs_delta_m"]) > 8.0]
    return {
        "schema": SCHEMA,
        "cell": cell,
        "bbox_epsg31370": bbox,
        "source_crs": "EPSG:31370",
        "counts": {
            "joined": len(records),
            "current_conflicts_gt_4m": len(conflicts),
            "current_severe_gt_8m": len(severe),
            "conflicts_overestimate": sum(float(r["candidate_minus_semantic_m"]) > 0 for r in conflicts),
            "conflicts_underestimate": sum(float(r["candidate_minus_semantic_m"]) < 0 for r in conflicts),
        },
        "variant_metrics": variants,
        "decision": {
            "best_tested_statistic": best_name,
            "promote_runtime": False,
            "reason": "This cell is calibration evidence only; runtime promotion requires consistent multi-cell evidence and a separate runtime gate.",
        },
        "runtime_approved": False,
    }


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def evaluate_cell(root: Path, buildings: Path, dsm_csv: Path, cell: str) -> dict:
    bbox = bbox_for_cell(cell)
    here = Path(__file__).resolve().parent
    matcher = load_module(here / "match_ixelles_urbis3d_semantic_heights.py", "ix_matcher")
    comparer = load_module(here / "compare_ixelles_semantic_dsm_heights.py", "ix_compare")

    matcher.ogr.UseExceptions()
    b = matcher.load_buildings(buildings, tuple(bbox))
    dataset, layer, package = matcher.find_buildingfaces(root)
    solids = matcher.collect_solids(layer, tuple(bbox))
    semantic = matcher.build_evidence(b, solids, tuple(bbox))
    semantic["cell"] = cell
    semantic["bbox_epsg31370"] = bbox
    semantic["source_package_path"] = str(package)

    comparison = comparer.compare(semantic, comparer.load_dsm_rows(dsm_csv, cell), cell)
    comparison["bbox_epsg31370"] = bbox
    calibration = calibrate_any(comparison, semantic, cell)
    dataset = None
    return {"semantic": semantic, "comparison": comparison, "calibration": calibration}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, required=True)
    ap.add_argument("--buildings", type=Path, required=True)
    ap.add_argument("--dsm-csv", type=Path, required=True)
    ap.add_argument("--cell", required=True)
    ap.add_argument("--output", type=Path, required=True)
    args = ap.parse_args()
    result = evaluate_cell(args.root, args.buildings, args.dsm_csv, args.cell)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({
        "cell": args.cell,
        "semantic_counts": result["semantic"]["counts"],
        "comparison_counts": result["comparison"]["counts"],
        "decision": result["calibration"]["decision"],
        "runtime_approved": False,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
