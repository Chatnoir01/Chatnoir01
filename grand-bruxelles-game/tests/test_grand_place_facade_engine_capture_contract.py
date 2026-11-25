import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-grand-place-facade-evidence.yml"
CAPTURE = ROOT / "grand-bruxelles-game/game/tests/grand_place_facade_evidence_capture.gd"
PRESENTATION = ROOT / "grand-bruxelles-game/game/scripts/grand_place_owner_identity_presentation.gd"
WINDING_DIAGNOSTIC = ROOT / "grand-bruxelles-game/tools/qa/grand_place_source_winding_diagnostic.py"
MAISON_DU_ROI_SOURCE = ROOT / "grand-bruxelles-game/data/urbis/grand_place_lod2/1654360.game.json"


def test_facade_evidence_workflow_runs_real_godot_capture():
    workflow = WORKFLOW.read_text(encoding="utf-8")
    required = ["Godot_v4.7.1-stable_linux.x86_64","xvfb-run -a","--rendering-method gl_compatibility","--script res://game/tests/grand_place_facade_evidence_capture.gd","grand-place-facade-evidence/manifest.json","actions/upload-artifact@v4","ref: ${{ github.event.pull_request.head.sha }}"]
    for marker in required:
        assert marker in workflow, f"dedicated facade evidence workflow is fixture-only or not exact-head; missing {marker!r}"


def test_facade_evidence_godot_download_is_resilient_to_transient_transport_failure():
    workflow = WORKFLOW.read_text(encoding="utf-8")
    download_url = "https://github.com/godotengine/godot-builds/releases/download/4.7.1-stable/Godot_v4.7.1-stable_linux.x86_64.zip"
    assert download_url in workflow
    assert "--retry 4" in workflow
    assert "--retry-all-errors" in workflow
    assert "--retry-delay 2" in workflow


def test_facade_evidence_artifact_hashes_all_four_exact_png_frames():
    workflow = WORKFLOW.read_text(encoding="utf-8")
    required = ["sha256sum canonical.png cornet_renard.png brasseurs_rose_thabor.png maison_du_roi.png > png-sha256.txt","sha256sum --check png-sha256.txt",'test "$(wc -l < png-sha256.txt)" -eq 4',"GRAND_PLACE_FACADE_PNG_HASHES_OK count=4","grand-bruxelles-game/artifacts/grand-place-facade-evidence/png-sha256.txt"]
    for marker in required:
        assert marker in workflow, f"facade witness bytes are not fail-closed and hash-bound; missing {marker!r}"


def test_facade_evidence_upload_is_single_root_and_preserves_full_frame_witness():
    workflow = WORKFLOW.read_text(encoding="utf-8")
    assert "Stage witness logs inside artifact root" in workflow, "the upload currently mixes repository-relative evidence with /tmp logs; GitHub artifact packaging can then retain only the logs and silently drop the PNG witness"
    assert "cp /tmp/grand-place-facade-import.log artifacts/grand-place-facade-evidence/" in workflow
    assert "cp /tmp/grand-place-facade-capture.log artifacts/grand-place-facade-evidence/" in workflow
    assert "path: grand-bruxelles-game/artifacts/grand-place-facade-evidence/" in workflow
    upload_block = workflow.split("- name: Upload dedicated Grand-Place facade witness", 1)[1]
    assert "/tmp/grand-place-facade-import.log" not in upload_block
    assert "/tmp/grand-place-facade-capture.log" not in upload_block


def test_capture_harness_is_engine_bound_and_writes_four_png_views():
    assert CAPTURE.is_file(), "real Godot facade capture harness is missing"
    source = CAPTURE.read_text(encoding="utf-8")
    required = ['load("res://game/main.tscn")','res://data/qa/grand_place_facade_visual_gate.json','GrandPlaceCompleteContourRuntime','root.get_texture().get_image()','image.save_png','"human_review_status": "pending"',"Camera3D.new()","_hide_non_facade_overlays(root)","PROCESS_MODE_DISABLED"]
    for marker in required:
        assert marker in source, f"capture harness is not bound to an isolated real-engine witness contract; missing {marker!r}"
    for view_id in ("canonical", "cornet_renard", "brasseurs_rose_thabor", "maison_du_roi"):
        assert view_id in source


def test_maison_du_roi_witness_records_real_source_surface_facing_measurement():
    source = CAPTURE.read_text(encoding="utf-8")
    required = ['MAISON_DU_ROI_OWNER_ID := "1654360"',"_owner_surface_facing_measurement",'"source_surface_facing"','"wall_triangles"','"roof_triangles"','"front_facing_wall_triangles"','"front_facing_wall_area_ratio"','"front_facing_roof_area_ratio"','"dominant_front_wall_normal"']
    for marker in required:
        assert marker in source, f"Maison du Roi witness does not quantify exact source surface orientation; missing {marker!r}"


def test_source_facing_measurement_accepts_legitimate_unindexed_mesh_surfaces():
    source = CAPTURE.read_text(encoding="utf-8")
    assert "var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]" not in source, "Godot returns null in ARRAY_INDEX for legitimate unindexed ArrayMesh surfaces; a typed direct assignment reproduces the Facade Evidence crash"
    required = ["var indices := PackedInt32Array()","arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null","typeof(arrays[Mesh.ARRAY_INDEX]) != TYPE_PACKED_INT32_ARRAY","indices = arrays[Mesh.ARRAY_INDEX]","indices.size() if not indices.is_empty() else vertices.size()"]
    for marker in required:
        assert marker in source, f"unindexed source meshes are not handled fail-closed; missing {marker!r}"


def test_maison_du_roi_source_winding_diagnostic_reproduces_engine_facing_telemetry():
    assert WINDING_DIAGNOSTIC.is_file(), "source-vs-runtime winding diagnostic is missing"
    assert MAISON_DU_ROI_SOURCE.is_file(), "Maison du Roi exact UrbIS source is missing"
    result = subprocess.run([sys.executable,str(WINDING_DIAGNOSTIC),"--source",str(MAISON_DU_ROI_SOURCE),"--camera","319.01","1.72","-535.20"],check=False,capture_output=True,text=True)
    assert result.returncode == 0, result.stderr or result.stdout
    report = json.loads(result.stdout)
    assert report["owner_id"] == "1654360"
    assert report["wall_triangles"] == 122
    assert report["roof_triangles"] == 91
    assert abs(report["runtime_oriented_front_wall_area_ratio"] - 0.295691) < 0.0005
    assert abs(report["runtime_oriented_front_roof_area_ratio"] - 0.304796) < 0.0005
    assert report["wall_triangles_flipped_by_center_heuristic"] == 103
    assert report["roof_triangles_flipped_upward"] == 91
    assert report["raw_front_wall_area_ratio"] > report["runtime_oriented_front_wall_area_ratio"]
    assert report["raw_front_roof_area_ratio"] > report["runtime_oriented_front_roof_area_ratio"]


def test_maison_du_roi_winding_diagnostic_is_exact_owner_and_production_defaults_cull_back():
    source = PRESENTATION.read_text(encoding="utf-8")
    required = ['WINDING_DIAGNOSTIC_OWNER_IDS := ["1654360"]','mat.cull_mode = BaseMaterial3D.CULL_BACK','mat.set_meta("source_winding_diagnostic_candidate", owner_id in WINDING_DIAGNOSTIC_OWNER_IDS)','mat.set_meta("source_winding_mitigation_enabled", false)','set_meta("source_winding_mitigation_production_authorized", false)','func set_source_winding_diagnostic_cull_mode(mode: int) -> bool:','mode not in [BaseMaterial3D.CULL_BACK, BaseMaterial3D.CULL_FRONT, BaseMaterial3D.CULL_DISABLED]','mat.cull_mode = mode','return set_source_winding_diagnostic_cull_mode(BaseMaterial3D.CULL_DISABLED if enabled else BaseMaterial3D.CULL_BACK)']
    for marker in required:
        assert marker in source, f"Maison du Roi winding diagnostic/default is missing or not exact-owner bounded; missing {marker!r}"
    assert 'WINDING_DIAGNOSTIC_OWNER_IDS := ["1654360",' not in source
    assert "mat.transparency" not in source
    assert "mat.no_depth_test" not in source
    assert ".position =" not in source
    assert ".global_position =" not in source
    assert ".scale =" not in source
