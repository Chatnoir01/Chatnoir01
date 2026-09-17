from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
CONFORMANCE = ROOT / "game/tests/anneessens_osm_building_runtime_conformance_test.gd"
RECEIPT = ROOT / "docs/provenance/anneessens_visual_blocker_256376389.md"


def _single(pattern: str, text: str, label: str) -> str:
    matches = re.findall(pattern, text, flags=re.MULTILINE)
    assert len(matches) == 1, f"{label} must appear exactly once; observed={len(matches)}"
    return matches[0]


def test_visual_blocker_is_bound_to_canonical_osm_source() -> None:
    conformance = CONFORMANCE.read_text(encoding="utf-8")
    receipt = RECEIPT.read_text(encoding="utf-8")

    target = _single(r'^const TARGET_OSM_ID := (\d+)$', conformance, "conformance TARGET_OSM_ID")
    source = _single(r'^const SOURCE_PATH := "res://([^"]+)"$', conformance, "conformance SOURCE_PATH")

    assert target == "256376389"
    assert source == "data/osm/vertical_slice_01.game.json"
    assert "Building_256376389_0" in receipt
    assert "OSM `256376389`" in receipt
    assert "`data/osm/vertical_slice_01.game.json`" in receipt
    assert "source identity proven=true" in receipt
    assert "geometry_change_authorized=false" in receipt
    assert "visual_acceptance=false" in receipt
    assert "destination_advertisable=false" in receipt
    assert "jouable_authorized=false" in receipt
