from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MATERIAL = ROOT / "game" / "scripts" / "brussels_osm_facade_articulation_material.gd"


def _source() -> str:
    return MATERIAL.read_text(encoding="utf-8")


def test_facade_articulation_roughness_contract() -> None:
    src = _source()
    assert 'const ASSET_FAMILY := "brussels_osm_facade_articulation_v1"' in src
    assert re.search(r"const PRESENTATION_REVISION\s*:=\s*2\b", src), "facade articulation presentation revision 2 missing"
    match = re.search(r"const ROUGHNESS_MICRO_VARIATION\s*:=\s*([0-9.]+)", src)
    assert match, "facade roughness micro-variation contract missing"
    strength = float(match.group(1))
    assert 0.0 < strength <= 0.04, f"roughness micro-variation must stay subtle, got {strength}"
    assert 'roughness_micro_variation' in src
    assert 'roughness_response' in src
    assert 'ROUGHNESS = clamp(roughness_value + roughness_micro_variation * roughness_response' in src
    assert 'ALBEDO = base_color.rgb * (1.0 + tint_strength * variation + orientation_variation);' in src
    assert 'roughness_microvariation_source_measured", false' in src
    assert 'surface_detail_semantics_claimed", false' in src
    assert 'geometry_changed", false' in src
    assert 'uses_external_textures", false' in src
    lowered = src.lower()
    for forbidden in ("mortar_pattern", "brick_course", "stone_joint", "window_grid", "weathering_pattern_claimed\", true"):
        assert forbidden not in lowered, f"invented facade semantics leaked into shared material: {forbidden}"


if __name__ == "__main__":
    test_facade_articulation_roughness_contract()
    print("FACADE_ARTICULATION_ROUGHNESS_CONTRACT_OK")
