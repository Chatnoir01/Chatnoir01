from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MATERIAL = ROOT / "game/scripts/brussels_asphalt_material_family.gd"
BUILDER = ROOT / "game/scripts/osm_city_builder.gd"


def main() -> None:
    assert MATERIAL.exists(), "RED: shared Brussels asphalt material family is missing"
    material = MATERIAL.read_text(encoding="utf-8")
    builder = BUILDER.read_text(encoding="utf-8")

    required_material_contract = [
        'const FAMILY_ID := "brussels_asphalt_presentation_v1"',
        'const SOURCE_PHOTOMETRY_CLAIMED := false',
        'const SOURCE_GEOMETRY_CHANGED := false',
        'func road_material(major: bool)',
        'procedural_original_asset',
        'urban.brussels',
    ]
    for needle in required_material_contract:
        assert needle in material, f"missing asphalt provenance/runtime contract: {needle}"

    assert 'BRUSSELS_ASPHALT_MATERIAL_FAMILY' in builder, "builder must load shared asphalt family"
    assert '_road_material = BRUSSELS_ASPHALT_MATERIAL_FAMILY.road_material(false)' in builder
    assert '_road_major_material = BRUSSELS_ASPHALT_MATERIAL_FAMILY.road_material(true)' in builder
    assert 'segment.position = (start + finish) * 0.5 + Vector3(0, 0.025, 0)' in builder, "road placement must stay unchanged"
    assert 'segment.size = Vector3(width, 0.10, length)' in builder, "road geometry must stay unchanged"
    print("SHARED_BRUSSELS_ASPHALT_CONTRACT_OK")


if __name__ == "__main__":
    main()
