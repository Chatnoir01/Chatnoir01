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

    assert contract["format"] == "grand-bruxelles-authored-civilian-roster-readiness-v2"
    assert contract["base_main_sha"] == "bdc538a4065d846f2c01a733e2b9c514cadb3829"
    assert contract["candidate_id"] == status["candidate_id"] == "CIV-1"
    assert contract["owner_verdict"] == status["owner_verdict"] == "GARDER"

    expected_state = contract["required_current_state"]
    for key, expected in expected_state.items():
        assert status[key] == expected, f"CIV-1 state changed at {key}; re-run packaging/provenance review"

    assert status["character_source"] == contract["required_character_source"]
    assert status["footwear_source"] == contract["required_footwear_source"]

    # Provenance must identify the exact upstream blobs that are allowed to be
    # materialized later. Repo/commit/license alone are not sufficient.
    assert status["source_manifest"] == contract["required_source_manifest"]
    assert status["source_paths"] == list(contract["required_source_manifest"].keys())
    for rel_path, entry in contract["required_source_manifest"].items():
        assert len(entry["git_blob_sha1"]) == 40
        assert entry["upstream_path"]
        if entry["size_bytes"] is not None:
            assert entry["size_bytes"] > 0
        assert rel_path.startswith("assets/characters/civilians/civ1/source/")

    forbidden = set(contract["forbidden_civilian_runtime_sources"])
    assert forbidden.issubset(set(status["forbidden_runtime_paths"]))

    # Main's authored loader is deliberately player-only today. NpcAgent still
    # routes into the procedural profiled mesh path. If either fact changes,
    # this gate fails until authored roster provenance + visual evidence is updated.
    assert 'actor.name == "Player" and _try_build_authored_character()' in visual
    assert 'if actor is NpcAgent:' in visual
    assert '_build_profiled_npc(actor as NpcAgent)' in visual
    assert 'set_meta("custom_mesh_pipeline", "array_mesh_profiled_v2")' in visual

    # No source/runtime payload may be silently inferred from provenance records.
    for rel_path in status["source_paths"]:
        assert not (ROOT / rel_path).exists(), f"source payload appeared without readiness promotion: {rel_path}"
    for rel_path in status["runtime_files"]:
        assert not (ROOT / rel_path).exists(), f"runtime payload appeared without readiness promotion: {rel_path}"
    assert status["runtime_sha256"] == {}

    assert contract["verdict"] == "BLOCK_RUNTIME_PROMOTION_UNTIL_AUTHORED_CIVILIAN_PACKAGE_READY"
    assert all(value is False for value in contract["authorizations"].values())


if __name__ == "__main__":
    test_authored_civilian_roster_readiness_is_fail_closed()
    print("AUTHORED_CIVILIAN_ROSTER_READINESS_GREEN")
