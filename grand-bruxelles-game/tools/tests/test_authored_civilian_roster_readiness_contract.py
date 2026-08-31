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

    assert contract["format"] == "grand-bruxelles-authored-civilian-roster-readiness-v5"
    assert contract["base_main_sha"] == "9e74591cd164cd381607b256b9feda105ccd1328"
    assert contract["candidate_id"] == status["candidate_id"] == "CIV-1"
    assert contract["owner_verdict"] == status["owner_verdict"] == "GARDER"

    for key, expected in contract["required_current_state"].items():
        assert status[key] == expected, f"CIV-1 state changed at {key}; re-run packaging/provenance review"

    assert status["character_source"] == contract["required_character_source"]
    assert status["footwear_source"] == contract["required_footwear_source"]
    assert status["source_manifest"] == contract["required_source_manifest"]
    assert status["source_paths"] == list(contract["required_source_manifest"].keys())
    assert status["excluded_upstream_intermediates"] == contract["required_excluded_upstream_intermediates"]

    sanitization = status.get("sanitization_contract", {})
    required_sanitization = contract["required_sanitization_contract"]
    for key, expected in required_sanitization.items():
        assert sanitization.get(key) == expected, f"CIV-1 sanitization contract drift: {key}"
    assert sanitization["materialization_allowed_after_strip"] is False
    assert (ROOT / sanitization["tool"]).is_file()

    sanitized_evidence = status.get("sanitized_body_evidence", {})
    assert sanitized_evidence == contract["required_sanitized_body_evidence"]
    body_manifest = status["source_manifest"]["assets/characters/civilians/civ1/source/vitruvian_body.glb"]
    assert sanitized_evidence["source_git_blob_sha1"] == body_manifest["git_blob_sha1"]
    assert sanitized_evidence["source_size_bytes"] == body_manifest["size_bytes"]
    assert sanitized_evidence["animations_removed"] == 6
    assert sanitized_evidence["sanitized_sha256"] == "8601f55e7c54b104b5c67de27faa1415e060e16c6b22a32b1cc24e525fa88888"
    assert sanitized_evidence["sanitized_size_bytes"] == 6780124
    assert sanitized_evidence["inventory_format"] == "grand-bruxelles-sanitized-glb-inventory-v2"
    assert sanitized_evidence["reference_integrity"] == "validated"
    assert sanitized_evidence["counts"] == {"meshes": 3, "skins": 1, "materials": 4}
    assert sanitized_evidence["binary_committed"] is False
    assert sanitized_evidence["godot_import_verified"] is False
    assert sanitized_evidence["visual_approval_claimed"] is False

    unresolved = []
    for rel_path, entry in contract["required_source_manifest"].items():
        assert len(entry["git_blob_sha1"]) == 40
        assert entry["upstream_path"]
        assert isinstance(entry["license_scope_verified"], bool)
        if entry["license_scope_verified"]:
            assert entry.get("license") in {"CC0-1.0", "CC-BY-4.0", "MIT"}
        else:
            unresolved.append(entry["blocked_component"])
            assert entry.get("geometry_license_scope_verified") is True
        if entry["size_bytes"] is not None:
            assert entry["size_bytes"] > 0
        assert rel_path.startswith("assets/characters/civilians/civ1/source/")

    evidence = contract["required_character_source"]["license_evidence"]
    assert contract["required_character_source"]["license_claim"] == "MIXED_BY_COMPONENT"
    assert evidence["character_geometry_license"] == "CC0-1.0"
    assert evidence["character_geometry_redistribution_verified"] is True
    assert evidence["animation_payload_license"] == "ADOBE_MIXAMO_TERMS"
    assert unresolved == ["embedded_mixamo_animations"]
    assert contract["authorizations"]["source_materialization"] is False

    assert set(contract["forbidden_civilian_runtime_sources"]).issubset(set(status["forbidden_runtime_paths"]))
    assert 'actor.name == "Player" and _try_build_authored_character()' in visual
    assert 'if actor is NpcAgent:' in visual
    assert '_build_profiled_npc(actor as NpcAgent)' in visual
    assert 'set_meta("custom_mesh_pipeline", "array_mesh_profiled_v2")' in visual

    for rel_path in status["source_paths"]:
        assert not (ROOT / rel_path).exists(), f"source payload appeared without readiness promotion: {rel_path}"
    for rel_path in status["runtime_files"]:
        assert not (ROOT / rel_path).exists(), f"runtime payload appeared without readiness promotion: {rel_path}"
    assert status["runtime_sha256"] == {}
    assert contract["verdict"] == "BLOCK_RUNTIME_PROMOTION_UNTIL_GODOT_IMPORT_AND_AUTHORED_CIVILIAN_PACKAGE_READY"
    assert all(value is False for value in contract["authorizations"].values())


if __name__ == "__main__":
    test_authored_civilian_roster_readiness_is_fail_closed()
    print("AUTHORED_CIVILIAN_ROSTER_READINESS_GREEN")
