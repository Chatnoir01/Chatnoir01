import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = ROOT / "data" / "qa" / "grand_place_facade_visual_gate.json"
MODULE_PATH = ROOT / "data" / "runtime" / "modules" / "grand_place_owner_identity_presentation.json"
WORKFLOW_PATH = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-grand-place-facade-evidence.yml"
LIVE_REBUILD_BASE = "f2a5796e6d5cd867cd482d600bcd9eda6ab0ed36"


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


def test_facade_workflow_rejects_stale_production_base_sha():
    workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
    assert "git fetch --no-tags origin main" in workflow
    assert "origin/main" in workflow
    assert "git merge-base --is-ancestor" in workflow
    assert "GB_LIVE_MAIN_SHA" in workflow
    assert "GB_EVIDENCE_HEAD_SHA" in workflow
    assert "production_base_sha" in workflow
    assert "stale Grand-Place evidence base" in workflow
    assert "Grand-Place candidate does not contain live main" in workflow
    assert "grand_place_facade_visual_gate.json" in workflow


def test_facade_workflow_reverifies_png_hashes_immediately_before_validator():
    workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
    assert workflow.count("sha256sum --check png-sha256.txt") >= 2
    validate_step = workflow.split("- name: Validate engine-generated witness artifact", 1)[1]
    assert "test \"$(wc -l < png-sha256.txt)\" -eq 4" in validate_step
    assert "sha256sum --check png-sha256.txt" in validate_step
    assert "validate_grand_place_facade_evidence.py" in validate_step
    assert validate_step.index("sha256sum --check png-sha256.txt") < validate_step.index("validate_grand_place_facade_evidence.py")


def test_grand_place_visual_evidence_cannot_be_satisfied_by_generic_photo_match():
    gate = _load(GATE_PATH)
    evidence = gate["evidence_contract"]
    assert evidence["artifact_kind"] == "grand_place_facade_visual_witness"
    assert evidence["required_resolution"] == [1280, 720]
    assert evidence["required_view_ids"] == ["canonical", "cornet_renard", "brasseurs_rose_thabor", "maison_du_roi"]
    assert evidence["generic_photo_match_artifact_is_sufficient"] is False
    assert evidence["human_full_frame_inspection_required"] is True
    assert evidence["numeric_gate_alone_is_sufficient"] is False


def test_rebuilt_identity_module_references_a_real_runtime_script():
    module = _load(MODULE_PATH)
    resource = module["path"]
    assert resource.startswith("res://")
    runtime_script = ROOT / resource.removeprefix("res://")
    assert runtime_script.is_file(), f"Grand-Place identity module points to missing runtime script: {resource}"
