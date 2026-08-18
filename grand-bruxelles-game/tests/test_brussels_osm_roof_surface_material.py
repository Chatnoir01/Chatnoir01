from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"
MATERIAL = ROOT / "game/scripts/brussels_osm_roof_surface_material.gd"
RUNTIME = ROOT / "game/scripts/brussels_osm_roof_surface_runtime.gd"
PROJECT = ROOT / "project.godot"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(f"BRUSSELS_OSM_ROOF_SURFACE_FAIL: {message}")


def main() -> None:
    builder = BUILDER.read_text(encoding="utf-8")
    require('roof.name = "Roof_%s"' in builder, "production Roof_* geometry contract missing")
    require("roof.depth = 0.20" in builder, "production roof depth contract changed")
    require("height + 0.10" in builder, "production roof vertical placement contract changed")
    require("roof.material = _roof_material" in builder, "legacy roof material assignment changed")

    require(MATERIAL.exists(), "reusable roof surface material missing")
    require(RUNTIME.exists(), "reusable roof surface runtime missing")

    material = MATERIAL.read_text(encoding="utf-8")
    runtime = RUNTIME.read_text(encoding="utf-8")
    project = PROJECT.read_text(encoding="utf-8")

    require('MATERIAL_FAMILY := "brussels_osm_roof_surface_v1"' in material, "material family mismatch")
    require('LICENSE := "ODbL-1.0"' in material, "ODbL provenance missing")
    require('VISUAL_RECIPE_PROVENANCE := "authored_presentation_not_source_measurement"' in material, "authored provenance missing")
    for marker in [
        '"roof_material_claimed", false',
        '"roof_covering_claimed", false',
        '"exact_rgb_is_photometric_measurement", false',
        '"weathering_claimed", false',
        '"geometry_changed", false',
    ]:
        require(marker in material, f"truth marker missing: {marker}")

    require('child.name.begins_with("Roof_")' in runtime, "runtime is not limited to Roof_ nodes")
    require("CSGPolygon3D" in runtime, "runtime roof node type guard missing")
    require("set_enhanced_enabled" in runtime, "same-run A/B toggle missing")
    require("geometry_unchanged" in runtime, "geometry invariance metadata missing")
    require('BrusselsOsmRoofSurfaceRuntime="*res://game/scripts/brussels_osm_roof_surface_runtime.gd"' in project, "autoload wiring missing")

    print("BRUSSELS_OSM_ROOF_SURFACE_OK: legacy_geometry_locked=true family=brussels_osm_roof_surface_v1 provenance=ODbL-1.0")


if __name__ == "__main__":
    main()
