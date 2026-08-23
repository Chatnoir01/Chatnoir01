import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OSM_PATH = ROOT / "data/osm/vertical_slice_01.game.json"
OFFICIAL_MANIFEST_PATH = ROOT / "data/provenance/brussels_mobility_sidewalk_corridor_geometry_manifest.json"
GEOREF_PATH = ROOT / "data/provenance/brussels_sidewalk_overlap_georef.json"


def fail(message: str) -> None:
    raise AssertionError(message)


def load_json(path: Path) -> dict:
    if not path.exists():
        fail(f"required file missing: {path.relative_to(ROOT)}")
    with path.open("r", encoding="utf-8") as handle:
        value = json.load(handle)
    if not isinstance(value, dict):
        fail(f"expected object in {path.relative_to(ROOT)}")
    return value


def test_overlap_requires_source_backed_georef() -> None:
    osm = load_json(OSM_PATH)
    official = load_json(OFFICIAL_MANIFEST_PATH)

    if osm.get("format") != "grand-bruxelles-osm-v1":
        fail("unexpected OSM game payload format")
    origin = osm.get("origin")
    if not isinstance(origin, dict) or set(origin) != {"lat", "lon"}:
        fail("OSM local-space origin contract missing")

    if official.get("crs") != "EPSG:31370":
        fail("official sidewalk persisted geometry must remain Lambert72 EPSG:31370")
    if int(official.get("feature_count", 0)) != 3158:
        fail("official sidewalk feature count drifted before overlap measurement")

    if not GEOREF_PATH.exists():
        fail("source-backed game-local <-> EPSG:31370 georef contract missing; horizontal overlap is not authorized")

    georef = load_json(GEOREF_PATH)
    if georef.get("schema") != "grand-bruxelles-sidewalk-overlap-georef-v1":
        fail("unexpected sidewalk overlap georef schema")
    if georef.get("game_space") != "vertical_slice_01.game local X/Z meters":
        fail("game-space identity mismatch")
    if georef.get("official_space") != "EPSG:31370 Lambert72 XY meters":
        fail("official-space identity mismatch")
    if georef.get("horizontal_only") is not True:
        fail("overlap georef must be horizontal-only")
    if georef.get("curb_height_authorized") is not False:
        fail("georef must not authorize curb-height inference")
    if georef.get("vertical_profile_authorized") is not False:
        fail("georef must not authorize vertical-profile inference")
    if georef.get("runtime_geometry_authorized") is not False:
        fail("QA georef must not authorize runtime geometry")

    method = georef.get("method")
    if not isinstance(method, dict):
        fail("georef method missing")
    if method.get("kind") not in {"validated_affine_2d", "validated_crs_pipeline"}:
        fail("georef method is not an approved validated transform")
    controls = method.get("control_points")
    if not isinstance(controls, list) or len(controls) < 3:
        fail("at least three independently validated control points are required")
    if float(method.get("max_horizontal_residual_m", 999.0)) > 0.50:
        fail("georef residual exceeds 0.50 m overlap-QA tolerance")
    if not str(method.get("evidence_sha256", "")).startswith("sha256:"):
        fail("georef evidence digest missing")


if __name__ == "__main__":
    test_overlap_requires_source_backed_georef()
    print("OFFICIAL_SIDEWALK_OVERLAP_GEOREF_OK")
