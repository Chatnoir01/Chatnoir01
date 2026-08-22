from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT / ".github/workflows/grand-bruxelles-grand-place-facade-evidence.yml"
CAPTURE = ROOT / "grand-bruxelles-game/game/tests/grand_place_facade_evidence_capture.gd"


def test_facade_evidence_workflow_runs_real_godot_capture():
    workflow = WORKFLOW.read_text(encoding="utf-8")
    required = [
        "Godot_v4.7.1-stable_linux.x86_64",
        "xvfb-run -a",
        "--rendering-method gl_compatibility",
        "--script res://game/tests/grand_place_facade_evidence_capture.gd",
        "grand-place-facade-evidence/manifest.json",
        "actions/upload-artifact@v4",
        "ref: ${{ github.event.pull_request.head.sha }}",
    ]
    for marker in required:
        assert marker in workflow, f"dedicated facade evidence workflow is fixture-only or not exact-head; missing {marker!r}"


def test_facade_evidence_artifact_hashes_all_four_exact_png_frames():
    workflow = WORKFLOW.read_text(encoding="utf-8")
    required = [
        "sha256sum canonical.png cornet_renard.png brasseurs_rose_thabor.png maison_du_roi.png > png-sha256.txt",
        "sha256sum --check png-sha256.txt",
        'test "$(wc -l < png-sha256.txt)" -eq 4',
        "GRAND_PLACE_FACADE_PNG_HASHES_OK count=4",
        "grand-bruxelles-game/artifacts/grand-place-facade-evidence/png-sha256.txt",
    ]
    for marker in required:
        assert marker in workflow, f"facade witness bytes are not fail-closed and hash-bound; missing {marker!r}"


def test_capture_harness_is_engine_bound_and_writes_four_png_views():
    assert CAPTURE.is_file(), "real Godot facade capture harness is missing"
    source = CAPTURE.read_text(encoding="utf-8")
    required = [
        'load("res://game/main.tscn")',
        'res://data/qa/grand_place_facade_visual_gate.json',
        'GrandPlaceCompleteContourRuntime',
        'root.get_texture().get_image()',
        'image.save_png',
        '"human_review_status": "pending"',
        "Camera3D.new()",
        "_hide_non_facade_overlays(root)",
        "PROCESS_MODE_DISABLED",
    ]
    for marker in required:
        assert marker in source, f"capture harness is not bound to an isolated real-engine witness contract; missing {marker!r}"
    for view_id in ("canonical", "cornet_renard", "brasseurs_rose_thabor", "maison_du_roi"):
        assert view_id in source


def test_maison_du_roi_witness_records_real_source_surface_facing_measurement():
    source = CAPTURE.read_text(encoding="utf-8")
    required = [
        'MAISON_DU_ROI_OWNER_ID := "1654360"',
        "_owner_surface_facing_measurement",
        '"source_surface_facing"',
        '"wall_triangles"',
        '"roof_triangles"',
        '"front_facing_wall_triangles"',
        '"front_facing_wall_area_ratio"',
        '"front_facing_roof_area_ratio"',
        '"dominant_front_wall_normal"',
    ]
    for marker in required:
        assert marker in source, f"Maison du Roi witness does not quantify exact source surface orientation; missing {marker!r}"


def test_source_facing_measurement_accepts_legitimate_unindexed_mesh_surfaces():
    source = CAPTURE.read_text(encoding="utf-8")
    assert "var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]" not in source, (
        "Godot returns null in ARRAY_INDEX for legitimate unindexed ArrayMesh surfaces; "
        "a typed direct assignment reproduces the Facade Evidence crash"
    )
    required = [
        "var indices := PackedInt32Array()",
        "arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null",
        "typeof(arrays[Mesh.ARRAY_INDEX]) != TYPE_PACKED_INT32_ARRAY",
        "indices = arrays[Mesh.ARRAY_INDEX]",
        "indices.size() if not indices.is_empty() else vertices.size()",
    ]
    for marker in required:
        assert marker in source, f"unindexed source meshes are not handled fail-closed; missing {marker!r}"
