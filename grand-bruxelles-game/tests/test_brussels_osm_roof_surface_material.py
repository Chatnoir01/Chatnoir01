from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATERIAL = ROOT / "game/scripts/brussels_osm_roof_surface_material.gd"
RUNTIME = ROOT / "game/scripts/brussels_osm_roof_surface_runtime.gd"
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"
PROJECT = ROOT / "project.godot"


def main() -> None:
    if not MATERIAL.exists():
        raise SystemExit("red-first witness: reusable OSM roof material missing")
    if not RUNTIME.exists():
        raise SystemExit("BRUSSELS_OSM_ROOF_SURFACE_FAIL runtime missing")

    material = MATERIAL.read_text(encoding="utf-8")
    runtime = RUNTIME.read_text(encoding="utf-8")
    builder = BUILDER.read_text(encoding="utf-8")
    project = PROJECT.read_text(encoding="utf-8")

    required_material = [
        'class_name BrusselsOsmRoofSurfaceMaterial',
        'MATERIAL_FAMILY := "brussels_osm_roof_surface_v1"',
        'ODbL-1.0',
        'roof_material_claimed',
        'exact_rgb_is_photometric_measurement',
        'weathering_claimed',
        'geometry_changed',
        'authored_presentation_not_source_measurement',
    ]
    for token in required_material:
        assert token in material, token

    required_runtime = [
        'begins_with("Roof_")',
        'generic_osm_roof',
        'geometry_unchanged',
        'set_enhanced_enabled',
        'BRUSSELS_OSM_ROOF_SURFACE_READY',
    ]
    for token in required_runtime:
        assert token in runtime, token

    # Hard geometry invariants from production builder: this lot is material-only.
    assert 'roof.depth = 0.20' in builder
    assert 'roof.position = Vector3(center.x, height + 0.10, center.y)' in builder
    assert 'BrusselsOsmRoofSurfaceRuntime="*res://game/scripts/brussels_osm_roof_surface_runtime.gd"' in project

    print("BRUSSELS_OSM_ROOF_SURFACE_CONTRACT_OK")


if __name__ == "__main__":
    main()
