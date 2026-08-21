extends RefCounted
class_name BrusselsOsmSidewalkSurfaceMaterial

## Reusable texture-free presentation family for the existing OSM-derived
## sidewalk meshes generated beside drivable roads in the current vertical slice.
## The committed corridor snapshot proves road placement/class/width, while the
## sidewalk widths and presentation recipe are authored runtime conventions.
## This material therefore makes no claim about real paving composition, slab
## dimensions, aggregate, wear, exact colour, or measured photometry.

const MATERIAL_FAMILY := "brussels_osm_sidewalk_surface_v1"
const PRESENTATION_REVISION := 2
const SOURCE_LABEL := "OpenStreetMap contributors via Overpass API; adjacent road placement/class/width only; ODbL-1.0"

static func _shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 dark_color : source_color = vec4(0.325, 0.316, 0.297, 1.0);
uniform vec4 light_color : source_color = vec4(0.438, 0.426, 0.400, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.93;
uniform float micro_grain_strength : hint_range(0.0, 1.0) = 0.17;
uniform float micro_grain_frequency : hint_range(0.5, 12.0) = 5.0;

varying vec3 world_pos;

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    vec2 smooth_local = local * local * (3.0 - 2.0 * local);
    float a = hash21(cell);
    float b = hash21(cell + vec2(1.0, 0.0));
    float c = hash21(cell + vec2(0.0, 1.0));
    float d = hash21(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, smooth_local.x), mix(c, d, smooth_local.x), smooth_local.y);
}

vec2 rotate2(vec2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return mat2(vec2(c, s), vec2(-s, c)) * p;
}

float fine_grain(vec2 xz) {
    float a = value_noise(rotate2(xz, 0.19) * micro_grain_frequency + vec2(71.0, 13.0));
    float b = value_noise(rotate2(xz, -0.47) * (micro_grain_frequency * 1.73) + vec2(5.0, 97.0));
    return clamp(a * 0.64 + b * 0.36, 0.0, 1.0);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 xz = world_pos.xz;
    vec2 p0 = rotate2(xz, 0.61);
    vec2 warp = vec2(
        value_noise(rotate2(xz, -0.37) * 0.055 + vec2(19.0, 7.0)),
        value_noise(rotate2(xz, 0.83) * 0.061 + vec2(3.0, 31.0))
    ) - vec2(0.5);
    vec2 warped = p0 + warp * 4.3;
    float broad = value_noise(warped * 0.075 + vec2(11.0, 23.0));
    float secondary = value_noise(rotate2(warped, -0.92) * 0.145 + vec2(41.0, 5.0));
    float authored_tone = clamp(broad * 0.72 + secondary * 0.28, 0.0, 1.0);
    float raw_grain = fine_grain(xz);
    float grain = (raw_grain - 0.5) * micro_grain_strength;
    // Keep the broad authored tone intact, but give close-player pixels enough
    // local contrast to survive 8-bit output and compression. This is a
    // presentation recipe only: it does not encode paving units or geometry.
    float micro_contrast = grain * 0.75;
    vec3 base = mix(dark_color.rgb, light_color.rgb, authored_tone);
    ALBEDO = base * (1.0 + micro_contrast);
    ROUGHNESS = clamp(base_roughness + (0.5 - authored_tone) * 0.032 - grain * 0.040, 0.88, 0.98);
    METALLIC = 0.0;
    SPECULAR = 0.12;
}
"""
    return shader

static func create_material() -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = _shader()
    material.set_shader_parameter("dark_color", Color(0.325, 0.316, 0.297, 1.0))
    material.set_shader_parameter("light_color", Color(0.438, 0.426, 0.400, 1.0))
    material.set_shader_parameter("base_roughness", 0.93)
    material.set_shader_parameter("micro_grain_strength", 0.17)
    material.set_shader_parameter("micro_grain_frequency", 5.0)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("presentation_revision", PRESENTATION_REVISION)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("placement_source", "OpenStreetMap contributors via Overpass API")
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("procedural_only", true)
    material.set_meta("surface_composition_claimed", false)
    material.set_meta("paving_unit_dimensions_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("wear_pattern_claimed", false)
    material.set_meta("geometry_changed", false)
    material.set_meta("authored_nonsemantic_microtexture", true)
    material.set_meta("microtexture_scale_source_measured", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material
