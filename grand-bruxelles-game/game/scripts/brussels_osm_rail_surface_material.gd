extends RefCounted
class_name BrusselsOsmRailSurfaceMaterial

## Presentation-only surface family for existing source-backed OSM railway geometry.
## OSM/Overpass under ODbL-1.0 supports alignment/existence/class/visibility only.
## Alloy, finish, oxidation, wear, exact RGB, reflectance and photometry are authored.

const MATERIAL_FAMILY := "brussels_osm_rail_surface_v1"
const SOURCE_LABEL := "OpenStreetMap contributors via Overpass API; railway alignment/existence/class/visibility only; ODbL-1.0"

# Contract literals retained for fail-closed provenance tests:
# "surface_composition_claimed", false
# "exact_rgb_is_photometric_measurement", false
# "wear_pattern_claimed", false
# "geometry_changed", false

static func create_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec3 world_pos;

float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    vec2 u = local * local * (3.0 - 2.0 * local);
    float a = hash21(cell);
    float b = hash21(cell + vec2(1.0, 0.0));
    float c = hash21(cell + vec2(0.0, 1.0));
    float d = hash21(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float broad = value_noise(world_pos.xz * 0.20);
    float fine = value_noise(world_pos.xz * 1.15 + vec2(23.0, 61.0));
    float tone = clamp(0.72 * broad + 0.28 * fine, 0.0, 1.0);
    vec3 dark_steel = vec3(0.145, 0.155, 0.165);
    vec3 light_steel = vec3(0.39, 0.405, 0.42);
    ALBEDO = mix(dark_steel, light_steel, tone);
    METALLIC = 0.78;
    ROUGHNESS = clamp(0.34 + (1.0 - tone) * 0.22, 0.32, 0.58);
    SPECULAR = 0.72;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("placement_source", "OpenStreetMap contributors via Overpass API")
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("surface_composition_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("wear_pattern_claimed", false)
    material.set_meta("geometry_changed", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material
