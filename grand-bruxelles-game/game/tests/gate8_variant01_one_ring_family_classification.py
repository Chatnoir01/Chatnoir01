from __future__ import annotations

import json
import pathlib
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: classifier.py CONTRACT_JSON ONE_RING_RESULT OUT_JSON")

contract = json.loads(pathlib.Path(sys.argv[1]).read_text())
source = json.loads(pathlib.Path(sys.argv[2]).read_text())
out_path = pathlib.Path(sys.argv[3])

failures: list[str] = []

if source.get("diagnostic_state") != contract["source_artifact"]["expected_state"]:
    failures.append("source_state_mismatch")
if int(source.get("audited_edge_count", -1)) != int(contract["source_artifact"]["expected_edges"]):
    failures.append("source_edge_count_mismatch")
if int(source.get("target_vertex_total", -1)) != int(contract["source_artifact"]["expected_vertices"]):
    failures.append("source_vertex_count_mismatch")
if source.get("godot_version") != contract["source_artifact"]["godot_version"]:
    failures.append("source_godot_version_mismatch")
if source.get("failures") != []:
    failures.append("source_has_failures")
if source.get("all_pair_bilateral_local_maxima") is not True:
    failures.append("source_local_maxima_not_confirmed")

edges = source.get("edges", [])
if len(edges) != 6:
    failures.append("expected_six_edges")

by_family: dict[str, list[dict]] = {}
for edge in edges:
    family = str(edge.get("family", ""))
    by_family.setdefault(family, []).append(edge)
    if edge.get("pair_is_bilateral_local_maximum") is not True:
        failures.append(f"pair_not_bilateral_local_maximum:{family}:{edge.get('vertex_a')}:{edge.get('vertex_b')}")
    for endpoint_name in ("endpoint_a", "endpoint_b"):
        endpoint = edge.get(endpoint_name, {})
        if int(endpoint.get("neighbor_count", 0)) <= 0:
            failures.append(f"empty_one_ring:{family}:{endpoint_name}")
        if endpoint.get("pair_present") is not True:
            failures.append(f"pair_missing_from_one_ring:{family}:{endpoint_name}")
        weight_sum = float(endpoint.get("weight_sum", 0.0))
        if abs(weight_sum - 1.0) > 0.0002:
            failures.append(f"weight_sum_drift:{family}:{endpoint_name}:{weight_sum}")

expected = contract["expected_families"]
for family in expected:
    if len(by_family.get(family, [])) != int(expected[family]["edge_count"]):
        failures.append(f"family_edge_count_mismatch:{family}")
for unexpected in sorted(set(by_family) - set(expected)):
    failures.append(f"unexpected_family:{unexpected}")

classified: list[dict] = []
counts: dict[str, int] = {}

for family in ("shoulder", "forearm", "hand"):
    for edge in by_family.get(family, []):
        a = float(edge["endpoint_a"]["max_other_neighbor_weight_l1"])
        b = float(edge["endpoint_b"]["max_other_neighbor_weight_l1"])
        lo, hi = sorted((a, b))
        signature = "UNCLASSIFIED"
        if family == "shoulder":
            cfg = expected[family]
            if lo <= float(cfg["coherent_side_max_other_l1_max"]) and hi >= float(cfg["broad_side_max_other_l1_min"]):
                signature = cfg["signature"]
        elif family == "forearm":
            cfg = expected[family]
            if a >= float(cfg["both_sides_max_other_l1_min"]) and b >= float(cfg["both_sides_max_other_l1_min"]):
                signature = cfg["signature"]
        elif family == "hand":
            cfg = expected[family]
            if lo <= float(cfg["narrow_side_max_other_l1_max"]) and hi >= float(cfg["broad_side_max_other_l1_min"]):
                signature = cfg["signature"]

        if signature == "UNCLASSIFIED":
            failures.append(f"unclassified_edge:{family}:{edge.get('vertex_a')}:{edge.get('vertex_b')}:a={a}:b={b}")
        counts[signature] = counts.get(signature, 0) + 1
        classified.append({
            "family": family,
            "surface": edge.get("surface"),
            "vertex_a": int(edge.get("vertex_a", -1)),
            "vertex_b": int(edge.get("vertex_b", -1)),
            "pair_weight_l1": float(edge.get("pair_weight_l1", 0.0)),
            "endpoint_a_max_other_l1": a,
            "endpoint_b_max_other_l1": b,
            "signature": signature,
        })

for family, cfg in expected.items():
    expected_count = int(cfg["edge_count"])
    actual_count = sum(1 for row in classified if row["family"] == family and row["signature"] == cfg["signature"])
    if actual_count != expected_count:
        failures.append(f"signature_count_mismatch:{family}:{actual_count}:{expected_count}")

result = {
    "format": contract["format"] + "-result",
    "diagnostic_state": "ONE_RING_FAMILY_SIGNATURES_CONFIRMED" if not failures else "ONE_RING_FAMILY_CLASSIFICATION_BLOCKED",
    "candidate_variant": int(contract["candidate_variant"]),
    "source_diagnostic_state": source.get("diagnostic_state"),
    "source_edge_count": len(edges),
    "classified_edges": classified,
    "signature_counts": counts,
    "failures": failures,
    "next_safe_axis": "FAMILY_SPECIFIC_AB_SHOULDER_FIRST" if not failures else "FIX_CLASSIFICATION_INPUT_OR_THRESHOLDS_WITH_NEW_MEASUREMENT",
    "rails": contract["rails"],
}
out_path.write_text(json.dumps(result, indent=2, sort_keys=True))
print(json.dumps(result, sort_keys=True))
if failures:
    raise SystemExit(1)
