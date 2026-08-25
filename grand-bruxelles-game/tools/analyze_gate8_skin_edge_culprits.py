#!/usr/bin/env python3
"""Classify the dominant bone pairs on the exact severe Walk_Formal skin-space edges.

This is intentionally diagnostic-only. It consumes the immutable Godot 4.7.1
skin-space result and turns endpoint weight discontinuities into a fail-closed,
reproducible culprit map before any retarget/Skin/rest change is attempted.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

EDGE_KEYS = ("max_absolute_edge", "max_stretch_edge", "min_compression_edge")


def _weight_map(rows: list[dict[str, Any]]) -> dict[str, float]:
    out: dict[str, float] = {}
    for row in rows:
        name = str(row.get("bone_name", ""))
        weight = float(row.get("weight", 0.0))
        if not name or name == "UNRESOLVED" or not math.isfinite(weight) or weight < 0.0:
            raise ValueError(f"invalid influence row: {row!r}")
        out[name] = out.get(name, 0.0) + weight
    return out


def analyze_edge(edge: dict[str, Any]) -> dict[str, Any]:
    wa = _weight_map(list(edge.get("vertex_a_weights", [])))
    wb = _weight_map(list(edge.get("vertex_b_weights", [])))
    if not wa or not wb:
        raise ValueError("both edge endpoints must have positive skin influences")

    bones = sorted(set(wa) | set(wb))
    discontinuities = [
        {
            "bone_name": name,
            "weight_a": wa.get(name, 0.0),
            "weight_b": wb.get(name, 0.0),
            "absolute_weight_delta": abs(wa.get(name, 0.0) - wb.get(name, 0.0)),
        }
        for name in bones
    ]
    discontinuities.sort(key=lambda row: (-float(row["absolute_weight_delta"]), str(row["bone_name"])))
    total = sum(float(row["absolute_weight_delta"]) for row in discontinuities)
    if not math.isfinite(total) or total <= 0.0:
        raise ValueError("edge has no measurable endpoint weight discontinuity")
    if len(discontinuities) < 2:
        raise ValueError("edge must expose at least two influencing bones")

    dominant_pair_rows = discontinuities[:2]
    pair = [str(row["bone_name"]) for row in dominant_pair_rows]
    pair_delta = sum(float(row["absolute_weight_delta"]) for row in dominant_pair_rows)
    pair_share = pair_delta / total
    if not math.isfinite(pair_share):
        raise ValueError("non-finite dominant pair share")

    return {
        "mesh": str(edge.get("mesh", "")),
        "surface": int(edge.get("surface", -1)),
        "triangle": int(edge.get("triangle", -1)),
        "vertices": [int(edge.get("vertex_a", -1)), int(edge.get("vertex_b", -1))],
        "rest_length_m": float(edge.get("rest_length_m", 0.0)),
        "posed_length_m": float(edge.get("posed_length_m", 0.0)),
        "absolute_change_m": float(edge.get("absolute_change_m", 0.0)),
        "ratio": float(edge.get("ratio", 0.0)),
        "weight_discontinuity_total": total,
        "bone_discontinuities": discontinuities,
        "dominant_pair": pair,
        "dominant_pair_weight_delta": pair_delta,
        "dominant_pair_share": pair_share,
    }


def analyze(evidence: dict[str, Any], contract: dict[str, Any]) -> dict[str, Any]:
    if evidence.get("format") != "grand-bruxelles-gate8-variant01-walk-formal-skin-space-v1":
        raise ValueError("unexpected evidence format")
    if evidence.get("diagnostic_state") != contract["source_evidence"]["diagnostic_state"]:
        raise ValueError("unexpected evidence diagnostic state")
    if evidence.get("failures") != []:
        raise ValueError("source Godot evidence contains failures")
    if evidence.get("production_authorized") is not False or evidence.get("activation_ready") is not False:
        raise ValueError("source evidence is not fail-closed")

    deformation = evidence.get("deformation")
    if not isinstance(deformation, dict):
        raise ValueError("missing deformation payload")

    pair_share_min = float(contract["analysis"]["dominant_pair_share_min"])
    expected_edges = contract["analysis"]["edges"]
    results: dict[str, Any] = {}
    failures: list[str] = []

    for key in EDGE_KEYS:
        edge = deformation.get(key)
        expected = expected_edges.get(key)
        if not isinstance(edge, dict) or not isinstance(expected, dict):
            failures.append(f"missing_edge={key}")
            continue
        row = analyze_edge(edge)
        row["classification"] = str(expected["classification"])
        results[key] = row

        exact_identity = (
            row["mesh"] == expected["mesh"]
            and row["surface"] == int(expected["surface"])
            and row["triangle"] == int(expected["triangle"])
            and row["vertices"] == [int(v) for v in expected["vertices"]]
        )
        if not exact_identity:
            failures.append(f"edge_identity_drift={key}")
        if set(row["dominant_pair"]) != set(expected["expected_pair"]):
            failures.append(f"dominant_pair_drift={key}:{row['dominant_pair']}")
        if float(row["dominant_pair_share"]) < pair_share_min:
            failures.append(f"dominant_pair_share_too_low={key}:{row['dominant_pair_share']:.9f}")

    return {
        "format": "grand-bruxelles-gate8-variant01-walk-formal-skin-edge-culprits-result-v1",
        "candidate_variant": 1,
        "candidate_static_verdict": "AMELIORER",
        "source_engine": contract["source_evidence"]["engine"],
        "source_run_id": int(contract["source_evidence"]["run_id"]),
        "source_artifact_id": int(contract["source_evidence"]["artifact_id"]),
        "analysis_metric": contract["analysis"]["metric"],
        "dominant_pair_share_min": pair_share_min,
        "edges": results,
        "diagnostic_state": "DOMINANT_SKIN_WEIGHT_BOUNDARIES_LOCALIZED" if not failures else "BLOCKED_EDGE_CULPRIT_DRIFT",
        "walk_alias_selected": "",
        "run_alias_selected": "",
        "retarget_changed": False,
        "skin_changed": False,
        "rest_pose_changed": False,
        "thresholds_changed": False,
        "production_authorized": False,
        "activation_ready": False,
        "adoption_ready": False,
        "runtime_population_changed": False,
        "visual_approval_claimed": False,
        "failures": failures,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", required=True, type=Path)
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    evidence = json.loads(args.evidence.read_text())
    contract = json.loads(args.contract.read_text())
    result = analyze(evidence, contract)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")

    for key in EDGE_KEYS:
        row = result.get("edges", {}).get(key, {})
        if row:
            print(
                "GATE8_SKIN_EDGE_CULPRIT edge=%s pair=%s share=%.6f abs_change=%.6f ratio=%.6f"
                % (
                    key,
                    "+".join(row["dominant_pair"]),
                    float(row["dominant_pair_share"]),
                    float(row["absolute_change_m"]),
                    float(row["ratio"]),
                )
            )
    print(
        "GATE8_SKIN_EDGE_CULPRITS_RESULT state=%s failures=%d production_authorized=false"
        % (result["diagnostic_state"], len(result["failures"]))
    )
    return 0 if not result["failures"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
