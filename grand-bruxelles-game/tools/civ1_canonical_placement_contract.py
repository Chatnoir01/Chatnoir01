#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

GROUND_NODE_RE = re.compile(r'\[node name="Ground" type="CSGBox3D" parent="\."\]\n(?P<body>.*?)(?=\n\[node |\Z)', re.S)
VEC3_RE = re.compile(r'Vector3\(([^,]+),\s*([^,]+),\s*([^\)]+)\)')


def parse_vec3(value: str) -> tuple[float, float, float]:
    match = VEC3_RE.search(value)
    if not match:
        raise ValueError(f"not-vector3:{value}")
    return tuple(float(match.group(i)) for i in range(1, 4))


def extract_assignment(block: str, key: str) -> str:
    match = re.search(rf'^{re.escape(key)}\s*=\s*(.+)$', block, re.M)
    if not match:
        raise ValueError(f"missing-assignment:{key}")
    return match.group(1).strip()


def main() -> int:
    if len(sys.argv) != 5:
        print("usage: civ1_canonical_placement_contract.py MAIN_TSCN NPC_AGENT NPC_DIRECTOR OUT", file=sys.stderr)
        return 2

    scene_path, agent_path, director_path, out_path = map(Path, sys.argv[1:])
    scene = scene_path.read_text(encoding="utf-8")
    agent = agent_path.read_text(encoding="utf-8")
    director = director_path.read_text(encoding="utf-8")

    ground_match = GROUND_NODE_RE.search(scene)
    if not ground_match:
        raise SystemExit("CIV1_CANONICAL_PLACEMENT_FAIL: canonical Ground node missing")
    ground_block = ground_match.group("body")
    ground_position = parse_vec3(extract_assignment(ground_block, "position"))
    ground_size = parse_vec3(extract_assignment(ground_block, "size"))
    ground_top_y = ground_position[1] + ground_size[1] * 0.5

    exact_spawn_copy = (
        "func _set_world_position(world_position: Vector3) -> void:" in agent
        and "global_position = world_position" in agent
        and "position = world_position" in agent
    )
    pooled_spawn_copy = "agent.reactivate(spawn_position)" in director

    grounding_tokens = [
        "floor_snap_length",
        "apply_floor_snap(",
        "is_on_floor(",
        "get_gravity(",
        "ProjectSettings.get_setting(\"physics/3d/default_gravity\"",
        "move_and_collide(Vector3(0",
        "intersect_ray(",
        "intersect_shape(",
    ]
    grounding_hits = [token for token in grounding_tokens if token in agent]

    main_has_agent_instance = 'script = ExtResource("14_npc_director")' in scene and 'script = ExtResource("15_npc_runtime")' in scene
    explicit_agent_node = 'type="CharacterBody3D"' in scene and 'npc_agent.gd' in scene

    canonical_available = bool(
        explicit_agent_node
        and grounding_hits
        and not exact_spawn_copy
    )

    receipt = {
        "schema": "grand-bruxelles-civ1-canonical-placement-contract-v1",
        "canonical_ground": {
            "node": "Main/Ground",
            "position_y_m": ground_position[1],
            "size_y_m": ground_size[1],
            "top_y_m": ground_top_y,
            "use_collision": "use_collision = true" in ground_block,
        },
        "runtime": {
            "population_director_loaded": 'script = ExtResource("14_npc_director")' in scene,
            "runtime_integration_loaded": 'script = ExtResource("15_npc_runtime")' in scene,
            "npc_agent_instance_authored_in_main": explicit_agent_node,
            "spawn_y_is_copied_verbatim": exact_spawn_copy,
            "pooled_spawn_y_is_copied_verbatim": pooled_spawn_copy,
            "grounding_mechanism_hits": grounding_hits,
        },
        "canonical_character_placement_available": canonical_available,
        "ground_contact_classifiable": False,
        "contact_proof_claimed": False,
        "planted_interval_claimable": False,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_change_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "required_next_evidence": "real loaded NpcAgent/CIV-1 mount transform or runtime grounding contract binding character local origin to canonical Ground",
    }

    if not main_has_agent_instance:
        raise SystemExit("CIV1_CANONICAL_PLACEMENT_FAIL: NPC runtime owner nodes missing")
    if not exact_spawn_copy:
        raise SystemExit("CIV1_CANONICAL_PLACEMENT_FAIL: spawn semantics changed; re-audit required")
    if not pooled_spawn_copy:
        raise SystemExit("CIV1_CANONICAL_PLACEMENT_FAIL: pooled spawn semantics changed; re-audit required")
    if canonical_available:
        raise SystemExit("CIV1_CANONICAL_PLACEMENT_FAIL: classifier unexpectedly promoted canonical placement")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CIV1_CANONICAL_PLACEMENT_CONTRACT_OK", json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
