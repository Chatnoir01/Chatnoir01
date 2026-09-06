import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "data" / "osm" / "vertical_slice_01.game.json"
BUILDER = ROOT / "game" / "scripts" / "osm_city_builder.gd"
ANNEESSENS_ID = "anneessens"
AUTOMATIC_ROAD_ID = 1382734012


def _canonical_anchor() -> tuple[float, float]:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    anchors = data.get("corridor", {}).get("anchors", [])
    matches = [item for item in anchors if item.get("id") == ANNEESSENS_ID]
    assert len(matches) == 1, "canonical Anneessens corridor anchor must be unique"
    anchor = matches[0]
    return float(anchor["x"]), float(anchor["z"])


def _automatic_road() -> dict:
    data = json.loads(SOURCE.read_text(encoding="utf-8"))
    matches = [road for road in data.get("roads", []) if int(road.get("osm_id", 0)) == AUTOMATIC_ROAD_ID]
    assert len(matches) == 1, "representative automatic Anneessens road must be unique"
    return matches[0]


def _builder_anchor() -> tuple[float, float]:
    text = BUILDER.read_text(encoding="utf-8")
    match = re.search(
        r"const ANNEESSENS_ANCHOR := Vector2\(([-0-9.]+),\s*([-0-9.]+)\)",
        text,
    )
    assert match, "osm_city_builder.gd must expose the bounded Anneessens detail anchor"
    return float(match.group(1)), float(match.group(2))


def test_anneessens_detail_anchor_matches_canonical_corridor_source() -> None:
    assert _builder_anchor() == _canonical_anchor()


def test_canonical_anchor_is_supported_by_representative_automatic_road() -> None:
    anchor_x, anchor_z = _canonical_anchor()
    points = _automatic_road().get("points", [])
    assert len(points) >= 2
    nearest_vertex_m = min(
        ((float(point[0]) - anchor_x) ** 2 + (float(point[1]) - anchor_z) ** 2) ** 0.5
        for point in points
    )
    # Source-backed sanity guard only: this must stay on the Place Anneessens road,
    # not drift to a different Lemonnier segment. It does not change geometry/spawn.
    assert nearest_vertex_m < 30.0
