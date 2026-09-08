#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
import re
import sys
from pathlib import Path
from typing import Any

GROUND_NODE_RE = re.compile(r'\[node name="Ground" type="CSGBox3D" parent="\."\]\n(?P<body>.*?)(?=\n\[node |\Z)', re.S)
VEC3_RE = re.compile(r'Vector3\(([^,]+),\s*([^,]+),\s*([^\)]+)\)')
SHA256_RE = re.compile(r'^sha256:[0-9a-f]{64}$')
COMMIT_SHA_RE = re.compile(r'^[0-9a-f]{40}$')
WITNESS_SCHEMA = "grand-bruxelles-civ1-runtime-placement-witness-v4"
EXPECTED_SOURCE_REPOSITORY = "https://github.com/ibrews/VitruvianGodot"
REQUIRED_SAMPLE_INDICES = [71, 72, 73]
SKELETON_ARTIFACT_ID = 9996432028
SKELETON_ARTIFACT_DIGEST = "sha256:9b4dd309157ce1f3e5aae44125f5931fac409238eece1a0632b8ad07933ebb00"
SKELETON_SAMPLE_COUNT = 120
PHASE_MINIMA_ARTIFACT_ID = 10057731450
PHASE_MINIMA_ARTIFACT_DIGEST = "sha256:78b7a990856feafda5248189848f8e10a8a33694141014bed831eb74a0ec8a5f"
PHASE_LOWEST_CANDIDATE_SAMPLE_INDEX = 72


def sha256_file(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


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


def finite_vector(value: Any, length: int) -> bool:
    return (
        isinstance(value, list)
        and len(value) == length
        and all(isinstance(v, (int, float)) and not isinstance(v, bool) and math.isfinite(float(v)) for v in value)
    )


def validate_transform(transform: Any, prefix: str, errors: list[str]) -> None:
    if not isinstance(transform, dict):
        errors.append(f"{prefix}:not-object")
        return
    origin = transform.get("origin_m")
    if not finite_vector(origin, 3):
        errors.append(f"{prefix}.origin_m:not-finite-vec3")
    basis = transform.get("basis_rows")
    if not isinstance(basis, list) or len(basis) != 3 or not all(finite_vector(row, 3) for row in basis):
        errors.append(f"{prefix}.basis_rows:not-finite-3x3")
        return
    a, b, c = [[float(v) for v in row] for row in basis]
    determinant = (
        a[0] * (b[1] * c[2] - b[2] * c[1])
        - a[1] * (b[0] * c[2] - b[2] * c[0])
        + a[2] * (b[0] * c[1] - b[1] * c[0])
    )
    if not math.isfinite(determinant) or abs(determinant) <= 1e-9:
        errors.append(f"{prefix}.basis_rows:singular:det={determinant!r}")


def validate_animation_evidence(value: Any, errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append("animation_evidence:not-object")
        return
    exact = {
        "skeleton_artifact_id": SKELETON_ARTIFACT_ID,
        "skeleton_artifact_digest": SKELETON_ARTIFACT_DIGEST,
        "skeleton_sample_count": SKELETON_SAMPLE_COUNT,
        "phase_minima_artifact_id": PHASE_MINIMA_ARTIFACT_ID,
        "phase_minima_artifact_digest": PHASE_MINIMA_ARTIFACT_DIGEST,
        "phase_lowest_candidate_sample_index": PHASE_LOWEST_CANDIDATE_SAMPLE_INDEX,
        "bound_sample_indices": REQUIRED_SAMPLE_INDICES,
    }
    for key, expected in exact.items():
        actual = value.get(key)
        if actual != expected:
            errors.append(f"animation_evidence.{key}:mismatch:{actual!r}:{expected!r}")


def validate_runtime_witness(
    witness: Any,
    ground_top_y: float,
    expected_runtime_hashes: dict[str, str],
) -> list[str]:
    errors: list[str] = []
    if not isinstance(witness, dict):
        return ["root:not-object"]

    exact_scalars = {
        "schema": WITNESS_SCHEMA,
        "evidence_kind": "godot-live-loaded-scene",
        "engine_version": "4.7.1",
        "main_scene": "res://game/main.tscn",
        "candidate": "CIV-1",
        "mcp_ephemeral": True,
        "canonical_export_modified": False,
    }
    for key, expected in exact_scalars.items():
        if witness.get(key) != expected:
            errors.append(f"{key}:expected:{expected!r}:got:{witness.get(key)!r}")

    node_paths = witness.get("node_paths")
    if not isinstance(node_paths, dict):
        errors.append("node_paths:not-object")
    else:
        for key in ("npc_agent", "character_mount", "skeleton"):
            value = node_paths.get(key)
            if not isinstance(value, str) or not value.strip():
                errors.append(f"node_paths.{key}:missing")
        if node_paths.get("ground") != "Main/Ground":
            errors.append(f"node_paths.ground:expected:'Main/Ground':got:{node_paths.get('ground')!r}")

    transforms = witness.get("world_transforms_by_sample")
    expected_keys = {str(index) for index in REQUIRED_SAMPLE_INDICES}
    if not isinstance(transforms, dict):
        errors.append("world_transforms_by_sample:not-object")
    else:
        actual_keys = set(transforms)
        if actual_keys != expected_keys:
            errors.append(f"world_transforms_by_sample.keys:mismatch:{sorted(actual_keys)!r}:{sorted(expected_keys)!r}")
        for index in REQUIRED_SAMPLE_INDICES:
            key = str(index)
            if key in transforms:
                validate_transform(transforms[key], f"world_transforms_by_sample.{key}", errors)

    witness_ground_top = witness.get("ground_top_y_m")
    if not isinstance(witness_ground_top, (int, float)) or isinstance(witness_ground_top, bool) or not math.isfinite(float(witness_ground_top)):
        errors.append("ground_top_y_m:not-finite-number")
    elif abs(float(witness_ground_top) - ground_top_y) > 1e-12:
        errors.append(f"ground_top_y_m:mismatch:{witness_ground_top!r}:{ground_top_y!r}")

    source_hash = witness.get("candidate_source_sha256")
    if not isinstance(source_hash, str) or SHA256_RE.fullmatch(source_hash) is None:
        errors.append("candidate_source_sha256:not-sha256")

    provenance_record = witness.get("provenance_record")
    if not isinstance(provenance_record, str) or not provenance_record.strip():
        errors.append("provenance_record:missing")

    source_evidence = witness.get("source_evidence")
    if not isinstance(source_evidence, dict):
        errors.append("source_evidence:not-object")
    else:
        if source_evidence.get("repository_url") != EXPECTED_SOURCE_REPOSITORY:
            errors.append(f"source_evidence.repository_url:expected:{EXPECTED_SOURCE_REPOSITORY!r}:got:{source_evidence.get('repository_url')!r}")
        source_commit = source_evidence.get("source_commit_sha")
        if not isinstance(source_commit, str) or COMMIT_SHA_RE.fullmatch(source_commit) is None:
            errors.append("source_evidence.source_commit_sha:not-40hex")
        license_id = source_evidence.get("license_id")
        if not isinstance(license_id, str) or not license_id.strip():
            errors.append("source_evidence.license_id:missing")
        artifact_id = source_evidence.get("artifact_id")
        if not isinstance(artifact_id, int) or isinstance(artifact_id, bool) or artifact_id <= 0:
            errors.append("source_evidence.artifact_id:not-positive-int")
        artifact_digest = source_evidence.get("artifact_digest")
        if not isinstance(artifact_digest, str) or SHA256_RE.fullmatch(artifact_digest) is None:
            errors.append("source_evidence.artifact_digest:not-sha256")
        source_file_hash = source_evidence.get("source_file_sha256")
        if not isinstance(source_file_hash, str) or SHA256_RE.fullmatch(source_file_hash) is None:
            errors.append("source_evidence.source_file_sha256:not-sha256")
        elif isinstance(source_hash, str) and SHA256_RE.fullmatch(source_hash) is not None and source_file_hash != source_hash:
            errors.append(f"source_evidence.source_file_sha256:mismatch:{source_file_hash}:{source_hash}")

    validate_animation_evidence(witness.get("animation_evidence"), errors)

    runtime_inputs = witness.get("runtime_inputs")
    if not isinstance(runtime_inputs, dict):
        errors.append("runtime_inputs:not-object")
    else:
        for key, expected_hash in expected_runtime_hashes.items():
            value = runtime_inputs.get(key)
            if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
                errors.append(f"runtime_inputs.{key}:not-sha256")
            elif value != expected_hash:
                errors.append(f"runtime_inputs.{key}:mismatch:{value}:{expected_hash}")

    capture = witness.get("capture")
    if not isinstance(capture, dict):
        errors.append("capture:not-object")
    else:
        if capture.get("loaded_scene_tree_observed") is not True:
            errors.append("capture.loaded_scene_tree_observed:not-true")
        if capture.get("character_mount_observed") is not True:
            errors.append("capture.character_mount_observed:not-true")
        if capture.get("canonical_ground_observed") is not True:
            errors.append("capture.canonical_ground_observed:not-true")
        sample_indices = capture.get("sample_indices")
        if sample_indices != REQUIRED_SAMPLE_INDICES:
            errors.append(f"capture.sample_indices:mismatch:{sample_indices!r}:{REQUIRED_SAMPLE_INDICES!r}")

    return errors


def main() -> int:
    if len(sys.argv) not in (5, 6):
        print("usage: civ1_canonical_placement_contract.py MAIN_TSCN NPC_AGENT NPC_DIRECTOR OUT [RUNTIME_WITNESS_JSON]", file=sys.stderr)
        return 2

    scene_path, agent_path, director_path, out_path = map(Path, sys.argv[1:5])
    witness_path = Path(sys.argv[5]) if len(sys.argv) == 6 else None
    scene = scene_path.read_text(encoding="utf-8")
    agent = agent_path.read_text(encoding="utf-8")
    director = director_path.read_text(encoding="utf-8")
    runtime_input_hashes = {
        "main_scene_sha256": sha256_file(scene_path),
        "npc_agent_sha256": sha256_file(agent_path),
        "npc_director_sha256": sha256_file(director_path),
    }

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
        "floor_snap_length", "apply_floor_snap(", "is_on_floor(", "get_gravity(",
        "ProjectSettings.get_setting(\"physics/3d/default_gravity\"", "move_and_collide(Vector3(0", "intersect_ray(", "intersect_shape(",
    ]
    grounding_hits = [token for token in grounding_tokens if token in agent]
    main_has_runtime_owner_nodes = 'script = ExtResource("14_npc_director")' in scene and 'script = ExtResource("15_npc_runtime")' in scene
    explicit_agent_node = 'type="CharacterBody3D"' in scene and 'npc_agent.gd' in scene

    witness_present = witness_path is not None
    witness_validated = False
    witness_errors: list[str] = []
    if witness_path is not None:
        try:
            witness = json.loads(witness_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as exc:
            raise SystemExit(f"CIV1_RUNTIME_WITNESS_FAIL: unreadable-json:{exc}") from exc
        witness_errors = validate_runtime_witness(witness, ground_top_y, runtime_input_hashes)
        if witness_errors:
            raise SystemExit("CIV1_RUNTIME_WITNESS_FAIL: " + ";".join(witness_errors))
        witness_validated = True

    required_animation_evidence = {
        "skeleton_artifact_id": SKELETON_ARTIFACT_ID,
        "skeleton_artifact_digest": SKELETON_ARTIFACT_DIGEST,
        "skeleton_sample_count": SKELETON_SAMPLE_COUNT,
        "phase_minima_artifact_id": PHASE_MINIMA_ARTIFACT_ID,
        "phase_minima_artifact_digest": PHASE_MINIMA_ARTIFACT_DIGEST,
        "phase_lowest_candidate_sample_index": PHASE_LOWEST_CANDIDATE_SAMPLE_INDEX,
        "bound_sample_indices": REQUIRED_SAMPLE_INDICES,
    }
    receipt = {
        "schema": "grand-bruxelles-civ1-canonical-placement-contract-v5",
        "canonical_ground": {"node": "Main/Ground", "position_y_m": ground_position[1], "size_y_m": ground_size[1], "top_y_m": ground_top_y, "use_collision": "use_collision = true" in ground_block},
        "runtime": {
            "population_director_loaded": 'script = ExtResource("14_npc_director")' in scene,
            "runtime_integration_loaded": 'script = ExtResource("15_npc_runtime")' in scene,
            "npc_agent_instance_authored_in_main": explicit_agent_node,
            "spawn_y_is_copied_verbatim": exact_spawn_copy,
            "pooled_spawn_y_is_copied_verbatim": pooled_spawn_copy,
            "grounding_mechanism_hits": grounding_hits,
            "input_sha256": runtime_input_hashes,
        },
        "runtime_witness": {
            "schema": WITNESS_SCHEMA,
            "present": witness_present,
            "validated": witness_validated,
            "validation_errors": witness_errors,
            "required_sample_indices": REQUIRED_SAMPLE_INDICES,
            "required_animation_evidence": required_animation_evidence,
            "required_fields": [
                "schema", "evidence_kind", "engine_version", "main_scene", "candidate", "node_paths.npc_agent", "node_paths.character_mount", "node_paths.skeleton", "node_paths.ground",
                "world_transforms_by_sample.71.origin_m", "world_transforms_by_sample.71.basis_rows", "world_transforms_by_sample.72.origin_m", "world_transforms_by_sample.72.basis_rows", "world_transforms_by_sample.73.origin_m", "world_transforms_by_sample.73.basis_rows",
                "ground_top_y_m", "candidate_source_sha256", "provenance_record", "source_evidence.repository_url", "source_evidence.source_commit_sha", "source_evidence.license_id", "source_evidence.artifact_id", "source_evidence.artifact_digest", "source_evidence.source_file_sha256",
                "animation_evidence.skeleton_artifact_id", "animation_evidence.skeleton_artifact_digest", "animation_evidence.skeleton_sample_count", "animation_evidence.phase_minima_artifact_id", "animation_evidence.phase_minima_artifact_digest", "animation_evidence.phase_lowest_candidate_sample_index", "animation_evidence.bound_sample_indices",
                "runtime_inputs.main_scene_sha256", "runtime_inputs.npc_agent_sha256", "runtime_inputs.npc_director_sha256", "mcp_ephemeral", "canonical_export_modified", "capture.loaded_scene_tree_observed", "capture.character_mount_observed", "capture.canonical_ground_observed", "capture.sample_indices",
            ],
        },
        "canonical_character_placement_available": witness_validated,
        "ground_contact_classifiable": False,
        "contact_proof_claimed": False,
        "planted_interval_claimable": False,
        "quantitative_foot_slide_candidate": False,
        "animation_correction_authorized": False,
        "runtime_change_authorized": False,
        "visual_approval_claimed": False,
        "player_view_claimed": False,
        "required_next_evidence": "capture a Godot 4.7.1 live-loaded CIV-1 mount witness whose 71/72/73 transforms are bound to the immutable 120-sample Skeleton and geometry-phase artifacts; only then replay those exact skinned samples against canonical Ground",
    }

    if not main_has_runtime_owner_nodes:
        raise SystemExit("CIV1_CANONICAL_PLACEMENT_FAIL: NPC runtime owner nodes missing")
    if not exact_spawn_copy:
        raise SystemExit("CIV1_CANONICAL_PLACEMENT_FAIL: spawn semantics changed; re-audit required")
    if not pooled_spawn_copy:
        raise SystemExit("CIV1_CANONICAL_PLACEMENT_FAIL: pooled spawn semantics changed; re-audit required")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("CIV1_CANONICAL_PLACEMENT_CONTRACT_OK", json.dumps(receipt, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())