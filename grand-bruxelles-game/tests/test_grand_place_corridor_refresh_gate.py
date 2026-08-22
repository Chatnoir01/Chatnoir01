import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = ROOT / "data" / "qa" / "grand_place_facade_visual_gate.json"
MODULE_PATH = ROOT / "data" / "runtime" / "modules" / "grand_place_facade_presentation_integrated_v5.json"


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def test_grand_place_facade_gate_remains_fail_closed():
    gate = _load(GATE_PATH)
    assert gate["production_base_sha"] == "f7b355421098e9de1cecddeaf999df622fd04aec"
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


def test_grand_place_presentation_module_cannot_reference_a_missing_runtime_script():
    if not MODULE_PATH.exists():
        return

    module = _load(MODULE_PATH)
    resource = module["path"]
    assert resource.startswith("res://")
    runtime_script = ROOT / resource.removeprefix("res://")
    assert runtime_script.is_file(), (
        f"Grand-Place presentation module points to missing runtime script: {resource}"
    )
