import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / "data/qa/photo_match/atomium_ground_framing_evidence.json"
PATCH = ROOT / "data/qa/photo_match/manifest.atomium_patch.json"


def test_atomium_framing_evidence_contract():
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    assert evidence["geometry"]["project_crs"] == "EPSG:31370"
    assert evidence["reference"]["license"] == "CC BY-SA 4.0"
    assert evidence["reference"]["lens_focal_length_status"] == "not_available"
    assert evidence["framing_witness"]["historical_lens_claimed"] is False
    assert evidence["runtime_approved"] is False
    assert evidence["realism_complete"] is False


def test_handoff_patch_is_bounded_and_non_final():
    evidence = json.loads(EVIDENCE.read_text(encoding="utf-8"))
    patch = json.loads(PATCH.read_text(encoding="utf-8"))
    selected = evidence["framing_witness"]["selected_provisional_vertical_fov_degrees"]
    maximum = evidence["framing_witness"]["maximum_compatible_vertical_fov_degrees"]
    assert selected <= maximum
    assert math.isclose(selected, 31.5, abs_tol=1e-9)
    assert patch["reference_id"] == "atomium_ground_oblique_v1"
    assert math.isclose(patch["set"]["viewpoint.game_camera_transform.fov_degrees"], selected, abs_tol=1e-9)
    assert patch["set"]["viewpoint.game_camera_transform.status"] == "evidence_bounded_provisional"
    assert patch["set"]["realism_complete"] is False
