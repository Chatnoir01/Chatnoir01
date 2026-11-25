import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-grand-place-maison-winding-ab.yml"
CAPTURE = ROOT / "grand-bruxelles-game/game/tests/grand_place_maison_du_roi_winding_ab.gd"
PRESENTATION = ROOT / "grand-bruxelles-game/game/scripts/grand_place_owner_identity_presentation.gd"
SOURCE_DIAGNOSTIC = ROOT / "grand-bruxelles-game/tools/qa/grand_place_source_winding_diagnostic.py"
SOURCE = ROOT / "grand-bruxelles-game/data/urbis/grand_place_lod2/1654360.game.json"


def test_maison_du_roi_winding_ab_is_real_engine_same_camera_evidence():
    assert WORKFLOW.is_file(), "dedicated Maison du Roi winding A/B workflow is missing"
    assert CAPTURE.is_file(), "dedicated Maison du Roi winding A/B Godot harness is missing"
    assert PRESENTATION.is_file(), "Grand-Place owner presentation runtime is missing"
    assert SOURCE_DIAGNOSTIC.is_file(), "Maison du Roi source winding diagnostic is missing"
    workflow = WORKFLOW.read_text(encoding="utf-8")
    capture = CAPTURE.read_text(encoding="utf-8")
    presentation = PRESENTATION.read_text(encoding="utf-8")
    for marker in ("Godot_v4.7.1-stable_linux.x86_64","xvfb-run -a","--rendering-method gl_compatibility","--script res://game/tests/grand_place_maison_du_roi_winding_ab.gd","actions/upload-artifact@v4","if-no-files-found: error"):
        assert marker in workflow, f"winding A/B workflow is not real-engine/fail-closed; missing {marker!r}"
    for marker in ('grand_place_source_winding_diagnostic.py','data/urbis/grand_place_lod2/1654360.game.json','--camera 319.01 1.72 -535.20','maison_du_roi_source_winding.json','grand-bruxelles-grand-place-source-winding-diagnostic-v1','raw_front_wall_area_ratio','runtime_oriented_front_wall_area_ratio','raw_front_roof_area_ratio','runtime_oriented_front_roof_area_ratio'):
        assert marker in workflow, f"winding A/B workflow is missing exact source-orientation evidence; missing {marker!r}"
    for marker in ('MAISON_DU_ROI_OWNER_ID := "1654360"','PRESENTATION_RUNTIME_NAME := "GrandPlaceOwnerIdentityPresentation"','set_source_winding_diagnostic_cull_mode','maison_du_roi_cull_back.png','maison_du_roi_cull_front.png','maison_du_roi_cull_disabled.png','maison_du_roi_winding_ab.json','"camera_position"','"fov_deg"','"production_default_cull_mode": "CULL_BACK"','"production_mitigation_authorized": false','"source_geometry_changed": false','"source_collision_changed": false','"human_review_required": true','"human_review_status": "pending"'):
        assert marker in capture, f"winding diagnostic harness is not bounded/reversible; missing {marker!r}"
    assert "func set_source_winding_diagnostic_cull_mode(mode: int) -> bool:" in presentation
    assert "BaseMaterial3D.CULL_FRONT" in presentation
    assert "camera.global_position = frozen_camera_position" in capture
    assert "camera.look_at(target, Vector3.UP)" in capture
    assert "await _capture_png(\"maison_du_roi_cull_back.png\")" in capture
    assert "await _capture_png(\"maison_du_roi_cull_front.png\")" in capture
    assert "await _capture_png(\"maison_du_roi_cull_disabled.png\")" in capture
    assert capture.count("BaseMaterial3D.CULL_BACK") >= 2
    assert "BaseMaterial3D.CULL_FRONT" in capture
    assert "BaseMaterial3D.CULL_DISABLED" in capture
    assert "production winding state was not restored to CULL_BACK after diagnostic" in capture


def test_maison_du_roi_source_winding_quantifies_runtime_facing_loss():
    proc = subprocess.run(
        [
            sys.executable,
            str(SOURCE_DIAGNOSTIC),
            "--source",
            str(SOURCE),
            "--camera",
            "319.01",
            "1.72",
            "-535.20",
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    report = json.loads(proc.stdout)
    assert report["owner_id"] == "1654360"
    assert report["source_geometry_changed"] is False
    assert report["source_collision_changed"] is False
    wall_loss = float(report["wall_front_area_ratio_loss_due_to_runtime_orientation"])
    roof_loss = float(report["roof_front_area_ratio_loss_due_to_runtime_orientation"])
    assert wall_loss == report["raw_front_wall_area_ratio"] - report["runtime_oriented_front_wall_area_ratio"]
    assert roof_loss == report["raw_front_roof_area_ratio"] - report["runtime_oriented_front_roof_area_ratio"]
    assert wall_loss > 0.25, "known Maison wall-facing loss disappeared; shared winding ownership must review"
    assert roof_loss > 0.25, "known Maison roof-facing loss disappeared; shared winding ownership must review"


def test_maison_du_roi_winding_ab_artifact_is_hash_bound_before_upload():
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "evidence-sha256.txt" in workflow, "winding evidence hash sidecar is missing"
    for filename in ("maison_du_roi_cull_back.png","maison_du_roi_cull_front.png","maison_du_roi_cull_disabled.png","maison_du_roi_winding_ab.json","maison_du_roi_source_winding.json"):
        assert filename in workflow, f"winding evidence hash binding omits {filename}"
    bind = "sha256sum maison_du_roi_cull_back.png maison_du_roi_cull_front.png maison_du_roi_cull_disabled.png maison_du_roi_winding_ab.json maison_du_roi_source_winding.json > evidence-sha256.txt"
    assert bind in workflow
    assert workflow.count('test "$(wc -l < evidence-sha256.txt)" -eq 5') >= 2, "winding evidence sidecar must contain exactly five bound files"
    assert workflow.count("sha256sum --check evidence-sha256.txt") >= 2, "winding evidence must be verified when bound and again immediately before artifact upload"
    bind_pos = workflow.index(bind)
    first_check_pos = workflow.index("sha256sum --check evidence-sha256.txt", bind_pos)
    upload_pos = workflow.index("uses: actions/upload-artifact@v4")
    second_check_pos = workflow.rindex("sha256sum --check evidence-sha256.txt", 0, upload_pos)
    assert bind_pos < first_check_pos < second_check_pos < upload_pos
