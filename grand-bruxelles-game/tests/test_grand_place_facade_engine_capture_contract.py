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
