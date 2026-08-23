from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-grand-place-maison-winding-ab.yml"
CAPTURE = ROOT / "grand-bruxelles-game/game/tests/grand_place_maison_du_roi_winding_ab.gd"


def test_maison_du_roi_winding_ab_is_real_engine_same_camera_evidence():
    assert WORKFLOW.is_file(), "dedicated Maison du Roi winding A/B workflow is missing"
    assert CAPTURE.is_file(), "dedicated Maison du Roi winding A/B Godot harness is missing"
    workflow = WORKFLOW.read_text(encoding="utf-8")
    capture = CAPTURE.read_text(encoding="utf-8")

    for marker in (
        "Godot_v4.7.1-stable_linux.x86_64",
        "xvfb-run -a",
        "--rendering-method gl_compatibility",
        "--script res://game/tests/grand_place_maison_du_roi_winding_ab.gd",
        "actions/upload-artifact@v4",
        "if-no-files-found: error",
    ):
        assert marker in workflow, f"winding A/B workflow is not real-engine/fail-closed; missing {marker!r}"

    for marker in (
        'MAISON_DU_ROI_OWNER_ID := "1654360"',
        'PRESENTATION_RUNTIME_NAME := "GrandPlaceOwnerIdentityPresentation"',
        'set_source_winding_mitigation_enabled',
        'maison_du_roi_cull_back.png',
        'maison_du_roi_cull_disabled.png',
        'maison_du_roi_winding_ab.json',
        '"camera_position"',
        '"fov_deg"',
        '"production_default_cull_mode": "CULL_BACK"',
        '"production_mitigation_authorized": false',
        '"source_geometry_changed": false',
        '"source_collision_changed": false',
        '"human_review_required": true',
        '"human_review_status": "pending"',
    ):
        assert marker in capture, f"winding A/B harness is not bounded/reversible; missing {marker!r}"

    assert "camera.global_position = frozen_camera_position" in capture
    assert "camera.look_at(target, Vector3.UP)" in capture
    assert "await _capture_png(\"maison_du_roi_cull_back.png\")" in capture
    assert "await _capture_png(\"maison_du_roi_cull_disabled.png\")" in capture
    assert capture.count("set_source_winding_mitigation_enabled(false)") >= 2
    assert "set_source_winding_mitigation_enabled(true)" in capture
    assert "production winding state was not restored to CULL_BACK after A/B" in capture


def test_maison_du_roi_winding_ab_artifact_is_hash_bound_before_upload():
    workflow = WORKFLOW.read_text(encoding="utf-8")

    assert "evidence-sha256.txt" in workflow, "A/B evidence hash sidecar is missing"
    for filename in (
        "maison_du_roi_cull_back.png",
        "maison_du_roi_cull_disabled.png",
        "maison_du_roi_winding_ab.json",
    ):
        assert filename in workflow, f"A/B evidence hash binding omits {filename}"

    assert "sha256sum maison_du_roi_cull_back.png maison_du_roi_cull_disabled.png maison_du_roi_winding_ab.json > evidence-sha256.txt" in workflow
    assert workflow.count("sha256sum --check evidence-sha256.txt") >= 2, (
        "A/B evidence must be verified when bound and again immediately before artifact upload"
    )

    bind_pos = workflow.index("sha256sum maison_du_roi_cull_back.png maison_du_roi_cull_disabled.png maison_du_roi_winding_ab.json > evidence-sha256.txt")
    first_check_pos = workflow.index("sha256sum --check evidence-sha256.txt", bind_pos)
    upload_pos = workflow.index("uses: actions/upload-artifact@v4")
    second_check_pos = workflow.rindex("sha256sum --check evidence-sha256.txt", 0, upload_pos)
    assert bind_pos < first_check_pos < second_check_pos < upload_pos
