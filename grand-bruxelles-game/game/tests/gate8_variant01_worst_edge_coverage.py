from __future__ import annotations

import collections
import json
import pathlib
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: gate.py CONTRACT TOPOLOGY_RESULT OUT")

contract = json.loads(pathlib.Path(sys.argv[1]).read_text())
topology = json.loads(pathlib.Path(sys.argv[2]).read_text())
out_path = pathlib.Path(sys.argv[3])
source = contract["source_topology_artifact"]

if topology.get("diagnostic_state") != source["expected_state"]:
    raise SystemExit("topology state mismatch")
rows = topology.get("blocked_case_topology", [])
if topology.get("blocked_case_count") != source["expected_blocked_cases"] or len(rows) != source["expected_blocked_cases"]:
    raise SystemExit("blocked topology count mismatch")

class_counts = collections.Counter(r.get("topology", {}).get("classification") for r in rows)
if dict(sorted(class_counts.items())) != dict(sorted(contract["expected"]["classification_counts"].items())):
    raise SystemExit(f"classification drift: {class_counts}")

def family(case: str) -> str:
    if "_shoulder_" in case or "_upper_arm_" in case:
        return "shoulder"
    if "_forearm_" in case:
        return "forearm"
    if "_hand_" in case:
        return "hand"
    return "other"

edge_rows = collections.defaultdict(list)
for row in rows:
    key = (str(row["surface"]), int(row["vertex_a"]), int(row["vertex_b"]))
    edge_rows[key].append(row)

expected = contract["expected"]
if len(edge_rows) != expected["unique_worst_edges"]:
    raise SystemExit(f"expected {expected['unique_worst_edges']} unique worst edges, got {len(edge_rows)}")

multiplicities = sorted(len(v) for v in edge_rows.values())
if multiplicities != sorted(expected["edge_case_multiplicities"]):
    raise SystemExit(f"edge multiplicity drift: {multiplicities}")

unique_vertices = set()
edge_evidence = []
covered_cases = set()
for (surface, va, vb), group in sorted(edge_rows.items(), key=lambda kv: (-len(kv[1]), kv[0][1], kv[0][2])):
    unique_vertices.update((va, vb))
    cases = sorted(str(r["case"]) for r in group)
    if covered_cases.intersection(cases):
        raise SystemExit("case assigned to more than one worst edge")
    covered_cases.update(cases)
    topologies = [r["topology"] for r in group]
    a = {str(i["bone"]): float(i["weight"]) for i in topologies[0]["vertex_a_influences"]}
    b = {str(i["bone"]): float(i["weight"]) for i in topologies[0]["vertex_b_influences"]}
    l1 = sum(abs(a.get(bone, 0.0) - b.get(bone, 0.0)) for bone in set(a) | set(b))
    families = sorted(set(family(c) for c in cases))
    if len(families) != 1:
        raise SystemExit(f"edge crosses role families: {families}")
    edge_evidence.append({
        "surface": surface,
        "vertex_a": va,
        "vertex_b": vb,
        "case_count": len(group),
        "cases": cases,
        "family": families[0],
        "classification_counts": dict(sorted(collections.Counter(t["classification"] for t in topologies).items())),
        "rotated_bones": sorted(set(str(t["rotated_bone"]) for t in topologies)),
        "endpoint_distribution_l1": l1,
        "max_edge_change_m": max(float(r["edge_change_m"]) for r in group),
        "max_stretch_ratio": max(float(r["stretch_ratio"]) for r in group),
        "vertex_a_influences": topologies[0]["vertex_a_influences"],
        "vertex_b_influences": topologies[0]["vertex_b_influences"],
    })

if len(unique_vertices) != expected["unique_vertices"]:
    raise SystemExit(f"expected {expected['unique_vertices']} unique vertices, got {len(unique_vertices)}")
if len(covered_cases) != source["expected_blocked_cases"]:
    raise SystemExit("not all blocked cases covered")

family_counts = collections.Counter()
for edge in edge_evidence:
    family_counts[edge["family"]] += edge["case_count"]
if dict(sorted(family_counts.items())) != dict(sorted(expected["family_case_counts"].items())):
    raise SystemExit(f"family coverage drift: {family_counts}")

rails = contract["rails"]
if not rails or any(bool(v) for v in rails.values()):
    raise SystemExit("authorization rail opened")

result = {
    "diagnostic_state": "BLOCKED_WORST_EDGE_COVERAGE_READY",
    "base_main_sha": contract["base_main_sha"],
    "candidate_variant": contract["candidate_variant"],
    "target_sha256": contract["target_sha256"],
    "blocked_case_count": len(rows),
    "covered_blocked_case_count": len(covered_cases),
    "coverage_fraction": len(covered_cases) / len(rows),
    "unique_worst_edges": len(edge_rows),
    "unique_vertices": len(unique_vertices),
    "unique_vertex_ids": sorted(unique_vertices),
    "classification_counts": dict(sorted(class_counts.items())),
    "family_case_counts": dict(sorted(family_counts.items())),
    "edge_case_multiplicities": multiplicities,
    "edges": edge_evidence,
    "rails": rails,
    "next_safe_axis": "VERIFY_SIX_EDGE_GEOMETRIC_ADJACENCY_AND_SEAM_DUPLICATES_BEFORE_LOCAL_REWEIGHT",
    "production_activation_allowed": False,
    "visual_approval_allowed": False,
}
if result["coverage_fraction"] < expected["minimum_coverage_fraction"]:
    raise SystemExit("coverage below contract")
out_path.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n")
print(json.dumps({k: result[k] for k in ("diagnostic_state", "blocked_case_count", "unique_worst_edges", "unique_vertices", "family_case_counts", "next_safe_axis")}, sort_keys=True))
