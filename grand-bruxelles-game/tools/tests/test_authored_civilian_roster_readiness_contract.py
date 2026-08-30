import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONTRACT_PATH = ROOT / "data" / "qa" / "authored_civilian_roster_readiness_contract.json"
STATUS_PATH = ROOT / "assets" / "characters" / "civilians" / "civ1" / "source_status.json"
VISUAL_PATH = ROOT / "game" / "scripts" / "humanoid_visual.gd"


def test_authored_civilian_roster_readiness_is_fail_closed() -> None:
    contract = json.loads(CONTRACT_PATH.read_text(encoding="utf-8"))
    status = json.loads(STATUS_PATH.read_text(encoding="utf-8"))
    visual = VISUAL_PATH.read_text(encoding="utf-8")

    assert contract["format"] == "grand-bruxelles-authored-civilian-roster-readiness-v3"
    assert contract["base_main_sha"] == "97b299786daedf8b8b4c19c5b4e404b2c088f160"
    assert contract["candidate_id"] == status["candidate_id"] == "CIV-1"
    assert contract["owner_verdict"] == status["owner_verdict"] == "GARDER"

    expected_state = contract["required_current_state"]
    for key, expected in expected_state.items():
        assert status[key] == expected, f"CIV-1 state changed at {key}; re-run packaging/provenance review"

    assert status["character_source"] == contract["required_character_source"]
    assert status["footwear_source"] == contract["required_footwear_source"]

    # Provenance must identify exact blobs and explicit per-blob license scope.
    # A repository-level CC0 assumption is not enough to authorize materialization.
    assert status["source_manifest"] == contract["required_source_manifest"]
    assert status["source_paths"] == list(contract["required_source_manifest"].keys())
    unresolved = []
    for rel_path, entry in contract["required_source_manifest"].items():
        assert len(entry["git_blob_sha1"]) == 40
        assert entry["upstream_path"]
        assert isinstance(entry["license_scope_verified"], bool)
        if entry["license_scope_verified"]:
            assert entry.get("license") in {"CC0-1.0", "CC-BY-4.0", "MIT"}
        else:
            unresolved.append(entry["upstream_path"])
        if entry["size_bytes"] is not None:
            assert entry["size_bytes"] > 0
        assert rel_path.startswith("assets/characters/civilians/civ1/source/")

    license_evidence = contract["required_character_source"]["license_evidence"]
    assert contract["required_character_source"]["license_claim"] == "MIXED"
    assert license_evidence["license_path"] == "LICENSE"
    assert license_evidence["notice_path"] == "NOTICE.md"
    assert "godot_project/vitruvian_head.glb" in license_evidence["explicit_cc0_assets"]
    assert sorted(unresolved) == sorted(license_evidence["unresolved_assets"])
    assert unresolved, "CIV-1 may not silently become materializable without explicit license review"
    assert contract["authorizations"]["source_materialization"] is False

    forbidden = set(contract["forbidden_civilian_runtime_sources"])
    assert forbidden.issubset(set(status["forbidden_runtime_paths"]))

    # Main's authored loader is deliberately player-only today. NpcAgent still
    # routes into the procedural profiled mesh path. If either fact changes,
    # this gate fails until authored roster provenance + visual evidence is updated.
    assert 'actor.name == "Player" and _try_build_authored_character()' in visual
    assert 'if actor is NpcAgent:' in visual
    assert '_build_profiled_npc(actor as NpcAgent)' in visual
    assert 'set_meta("custom_mesh_pipeline", "array_mesh_profiled_v2")' in visual

    # No source/runtime payload may appear while license scope/readiness is blocked.
    for rel_path in status["source_paths"]:
        assert not (ROOT / rel_path).exists(), f"source payload appeared without readiness promotion: {rel_path}"
    for rel_path in status["runtime_files"]:
        assert not (ROOT / rel_path).exists(), f"runtime payload appeared without readiness promotion: {rel_path}"
    assert status["runtime_sha256"] == {}

    assert contract["verdict"] == "BLOCK_RUNTIME_PROMOTION_UNTIL_LICENSE_SCOPE_AND_AUTHORED_CIVILIAN_PACKAGE_READY"
    assert all(value is False for value in contract["authorizations"].values())


if __name__ == "__main__":
    test_authored_civilian_roster_readiness_is_fail_closed()
    print("AUTHORED_CIVILIAN_ROSTER_READINESS_GREEN")
