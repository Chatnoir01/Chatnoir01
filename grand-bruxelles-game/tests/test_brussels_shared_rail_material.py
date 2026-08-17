from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / "game/scripts/brussels_shared_rail_material.gd"
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"


def main() -> None:
    builder = BUILDER.read_text(encoding="utf-8")
    assert 'rail.size = Vector3(0.095, 0.09, length)' in builder
    assert 'perpendicular * 0.72 * side + Vector3(0, 0.105, 0)' in builder
    assert 'var spacing := 2.9' in builder
    assert 'sleeper.size = Vector3(2.15, 0.055, 0.22)' in builder
    assert 'BRUSSELS_SHARED_RAIL_MATERIAL_FAMILY' in builder
    assert ASSET.exists(), "red-first witness: reusable shared rail material missing"
    text = ASSET.read_text(encoding="utf-8")
    assert 'brussels_shared_rail_surface_v1' in text
    assert 'geometry_changed' in text
    assert 'source_material_identity_claimed' in text
    assert 'exact_rgb_is_photometric_measurement' in text
    assert 'OpenStreetMap contributors' in text
    assert 'ODbL-1.0' in text
    print("BRUSSELS_SHARED_RAIL_MATERIAL_OK")


if __name__ == "__main__":
    main()
