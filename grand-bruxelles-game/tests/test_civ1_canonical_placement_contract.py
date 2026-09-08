from __future__ import annotations

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


def run_classifier(out: Path, witness: Path | None = None) -> subprocess.CompletedProcess[str]:
    command = [sys.executable, str(TOOL), str(MAIN), str(AGENT), str(DIRECTOR), str(out)]
    if witness is not None:
        command.append(str(witness))
    return subprocess.run(command, text=True, capture_output=True, check=False)


def test_current_runtime_is_fail_closed_without_loaded_transform_witness() -> None:
    assert TOOL.is_file(), f"missing canonical placement classifier: {TOOL}"
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "receipt.json"
        result = run_classifier(out)
        assert result.returncode == 0, result.stderr or result.stdout
        receipt = json.loads(out.read_text(encoding="utf-8"))

    assert receipt["schema"] == "grand-bruxelles-civ1-canonical-placement-contract-v2"
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
        "grand-bruxelles-civ1-runtime-placement-witness-v1",
        '"evidence_kind"',
        '"engine_version"',
        '"main_scene"',
        '"candidate"',
        '"node_paths"',
        '"world_transform"',
        '"origin_m"',
        '"basis_rows"',
        '"ground_top_y_m"',
        '"candidate_source_sha256"',
        '"provenance_record"',
        '"mcp_ephemeral"',
        '"canonical_export_modified"',
    ]
    for token in required_tokens:
        assert token in text, f"missing runtime-witness contract token: {token}"

    with tempfile.TemporaryDirectory() as tmp:
        tmp_path = Path(tmp)
        witness = tmp_path / "malformed-witness.json"
        witness.write_text(
            json.dumps({"schema": "grand-bruxelles-civ1-runtime-placement-witness-v1"}),
            encoding="utf-8",
        )
        out = tmp_path / "receipt.json"
        result = run_classifier(out, witness)
        assert result.returncode != 0
        combined = result.stdout + result.stderr
        assert "RUNTIME_WITNESS_FAIL" in combined


def test_no_old_grounding_shortcuts_are_reintroduced() -> None:
    lowered = TOOL.read_text(encoding="utf-8").lower()
    forbidden = [
        "placement_y",
        "bilateral",
        "percentile",
        "quantile",
        "contact_threshold",
        "foot_slide_threshold",
        "camera_fov",
    ]
    for token in forbidden:
        assert token not in lowered


if __name__ == "__main__":
    test_current_runtime_is_fail_closed_without_loaded_transform_witness()
    test_runtime_witness_contract_is_explicit_and_malformed_evidence_is_rejected()
    test_no_old_grounding_shortcuts_are_reintroduced()
    print("CIV1_CANONICAL_PLACEMENT_CONTRACT_REGRESSION_GREEN")
