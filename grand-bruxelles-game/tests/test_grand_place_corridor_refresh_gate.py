import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = ROOT / "data" / "qa" / "grand_place_facade_visual_gate.json"
MODULE_PATH = ROOT / "data" / "runtime" / "modules" / "grand_place_owner_identity_presentation.json"
WORKFLOW_PATH = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-grand-place-facade-evidence.yml"
LIVE_REBUILD_BASE = "0950c847303057c13802667165fa836becae0321"
LATEST_REVIEW_HEAD = "44377dde1d3ac2d754e01c87ada1d129eb812ef7"
LATEST_REVIEW_RUN = 32850758541
LATEST_REVIEW_ARTIFACT = 9564256215
LATEST_REVIEW_DIGEST = "sha256:af7fe0ab83684349078bb3a629edf901323238b231313688933396623a97e041"
LATEST_REVIEW_MANIFEST_SHA256 = "5efd15ac8daf39782d2302d346235171541193cab860474fedddd281394120e8"
LATEST_REVIEW_PNG_SHA256 = {
    "canonical.png": "0b0ea00dcee5a3ca196d380f6f4c92450649ec81898e44343ee4ea9a1650a234",
    "cornet_renard.png": "209c3f05ae7a91e948291aced5771317a6719836494e2976d20c9a3f2aaeb07e",
    "brasseurs_rose_thabor.png": "d826606c9d418d794254124212fec198239ebb9f781eda9f6d92323c4f1cf3f2",
    "maison_du_roi.png": "a4534c2c4d27dd0227968acd4e3ede72b4990a9683ffae3fb0404176ee6994ee",
}


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


def test_latest_human_full_frame_review_is_bound_to_exact_artifact_and_remains_rejected():
    gate = _load(GATE_PATH)
    review = gate["latest_human_review"]
    assert review["head_sha"] == LATEST_REVIEW_HEAD
    assert review["workflow_run_id"] == LATEST_REVIEW_RUN
    assert review["artifact_id"] == LATEST_REVIEW_ARTIFACT
    assert review["artifact_digest"] == LATEST_REVIEW_DIGEST
    assert review["manifest_sha256"] == LATEST_REVIEW_MANIFEST_SHA256
    assert review["png_sha256"] == LATEST_REVIEW_PNG_SHA256
    assert len(set(review["png_sha256"].values())) == 4
    assert review["resolution"] == [1280, 720]
    assert review["full_frame_inspected"] is True
    assert review["overall_verdict"] == "reject"
    verdicts = review["view_verdicts"]
    assert verdicts["cornet_renard"] == "reject"
    assert verdicts["maison_du_roi"] == "reject"
    assert review["production_culling"] == "CULL_BACK"
    assert review["source_geometry_changed"] is False
    assert review["source_collision_changed"] is False
    notes = review["notes"]
    assert any(str(LATEST_REVIEW_ARTIFACT) in note and "SHA-256" in note for note in notes)
    assert any("four PNG" in note and "pairwise distinct" in note for note in notes)
    assert any("manifest" in note.lower() and LATEST_REVIEW_MANIFEST_SHA256 in note for note in notes)


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


def test_facade_manifest_base_comes_from_verified_live_main_not_pr_snapshot():
    workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
    continuity_step = workflow.split("- name: Verify Grand-Place live-main continuity", 1)[1].split("- name: Install software renderer dependencies", 1)[0]
    capture_step = workflow.split("- name: Capture four real Grand-Place facade views", 1)[1].split("- name: Bind witness payload with SHA-256 sidecar", 1)[0]
    assert 'echo "GB_LIVE_MAIN_SHA=$GB_LIVE_MAIN_SHA" >> "$GITHUB_ENV"' in continuity_step
    assert "GB_EVIDENCE_BASE_SHA: ${{ env.GB_LIVE_MAIN_SHA }}" in capture_step
    assert "github.event.pull_request.base.sha" not in capture_step


def test_facade_workflow_reverifies_png_hashes_immediately_before_validator():
    workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
    assert workflow.count("sha256sum --check png-sha256.txt") >= 2
    validate_step = workflow.split("- name: Validate engine-generated witness artifact", 1)[1]
    assert "test \"$(wc -l < png-sha256.txt)\" -eq 4" in validate_step
    assert "sha256sum --check png-sha256.txt" in validate_step
    assert "validate_grand_place_facade_evidence.py" in validate_step
    assert validate_step.index("sha256sum --check png-sha256.txt") < validate_step.index("validate_grand_place_facade_evidence.py")


def test_facade_workflow_cryptographically_binds_manifest_with_all_pngs():
    workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
    required = "canonical.png cornet_renard.png brasseurs_rose_thabor.png maison_du_roi.png manifest.json"
    assert f"sha256sum {required} > evidence-sha256.txt" in workflow
    assert workflow.count("sha256sum --check evidence-sha256.txt") >= 2
    bind_step = workflow.split("- name: Bind witness payload with SHA-256 sidecar", 1)[1]
    assert "test \"$(wc -l < evidence-sha256.txt)\" -eq 5" in bind_step
    validate_step = workflow.split("- name: Validate engine-generated witness artifact", 1)[1]
    assert "test \"$(wc -l < evidence-sha256.txt)\" -eq 5" in validate_step
    assert validate_step.index("sha256sum --check evidence-sha256.txt") < validate_step.index("validate_grand_place_facade_evidence.py")


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
