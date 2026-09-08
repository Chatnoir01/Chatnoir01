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


def run_classifier(out: Path, witness: Path | None = None) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(TOOL), str(MAIN), str(AGENT), str(DIRECTOR), str(out)]
    if witness is not None:
        command.append(str(witness))
    return subprocess.run(command, text=True, capture_output=True, check=False)


def sha256_file(path: Path) -> str:
    return "sha256:" + hashlib.sha256(path.read_bytes()).hexdigest()


def identity_transform(origin_x: float) -> dict[str, object]:
    return {
        "origin_m": [origin_x, 0.0, 0.0],
        "basis_rows": [[1.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.0, 0.0, 1.0]],
    }


def valid_runtime_witness() -> dict[str, object]:
    source_hash = "sha256:" + "1" * 64
    return {
        "schema": "grand-bruxelles-civ1-runtime-placement-witness-v3",
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
        "world_transforms_by_sample": {
            "71": identity_transform(0.00),
            "72": identity_transform(0.02),
            "73": identity_transform(0.04),
        },
        "ground_top_y_m": -0.03,
        "candidate_source_sha256": source_hash,
        "provenance_record": "CIV-1 immutable source receipt",
        "source_evidence": {
            "repository_url": "https://github.com/ibrews/VitruvianGodot",
            "source_commit_sha": "bdecdcd000000000000000000000000000000000",
            "license_id": "CC0-1.0",
            "artifact_id": 10024557192,
            "artifact_digest": "sha256:" + "2" * 64,
            "source_file_sha256": source_hash,
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


def test_current_runtime_is_fail_closed_without_loaded_transform_witness() -> None:
    assert TOOL.is_file(), f"missing canonical placement classifier: {TOOL}"
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "receipt.json"
        result = run_classifier(out)
        assert result.returncode == 0, result.stderr or result.stdout
        receipt = json.loads(out.read_text(encoding="utf-8"))

    assert receipt["schema"] == "grand-bruxelles-civ1-canonical-placement-contract-v4"
    assert abs(receipt["canonical_ground"]["top_y_m"] - (-0.03)) <= 1e-12
    assert receipt["canonical_ground"]["use_collision"] is True
    assert receipt["runtime"]["population_director_loaded"] is True
    assert receipt["runtime"]["runtime_integration_loaded"] is True
    assert receipt["runtime"]["npc_agent_instance_authored_in_main"] is False
    assert receipt["runtime"]["spawn_y_is_copied_verbatim"] is True
    assert receipt["runtime"]["pooled_spawn_y_is_copied_verbatim"] is True
    assert receipt["runtime"]["grounding_mechanism_hits"] == []
    assert receipt["runtime_witness"]["present"] is False
    assert receipt["runtime_witness"]["validated"] is False
    assert receipt["runtime_witness"]["required_sample_indices"] == REQUIRED_SAMPLES
    assert receipt["canonical_character_placement_available"] is False
    assert receipt["ground_contact_classifiable"] is False
    assert receipt["contact_proof_claimed"] is False
    assert receipt["planted_interval_claimable"] is False
    assert receipt["quantitative_foot_slide_candidate"] is False
    assert receipt["animation_correction_authorized"] is False
    assert receipt["runtime_change_authorized"] is False
    assert receipt["visual_approval_claimed"] is False
    assert receipt["player_view_claimed"] is False


def test_runtime_witness_contract_is_explicit_and_malformed_evidence_is_rejected() -> None:
    text = TOOL.read_text(encoding="utf-8")
    required_tokens = [
        "grand-bruxelles-civ1-runtime-placement-witness-v3",
        '"evidence_kind"',
        '"engine_version"',
        '"main_scene"',
        '"candidate"',
        '"node_paths"',
        '"world_transforms_by_sample"',
        '"origin_m"',
        '"basis_rows"',
        '"ground_top_y_m"',
        '"candidate_source_sha256"',
        '"provenance_record"',
        '"source_evidence"',
        '"repository_url"',
        '"source_commit_sha"',
        '"license_id"',
        '"artifact_id"',
        '"artifact_digest"',
        '"source_file_sha256"',
        '"runtime_inputs"',
        '"main_scene_sha256"',
        '"npc_agent_sha256"',
        '"npc_director_sha256"',
        '"mcp_ephemeral"',
        '"canonical_export_modified"',
        '"sample_indices"',
    ]
    for token in required_tokens:
        assert token in text, f"missing runtime-witness contract token: {token}"

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        witness = tmp_path / "malformed-witness.json"
        witness.write_text(json.dumps({"schema": "grand-bruxelles-civ1-runtime-placement-witness-v3"}), encoding="utf-8")
        out = tmp_path / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode != 0
        assert "RUNTIME_WITNESS_FAIL" in result.stdout + result.stderr


def test_single_transform_witness_is_rejected_to_prevent_temporal_mismatch() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        witness_data = valid_runtime_witness()
        witness_data.pop("world_transforms_by_sample")
        witness_data["world_transform"] = identity_transform(0.02)
        witness = tmp_path / "single-transform-witness.json"
        witness.write_text(json.dumps(witness_data), encoding="utf-8")
        out = tmp_path / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode != 0
        combined = result.stdout + result.stderr
        assert "RUNTIME_WITNESS_FAIL" in combined
        assert "world_transforms_by_sample:not-object" in combined


def test_missing_or_extra_same_sample_transform_is_rejected_causally() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        witness_data = valid_runtime_witness()
        transforms = witness_data["world_transforms_by_sample"]
        assert isinstance(transforms, dict)
        transforms.pop("71")
        transforms["74"] = identity_transform(0.06)
        witness = tmp_path / "wrong-samples-witness.json"
        witness.write_text(json.dumps(witness_data), encoding="utf-8")
        out = tmp_path / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode != 0
        combined = result.stdout + result.stderr
        assert "world_transforms_by_sample.keys:mismatch" in combined


def test_capture_sample_indices_must_match_transform_samples_exactly() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        witness_data = valid_runtime_witness()
        capture = witness_data["capture"]
        assert isinstance(capture, dict)
        capture["sample_indices"] = [72]
        witness = tmp_path / "wrong-capture-samples.json"
        witness.write_text(json.dumps(witness_data), encoding="utf-8")
        out = tmp_path / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode != 0
        combined = result.stdout + result.stderr
        assert "capture.sample_indices:mismatch" in combined


def test_structurally_valid_but_stale_runtime_inputs_are_rejected_causally() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        witness_data = valid_runtime_witness()
        runtime_inputs = witness_data["runtime_inputs"]
        assert isinstance(runtime_inputs, dict)
        runtime_inputs["main_scene_sha256"] = "sha256:" + "0" * 64
        witness = tmp_path / "stale-witness.json"
        witness.write_text(json.dumps(witness_data), encoding="utf-8")
        out = tmp_path / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode != 0
        combined = result.stdout + result.stderr
        assert "RUNTIME_WITNESS_FAIL" in combined
        assert "runtime_inputs.main_scene_sha256:mismatch" in combined


def test_candidate_source_hash_must_match_immutable_source_evidence() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        witness_data = valid_runtime_witness()
        source_evidence = witness_data["source_evidence"]
        assert isinstance(source_evidence, dict)
        source_evidence["source_file_sha256"] = "sha256:" + "9" * 64
        witness = tmp_path / "source-mismatch-witness.json"
        witness.write_text(json.dumps(witness_data), encoding="utf-8")
        out = tmp_path / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode != 0
        combined = result.stdout + result.stderr
        assert "RUNTIME_WITNESS_FAIL" in combined
        assert "source_evidence.source_file_sha256:mismatch" in combined


def test_source_evidence_requires_repository_commit_license_and_artifact_receipt() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        witness_data = valid_runtime_witness()
        source_evidence = witness_data["source_evidence"]
        assert isinstance(source_evidence, dict)
        source_evidence["repository_url"] = "https://example.invalid/other-source"
        source_evidence["license_id"] = ""
        source_evidence["artifact_id"] = 0
        source_evidence["artifact_digest"] = "not-a-digest"
        witness = tmp_path / "bad-provenance-witness.json"
        witness.write_text(json.dumps(witness_data), encoding="utf-8")
        out = tmp_path / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode != 0
        combined = result.stdout + result.stderr
        assert "source_evidence.repository_url:expected" in combined
        assert "source_evidence.license_id:missing" in combined
        assert "source_evidence.artifact_id:not-positive-int" in combined
        assert "source_evidence.artifact_digest:not-sha256" in combined


def test_exact_runtime_source_and_same_sample_evidence_allow_only_placement_not_contact() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        witness = tmp_path / "fresh-witness.json"
        witness.write_text(json.dumps(valid_runtime_witness()), encoding="utf-8")
        out = tmp_path / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode == 0, result.stderr or result.stdout
        receipt = json.loads(out.read_text(encoding="utf-8"))
        assert receipt["runtime_witness"]["validated"] is True
        assert receipt["runtime_witness"]["required_sample_indices"] == REQUIRED_SAMPLES
        assert receipt["canonical_character_placement_available"] is True
        assert receipt["ground_contact_classifiable"] is False
        assert receipt["contact_proof_claimed"] is False
        assert receipt["planted_interval_claimable"] is False
        assert receipt["quantitative_foot_slide_candidate"] is False


def test_no_old_grounding_shortcuts_are_reintroduced() -> None:
    lowered = TOOL.read_text(encoding="utf-8").lower()
    forbidden = ["placement_y", "bilateral", "percentile", "quantile", "contact_threshold", "foot_slide_threshold", "camera_fov"]
    for token in forbidden:
        assert token not in lowered


if __name__ == "__main__":
    test_current_runtime_is_fail_closed_without_loaded_transform_witness()
    test_runtime_witness_contract_is_explicit_and_malformed_evidence_is_rejected()
    test_single_transform_witness_is_rejected_to_prevent_temporal_mismatch()
    test_missing_or_extra_same_sample_transform_is_rejected_causally()
    test_capture_sample_indices_must_match_transform_samples_exactly()
    test_structurally_valid_but_stale_runtime_inputs_are_rejected_causally()
    test_candidate_source_hash_must_match_immutable_source_evidence()
    test_source_evidence_requires_repository_commit_license_and_artifact_receipt()
    test_exact_runtime_source_and_same_sample_evidence_allow_only_placement_not_contact()
    test_no_old_grounding_shortcuts_are_reintroduced()
    print("CIV1_CANONICAL_PLACEMENT_CONTRACT_REGRESSION_GREEN")