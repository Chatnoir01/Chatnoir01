from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "civ1_canonical_placement_contract.py"
MAIN = ROOT / "game" / "main.tscn"
AGENT = ROOT / "game" / "scripts" / "npc_agent.gd"
DIRECTOR = ROOT / "game" / "scripts" / "npc_population_director.gd"
REQUIRED_SAMPLES = [71, 72, 73]
TRANSFORM_ROLES = ["npc_agent", "character_mount", "skeleton"]
SKELETON_ARTIFACT_ID = 9996432028
SKELETON_DIGEST = "sha256:9b4dd309157ce1f3e5aae44125f5931fac409238eece1a0632b8ad07933ebb00"
PHASE_ARTIFACT_ID = 10057731450
PHASE_DIGEST = "sha256:78b7a990856feafda5248189848f8e10a8a33694141014bed831eb74a0ec8a5f"
SOURCE_COMMIT = "bdecdcd537b4031fdd0fb299b7e4f93f084fffa0"
SOURCE_GIT_BLOB = "09bcade1092e5a89b474e91e6013209d4c68c127"
SOURCE_SIZE_BYTES = 6879364
SOURCE_SHA256 = "sha256:8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888"


def run_classifier(out: Path, witness: Path | None = None) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(TOOL), str(MAIN), str(AGENT), str(DIRECTOR), str(out)]
    if witness is not None:
        command.append(str(witness))
    return subprocess.run(command, text=True, capture_output=True, check=False)


def sha256_file(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def identity_transform(origin_x: float, origin_y: float = 0.0) -> dict[str, object]:
    return {"origin_m": [origin_x, origin_y, 0.0], "basis_rows": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]]}


def role_transforms(origin_x: float) -> dict[str, object]:
    return {
        "npc_agent": identity_transform(origin_x, 0.0),
        "character_mount": identity_transform(origin_x, 0.01),
        "skeleton": identity_transform(origin_x, 0.02),
    }


def valid_runtime_witness() -> dict[str, object]:
    source_hash = SOURCE_SHA256
    return {
        "schema": "grand-bruxelles-civ1-runtime-placement-witness-v7",
        "evidence_kind": "godot-live-loaded-scene",
        "engine_version": "4.7.1",
        "main_scene": "res://game/main.tscn",
        "candidate": "CIV-1",
        "mcp_ephemeral": True,
        "canonical_export_modified": False,
        "node_paths": {
            "npc_agent": "Main/NpcPopulationDirector/NpcAgent_0",
            "character_mount": "Main/NpcPopulationDirector/NpcAgent_0/CharacterMount",
            "skeleton": "Main/NpcPopulationDirector/NpcAgent_0/CharacterMount/Skeleton3D",
            "ground": "Main/Ground",
        },
        "node_classes": {
            "npc_agent": "CharacterBody3D",
            "character_mount": "Node3D",
            "skeleton": "Skeleton3D",
            "ground": "CSGBox3D",
        },
        "node_world_transforms_by_sample": {
            "71": role_transforms(0.00),
            "72": role_transforms(0.02),
            "73": role_transforms(0.04),
        },
        "ground_top_y_m": -0.03,
        "candidate_source_sha256": source_hash,
        "provenance_record": "CIV-1 immutable source receipt",
        "source_evidence": {
            "repository_url": "https://github.com/ibrews/VitruvianGodot",
            "source_commit_sha": SOURCE_COMMIT,
            "source_git_blob_sha1": SOURCE_GIT_BLOB,
            "source_size_bytes": SOURCE_SIZE_BYTES,
            "license_id": "CC0-1.0",
            "artifact_id": 10024557192,
            "artifact_digest": "sha256:" + "2" * 64,
            "source_file_sha256": source_hash,
        },
        "animation_evidence": {
            "skeleton_artifact_id": SKELETON_ARTIFACT_ID,
            "skeleton_artifact_digest": SKELETON_DIGEST,
            "skeleton_sample_count": 120,
            "phase_minima_artifact_id": PHASE_ARTIFACT_ID,
            "phase_minima_artifact_digest": PHASE_DIGEST,
            "phase_lowest_candidate_sample_index": 72,
            "bound_sample_indices": REQUIRED_SAMPLES,
        },
        "runtime_inputs": {
            "main_scene_sha256": sha256_file(MAIN),
            "npc_agent_sha256": sha256_file(AGENT),
            "npc_director_sha256": sha256_file(DIRECTOR),
        },
        "capture": {
            "loaded_scene_tree_observed": True,
            "character_mount_observed": True,
            "canonical_ground_observed": True,
            "sample_indices": REQUIRED_SAMPLES,
        },
    }


def classify_witness(data: dict[str, object]) -> subprocess.CompletedProcess[str]:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        witness = root / "witness.json"
        witness.write_text(json.dumps(data), encoding="utf-8")
        return run_classifier(root / "receipt.json", witness)


def test_current_runtime_is_fail_closed_without_loaded_transform_witness() -> None:
    assert TOOL.is_file(), f"missing canonical placement classifier: {TOOL}"
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "receipt.json"
        result = run_classifier(out)
        assert result.returncode == 0, result.stderr or result.stdout
        receipt = json.loads(out.read_text(encoding="utf-8"))
    assert receipt["schema"] == "grand-bruxelles-civ1-canonical-placement-contract-v8"
    assert abs(receipt["canonical_ground"]["top_y_m"] - (-0.03)) <= 1e-12
    assert receipt["runtime_witness"]["schema"] == "grand-bruxelles-civ1-runtime-placement-witness-v7"
    assert receipt["runtime_witness"]["required_sample_indices"] == REQUIRED_SAMPLES
    assert receipt["runtime_witness"]["required_transform_roles"] == TRANSFORM_ROLES
    assert receipt["runtime_witness"]["required_animation_evidence"]["skeleton_artifact_id"] == SKELETON_ARTIFACT_ID
    assert receipt["runtime_witness"]["required_animation_evidence"]["phase_minima_artifact_id"] == PHASE_ARTIFACT_ID
    assert receipt["runtime_witness"]["required_source_evidence"]["source_commit_sha"] == SOURCE_COMMIT
    assert receipt["runtime_witness"]["required_source_evidence"]["source_git_blob_sha1"] == SOURCE_GIT_BLOB
    assert receipt["runtime_witness"]["required_source_evidence"]["source_size_bytes"] == SOURCE_SIZE_BYTES
    assert receipt["runtime_witness"]["required_source_evidence"]["source_file_sha256"] == SOURCE_SHA256
    assert receipt["canonical_character_placement_available"] is False
    assert receipt["ground_contact_classifiable"] is False
    assert receipt["contact_proof_claimed"] is False
    assert receipt["quantitative_foot_slide_candidate"] is False
    assert receipt["visual_approval_claimed"] is False


def test_wrong_animation_lineage_is_rejected_causally() -> None:
    witness = valid_runtime_witness()
    animation = witness["animation_evidence"]
    assert isinstance(animation, dict)
    animation["skeleton_artifact_digest"] = "sha256:" + "0" * 64
    result = classify_witness(witness)
    combined = result.stdout + result.stderr
    assert result.returncode != 0
    assert "animation_evidence.skeleton_artifact_digest:mismatch" in combined


def test_wrong_animation_sample_count_is_rejected_causally() -> None:
    witness = valid_runtime_witness()
    animation = witness["animation_evidence"]
    assert isinstance(animation, dict)
    animation["skeleton_sample_count"] = 119
    result = classify_witness(witness)
    assert result.returncode != 0
    assert "animation_evidence.skeleton_sample_count:mismatch" in result.stdout + result.stderr


def test_phase_evidence_must_bind_exact_samples_and_lowest_candidate() -> None:
    witness = valid_runtime_witness()
    animation = witness["animation_evidence"]
    assert isinstance(animation, dict)
    animation["bound_sample_indices"] = [70, 71, 72]
    animation["phase_lowest_candidate_sample_index"] = 71
    result = classify_witness(witness)
    combined = result.stdout + result.stderr
    assert result.returncode != 0
    assert "animation_evidence.bound_sample_indices:mismatch" in combined
    assert "animation_evidence.phase_lowest_candidate_sample_index:mismatch" in combined


def test_legacy_root_only_sample_transforms_are_rejected() -> None:
    witness = valid_runtime_witness()
    witness.pop("node_world_transforms_by_sample")
    witness["world_transforms_by_sample"] = {"71": identity_transform(0.00), "72": identity_transform(0.02), "73": identity_transform(0.04)}
    result = classify_witness(witness)
    combined = result.stdout + result.stderr
    assert result.returncode != 0
    assert "node_world_transforms_by_sample:not-object" in combined
    assert "world_transforms_by_sample:legacy-root-only-field-forbidden" in combined


def test_each_sample_requires_all_observed_transform_roles() -> None:
    witness = valid_runtime_witness()
    transforms = witness["node_world_transforms_by_sample"]
    assert isinstance(transforms, dict)
    sample = transforms["72"]
    assert isinstance(sample, dict)
    sample.pop("skeleton")
    result = classify_witness(witness)
    combined = result.stdout + result.stderr
    assert result.returncode != 0
    assert "node_world_transforms_by_sample.72.keys:mismatch" in combined


def test_stale_runtime_inputs_are_rejected() -> None:
    witness = valid_runtime_witness()
    runtime = witness["runtime_inputs"]
    assert isinstance(runtime, dict)
    runtime["main_scene_sha256"] = "sha256:" + "0" * 64
    result = classify_witness(witness)
    assert result.returncode != 0
    assert "runtime_inputs.main_scene_sha256:mismatch" in result.stdout + result.stderr


def test_source_hash_must_match_source_evidence() -> None:
    witness = valid_runtime_witness()
    source = witness["source_evidence"]
    assert isinstance(source, dict)
    source["source_file_sha256"] = "sha256:" + "9" * 64
    result = classify_witness(witness)
    assert result.returncode != 0
    assert "source_evidence.source_file_sha256:mismatch" in result.stdout + result.stderr


def test_self_consistent_forged_source_hash_is_rejected() -> None:
    witness = valid_runtime_witness()
    forged = "sha256:" + "9" * 64
    witness["candidate_source_sha256"] = forged
    source = witness["source_evidence"]
    assert isinstance(source, dict)
    source["source_file_sha256"] = forged
    result = classify_witness(witness)
    combined = result.stdout + result.stderr
    assert result.returncode != 0
    assert "candidate_source_sha256:mismatch" in combined
    assert "source_evidence.source_file_sha256:mismatch" in combined


def test_source_commit_blob_size_and_license_are_pinned() -> None:
    mutations = [
        ("source_commit_sha", "0" * 40, "source_evidence.source_commit_sha:mismatch"),
        ("source_git_blob_sha1", "f" * 40, "source_evidence.source_git_blob_sha1:mismatch"),
        ("source_size_bytes", SOURCE_SIZE_BYTES - 1, "source_evidence.source_size_bytes:mismatch"),
        ("license_id", "MIT", "source_evidence.license_id:mismatch"),
    ]
    for key, bad_value, expected_error in mutations:
        witness = valid_runtime_witness()
        source = witness["source_evidence"]
        assert isinstance(source, dict)
        source[key] = bad_value
        result = classify_witness(witness)
        assert result.returncode != 0, (key, result.stdout + result.stderr)
        assert expected_error in result.stdout + result.stderr


def test_node_paths_must_prove_one_observed_hierarchy() -> None:
    cases = [
        ("npc_agent", "Main/NpcPopulationDirector/../ForgedAgent", "node_paths.npc_agent:not-canonical"),
        ("character_mount", "Main/Unrelated/CharacterMount", "node_paths.character_mount:not-descendant-of-npc-agent"),
        ("skeleton", "Main/Other/Skeleton3D", "node_paths.skeleton:not-descendant-of-character-mount"),
    ]
    for key, bad_path, expected_error in cases:
        witness = valid_runtime_witness()
        paths = witness["node_paths"]
        assert isinstance(paths, dict)
        paths[key] = bad_path
        result = classify_witness(witness)
        combined = result.stdout + result.stderr
        assert result.returncode != 0, (key, combined)
        assert expected_error in combined, (key, combined)


def test_node_classes_must_match_observed_runtime_roles() -> None:
    cases = [
        ("npc_agent", "Node3D", "node_classes.npc_agent:mismatch"),
        ("character_mount", "CharacterBody3D", "node_classes.character_mount:mismatch"),
        ("skeleton", "Node3D", "node_classes.skeleton:mismatch"),
        ("ground", "MeshInstance3D", "node_classes.ground:mismatch"),
    ]
    for key, forged_class, expected_error in cases:
        witness = valid_runtime_witness()
        classes = witness["node_classes"]
        assert isinstance(classes, dict)
        classes[key] = forged_class
        result = classify_witness(witness)
        combined = result.stdout + result.stderr
        assert result.returncode != 0, (key, combined)
        assert expected_error in combined, (key, combined)


def test_fully_bound_witness_unlocks_placement_only() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        witness = root / "witness.json"
        witness.write_text(json.dumps(valid_runtime_witness()), encoding="utf-8")
        out = root / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode == 0, result.stderr or result.stdout
        receipt = json.loads(out.read_text(encoding="utf-8"))
    assert receipt["runtime_witness"]["validated"] is True
    assert receipt["canonical_character_placement_available"] is True
    assert receipt["ground_contact_classifiable"] is False
    assert receipt["contact_proof_claimed"] is False
    assert receipt["planted_interval_claimable"] is False
    assert receipt["quantitative_foot_slide_candidate"] is False
    assert receipt["animation_correction_authorized"] is False
    assert receipt["runtime_change_authorized"] is False


def test_no_old_grounding_shortcuts_are_reintroduced() -> None:
    lowered = TOOL.read_text(encoding="utf-8").lower()
    for token in ["placement_y", "bilateral", "percentile", "quantile", "contact_threshold", "foot_slide_threshold", "camera_fov"]:
        assert token not in lowered


if __name__ == "__main__":
    test_current_runtime_is_fail_closed_without_loaded_transform_witness()
    test_wrong_animation_lineage_is_rejected_causally()
    test_wrong_animation_sample_count_is_rejected_causally()
    test_phase_evidence_must_bind_exact_samples_and_lowest_candidate()
    test_legacy_root_only_sample_transforms_are_rejected()
    test_each_sample_requires_all_observed_transform_roles()
    test_stale_runtime_inputs_are_rejected()
    test_source_hash_must_match_source_evidence()
    test_self_consistent_forged_source_hash_is_rejected()
    test_source_commit_blob_size_and_license_are_pinned()
    test_node_paths_must_prove_one_observed_hierarchy()
    test_node_classes_must_match_observed_runtime_roles()
    test_fully_bound_witness_unlocks_placement_only()
    test_no_old_grounding_shortcuts_are_reintroduced()
    print("CIV1_CANONICAL_PLACEMENT_CONTRACT_REGRESSION_GREEN")
