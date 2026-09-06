import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GATE_PATH = ROOT / "data" / "qa" / "grand_place_facade_visual_gate.json"
MODULE_PATH = ROOT / "data" / "runtime" / "modules" / "grand_place_owner_identity_presentation.json"
WORKFLOW_PATH = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-grand-place-facade-evidence.yml"
INTEGRATION_FLOOR = "188ef30b9286f6ae84ffff80b332b3922864bec2"
LATEST_REVIEW_HEAD = "9b584f5260f3fa7c4fc290bf3d59c5ec3e0447b8"
LATEST_REVIEW_RUN = 32987132015
LATEST_REVIEW_ARTIFACT = 9613355631
LATEST_REVIEW_DIGEST = "sha256:72f5632f5a452effc8f5f47473df73e5bd97df61cc3acb31aa145964be07d7f4"
LATEST_REVIEW_MANIFEST_SHA256 = "4fd4900e4724f9dfbf50081c0d83e4ac306072780e7a22d392480abe371e4218"
LATEST_REVIEW_PNG_SHA256 = {
    "canonical.png": "b2d39089d09496231954b5926b580f78465e4fdd20edeefc040dfa4e26bef8ed",
    "cornet_renard.png": "a150b679ecb3d168b5ec50a67cadb0d5d8f2905b4a0a4418bf58f6047201f355",
    "brasseurs_rose_thabor.png": "e65050d064f4773dd583bab73a9c804c75f50bd53a2846924e1ff09b1e939bc7",
    "maison_du_roi.png": "802d511e9baf326ca5fc9f39b9734689bda80fd28075efdad5ac80d7132e3af5",
}


def _load(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def test_grand_place_facade_gate_remains_fail_closed():
    gate = _load(GATE_PATH)
    assert gate["integration_floor_sha"] == INTEGRATION_FLOOR
    assert "production_base_sha" not in gate
    assert len(gate["integration_floor_sha"]) == 40
    assert gate["integration_floor_sha"] == gate["integration_floor_sha"].lower()
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


def test_facade_workflow_uses_durable_integration_floor_and_live_main_ancestry():
    workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
    assert "git fetch --no-tags origin main" in workflow
    assert "origin/main" in workflow
    assert "git merge-base --is-ancestor" in workflow
    assert "GB_LIVE_MAIN_SHA" in workflow
    assert "GB_EVIDENCE_HEAD_SHA" in workflow
    assert "GB_INTEGRATION_FLOOR_SHA" in workflow
    assert "integration_floor_sha" in workflow
    assert 'gate.get("production_base_sha"' not in workflow
    assert "stale Grand-Place evidence base" not in workflow
    assert "legacy production_base_sha is forbidden" in workflow
    assert "Grand-Place integration floor is not an ancestor of live main" in workflow
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
