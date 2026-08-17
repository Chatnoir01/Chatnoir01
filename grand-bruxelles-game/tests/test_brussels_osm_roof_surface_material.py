from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATERIAL = ROOT / "game/scripts/brussels_osm_roof_surface_material.gd"
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"


def main() -> None:
    assert MATERIAL.exists(), "red-first witness: reusable OSM roof material missing"
    material_text = MATERIAL.read_text(encoding="utf-8")
    builder_text = BUILDER.read_text(encoding="utf-8")

    assert "class_name BrusselsOsmRoofSurfaceMaterial" in material_text
    assert "brussels_osm_roof_surface_v1" in material_text
    assert "authored_presentation_not_source_measurement" in material_text
    assert "material_identity_claimed" in material_text
    assert "measured_rgb_claimed" in material_text
    assert "geometry_changed" in material_text
    assert "BrusselsOsmRoofSurfaceMaterial" in builder_text
    assert "roof.depth = 0.20" in builder_text
    assert "roof.position = Vector3(center.x, height + 0.10, center.y)" in builder_text

    print("BRUSSELS_OSM_ROOF_SURFACE_MATERIAL_OK")


if __name__ == "__main__":
    main()
