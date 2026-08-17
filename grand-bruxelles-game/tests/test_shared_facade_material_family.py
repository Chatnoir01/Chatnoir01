from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"
FAMILY = ROOT / "game/scripts/brussels_facade_material_family.gd"


def main() -> None:
    builder = BUILDER.read_text(encoding="utf-8")
    assert FAMILY.exists(), "missing reusable brussels_facade_material_family.gd"
    family = FAMILY.read_text(encoding="utf-8")

    assert 'preload("res://game/scripts/brussels_facade_material_family.gd")' in builder
    assert "BRUSSELS_FACADE_MATERIAL_FAMILY.create_family()" in builder
    assert 'FAMILY_ID := "brussels_facade_presentation_v1"' in family
    assert '"source_surface_semantics_claimed", false' in family
    assert '"source_geometry_owner", "osm_city_builder_existing_footprints"' in family
    assert '"source_license", "ODbL-1.0"' in family
    assert '"authored_presentation_values", true' in family
    assert "uv1_triplanar = true" in family
    assert "albedo_texture" in family

    # This shared lot is presentation-only: it must not own or alter placement.
    forbidden = ["CSGPolygon3D", "position =", "polygon =", "depth =", "rotation_degrees"]
    for token in forbidden:
        assert token not in family, f"material family must not own geometry: {token}"

    print("SHARED_FACADE_MATERIAL_FAMILY_OK")


if __name__ == "__main__":
    main()
