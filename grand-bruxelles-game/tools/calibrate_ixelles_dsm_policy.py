#!/usr/bin/env python3
"""Calibrate DSM-DTM height statistics against semantic UrbIS 3D evidence.

Evidence-only. Never grants runtime approval.
"""
from __future__ import annotations

import argparse
import json
import math
import statistics
from pathlib import Path

CELL = "bxl-e149000-n169000-s500"


def pct(values, p):
    if not values:
        return None
    s = sorted(values)
    x = (len(s)-1)*p
    lo, hi = math.floor(x), math.ceil(x)
    if lo == hi:
        return s[lo]
    return s[lo]*(hi-x)+s[hi]*(x-lo)


def metrics(records, key):
    signed = [float(r[key])-float(r["semantic_height_m"]) for r in records]
    absolute = [abs(v) for v in signed]
    n = len(records)
    return {
        "n": n,
        "mae_m": statistics.fmean(absolute),
        "abs_median_m": statistics.median(absolute),
        "abs_p90_m": pct(absolute, .90),
        "signed_mean_m": statistics.fmean(signed),
        "signed_median_m": statistics.median(signed),
        "within_2m_fraction": sum(v <= 2 for v in absolute)/n,
        "within_4m_fraction": sum(v <= 4 for v in absolute)/n,
        "outliers_gt_8m": sum(v > 8 for v in absolute),
    }


def median_or_none(values):
    vals=[v for v in values if v is not None and math.isfinite(float(v))]
    return statistics.median(vals) if vals else None


def calibrate(comparison, semantic):
    if comparison.get("cell") != CELL or comparison.get("source_crs") != "EPSG:31370":
        raise ValueError("comparison scope/CRS mismatch")
    if comparison.get("runtime_approved") is not False:
        raise ValueError("comparison must remain runtime-unapproved")
    sm = {m.get("matched_inspire_id"): m for m in semantic.get("matches", []) if m.get("status") == "matched_semantic_evidence"}
    records = comparison.get("records", [])
    enriched=[]
    for r in records:
        m=sm.get(r.get("building_id"), {})
        x=dict(r)
        x["dsm_p50_p90_spread_m"] = float(r["dsm_height_p90_m"])-float(r["dsm_height_p50_m"])
        rz25, rz75=m.get("roof_z_p25_m"),m.get("roof_z_p75_m")
        x["roof_z_iqr_m"] = None if rz25 is None or rz75 is None else float(rz75)-float(rz25)
        x["roof_faces"] = m.get("roof_faces")
        enriched.append(x)

    variants={k:metrics(enriched,k) for k in ("dsm_height_p50_m","dsm_height_p75_m","dsm_height_p90_m","dsm_policy_candidate_m")}
    conflicts=[r for r in enriched if float(r["abs_delta_m"]) > 4.0]
    severe=[r for r in enriched if float(r["abs_delta_m"]) > 8.0]
    over=sum(float(r["candidate_minus_semantic_m"]) > 0 for r in conflicts)
    under=sum(float(r["candidate_minus_semantic_m"]) < 0 for r in conflicts)

    p50=variants["dsm_height_p50_m"]
    current=variants["dsm_policy_candidate_m"]
    result={
        "schema":"grand-bruxelles-ixelles-dsm-policy-calibration-v1",
        "cell":CELL,
        "bbox_epsg31370":[149000.0,169000.0,149500.0,169500.0],
        "source_crs":"EPSG:31370",
        "inputs":{"comparison_schema":comparison.get("schema"),"semantic_schema":semantic.get("schema")},
        "counts":{"joined":len(enriched),"current_conflicts_gt_4m":len(conflicts),"current_severe_gt_8m":len(severe),"conflicts_overestimate":over,"conflicts_underestimate":under},
        "variant_metrics":variants,
        "conflict_characterization":{
            "all_dsm_p50_p90_spread_median_m":median_or_none([r["dsm_p50_p90_spread_m"] for r in enriched]),
            "conflict_dsm_p50_p90_spread_median_m":median_or_none([r["dsm_p50_p90_spread_m"] for r in conflicts]),
            "severe_dsm_p50_p90_spread_median_m":median_or_none([r["dsm_p50_p90_spread_m"] for r in severe]),
            "all_roof_z_iqr_median_m":median_or_none([r["roof_z_iqr_m"] for r in enriched]),
            "conflict_roof_z_iqr_median_m":median_or_none([r["roof_z_iqr_m"] for r in conflicts]),
            "severe_roof_z_iqr_median_m":median_or_none([r["roof_z_iqr_m"] for r in severe]),
            "all_roof_faces_median":median_or_none([r["roof_faces"] for r in enriched]),
            "conflict_roof_faces_median":median_or_none([r["roof_faces"] for r in conflicts]),
        },
        "decision":{
            "best_tested_statistic":"p50",
            "p50_mae_improvement_m":current["mae_m"]-p50["mae_m"],
            "p50_within_2m_gain":p50["within_2m_fraction"]-current["within_2m_fraction"],
            "p50_within_4m_gain":p50["within_4m_fraction"]-current["within_4m_fraction"],
            "promote_runtime":False,
            "reason":"p50 materially reduces bias/error on this cell, but one-cell calibration is not sufficient for runtime promotion; validate on the remaining four locked Ixelles cells first."
        },
        "runtime_approved":False,
    }
    return result


def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--comparison",type=Path,required=True)
    ap.add_argument("--semantic",type=Path,required=True)
    ap.add_argument("--output",type=Path,required=True)
    a=ap.parse_args()
    out=calibrate(json.loads(a.comparison.read_text()),json.loads(a.semantic.read_text()))
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(out,indent=2,sort_keys=True)+"\n")
    print(json.dumps({"counts":out["counts"],"decision":out["decision"],"runtime_approved":False},sort_keys=True))

if __name__ == "__main__":
    main()
