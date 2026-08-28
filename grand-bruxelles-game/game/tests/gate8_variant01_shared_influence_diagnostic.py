from __future__ import annotations

import json
import pathlib
import sys

if len(sys.argv) != 4:
    raise SystemExit("usage: diagnostic.py CONTRACT TOPOLOGY_RESULT OUT")

contract = json.loads(pathlib.Path(sys.argv[1]).read_text())
topology = json.loads(pathlib.Path(sys.argv[2]).read_text())
out_path = pathlib.Path(sys.argv[3])

source = contract["source_topology_artifact"]
if topology.get("diagnostic_state") != source["expected_state"]:
    raise SystemExit("topology diagnostic state mismatch")
if topology.get("blocked_case_count") != source["expected_blocked_cases"]:
    raise SystemExit("blocked case count mismatch")
rows = topology.get("blocked_case_topology", [])
shared = [r for r in rows if r.get("topology", {}).get("classification") == "shared_influences"]
if len(shared) != source["expected_shared_influence_cases"]:
    raise SystemExit(f"expected 12 shared-influence rows, got {len(shared)}")

observations = []
roles = set()
for row in shared:
    case = str(row["case"])
    role = "left_hand" if case.startswith("left_hand_") else ("right_hand" if case.startswith("right_hand_") else "other")
    roles.add(role)
    topo = row["topology"]
    a = {str(i["bone"]): float(i["weight"]) for i in topo["vertex_a_influences"]}
    b = {str(i["bone"]): float(i["weight"]) for i in topo["vertex_b_influences"]}
    bones = sorted(set(a) | set(b))
    l1 = sum(abs(a.get(bone, 0.0) - b.get(bone, 0.0)) for bone in bones)
    dom_a = max(a, key=a.get)
    dom_b = max(b, key=b.get)
    shared_bones = sorted(set(a) & set(b))
    observations.append({
        "case": case,
        "role": role,
        "rotated_bone": topo["rotated_bone"],
        "vertex_a": row["vertex_a"],
        "vertex_b": row["vertex_b"],
        "surface": row["surface"],
        "endpoint_distribution_l1": l1,
        "dominant_bone_a": dom_a,
        "dominant_bone_b": dom_b,
        "dominant_bone_flip": dom_a != dom_b,
        "shared_bones": shared_bones,
        "shared_bone_count": len(shared_bones),
        "rotated_weight_delta": float(topo["rotated_weight_delta"]),
        "edge_change_m": float(row["edge_change_m"]),
        "stretch_ratio": float(row["stretch_ratio"]),
    })

rules = contract["diagnostic"]
expected_roles = set(rules["expected_roles"])
if rules["require_bilateral_hand_only"] and roles != expected_roles:
    raise SystemExit(f"shared-influence roles drift: {sorted(roles)}")
for role in expected_roles:
    count = sum(1 for o in observations if o["role"] == role)
    if count != rules["expected_axes_per_side"]:
        raise SystemExit(f"{role} expected 6 cases, got {count}")
if any(o["endpoint_distribution_l1"] < rules["min_endpoint_distribution_l1"] for o in observations):
    raise SystemExit("shared seam endpoint distribution divergence below locked diagnostic threshold")
if rules["require_dominant_bone_flip"] and not all(o["dominant_bone_flip"] for o in observations):
    raise SystemExit("expected dominant-bone flip in every shared-influence witness")
if rules["require_two_shared_bones"] and not all(o["shared_bone_count"] == 2 for o in observations):
    raise SystemExit("expected exactly two shared bones in every shared-influence witness")

unique_edges = sorted({(o["surface"], o["vertex_a"], o["vertex_b"]) for o in observations})
left = [o for o in observations if o["role"] == "left_hand"]
right = [o for o in observations if o["role"] == "right_hand"]
result = {
    "format": contract["format"],
    "diagnostic_state": "SHARED_INFLUENCE_SEAM_DISTRIBUTION_FLIP_CONFIRMED",
    "candidate_variant": 1,
    "shared_influence_case_count": len(observations),
    "unique_worst_edges": len(unique_edges),
    "roles": sorted(roles),
    "min_endpoint_distribution_l1": min(o["endpoint_distribution_l1"] for o in observations),
    "max_endpoint_distribution_l1": max(o["endpoint_distribution_l1"] for o in observations),
    "left_hand_distribution_l1": left[0]["endpoint_distribution_l1"],
    "right_hand_distribution_l1": right[0]["endpoint_distribution_l1"],
    "dominant_bone_flip_count": sum(o["dominant_bone_flip"] for o in observations),
    "observations": observations,
    "rails": contract["rails"],
    "next_safe_axis": "TEST_FULL_VECTOR_HAND_SEAM_BLEND_AB_ON_TWO_UNIQUE_EDGES"
}
out_path.write_text(json.dumps(result, indent=2, sort_keys=True))
print(json.dumps({k: result[k] for k in ("diagnostic_state", "shared_influence_case_count", "unique_worst_edges", "min_endpoint_distribution_l1", "max_endpoint_distribution_l1", "next_safe_axis")}, sort_keys=True))
