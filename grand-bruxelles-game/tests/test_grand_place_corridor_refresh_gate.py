import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = ROOT / "data" / "qa" / "grand_place_facade_visual_gate.json"
MODULE_PATH = ROOT / "data" / "runtime" / "modules" / "grand_place_owner_identity_presentation.json"
LIVE_REBUILD_BASE = "d83495ad605507737dd9191eb0a46e51692e256e"


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def test_grand_place_facade_gate_remains_fail_closed():
    gate = _load(GATE_PATH)
    assert gate["production_base_sha"] == LIVE_REBUILD_BASE
    assert gate["resolution"] == [1280, 720]
    assert gate["camera_position"] == [319.01, 1.72, -535.20]
    assert gate["fov_deg"] == 62.0
    assert gate["required_views"] == 4
    views = {view["id"]: view for view in gate["views"]}
    cornet = views["cornet_renard"]
    assert cornet["target_method"] == "source_bbox_cluster_center"
    assert cornet["target_owner_ids"] == ["1608847", "1608851"]
    assert cornet["minimum_bbox_width"] == 220
    assert cornet["minimum_bbox_height"] == 140
    assert cornet["last_observed_bbox_width"] == 187
    assert cornet["last_observed_verdict"] == "reject"
    assert cornet["last_observed_bbox_width"] < cornet["minimum_bbox_width"]
    assert all(gate["freeze"].values())
    rules = gate["hard_rules"]
    assert rules["camera_position_move_for_pass"] is False
    assert rules["fov_change_for_pass"] is False
    assert rules["source_bbox_target_change_after_first_render"] is False
    assert rules["threshold_reduction_after_first_render"] is False
    assert rules["human_full_frame_pass_required"] is True
    assert rules["numeric_pass_alone_authorizes_finished_perfect"] is False
    assert rules["finished_perfect_on_this_phase"] is False


def test_grand_place_visual_evidence_cannot_be_satisfied_by_generic_photo_match():
    gate = _load(GATE_PATH)
    evidence = gate["evidence_contract"]
    assert evidence["artifact_kind"] == "grand_place_facade_visual_witness"
    assert evidence["required_resolution"] == [1280, 720]
    assert evidence["required_view_ids"] == [
        "canonical",
        "cornet_renard",
        "brasseurs_rose_thabor",
        "maison_du_roi",
    ]
    assert evidence["generic_photo_match_artifact_is_sufficient"] is False
    assert evidence["human_full_frame_inspection_required"] is True
    assert evidence["numeric_gate_alone_is_sufficient"] is False


def test_rebuilt_identity_module_references_a_real_runtime_script():
    module = _load(MODULE_PATH)
    resource = module["path"]
    assert resource.startswith("res://")
    runtime_script = ROOT / resource.removeprefix("res://")
    assert runtime_script.is_file(), f"Grand-Place identity module points to missing runtime script: {resource}"
