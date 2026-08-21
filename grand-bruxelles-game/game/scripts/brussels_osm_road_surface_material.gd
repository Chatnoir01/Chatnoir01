extends RefCounted
class_name BrusselsOsmRoadSurfaceMaterial

## Reusable texture-free presentation family for the existing OSM road meshes.
## The committed OSM corridor snapshot proves road geometry, OSM id, class and
## width, but it does not retain a surface-composition tag. These colours and
## tonal variations are therefore deterministic authored presentation values,
## not claims about asphalt composition, aggregate, wear or measured photometry.

const MATERIAL_FAMILY := "brussels_osm_road_surface_v1"
const PRESENTATION_REVISION := 2
const SOURCE_LABEL := "OpenStreetMap contributors via Overpass API; road placement/class/width only; ODbL-1.0"

static func _shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 dark_color : source_color = vec4(0.085, 0.090, 0.095, 1.0);
uniform vec4 light_color : source_color = vec4(0.135, 0.140, 0.145, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.95;
uniform float micro_grain_strength : hint_range(0.0, 1.0) = 0.35;
uniform float micro_grain_frequency : hint_range(0.5, 16.0) = 7.0;

varying vec3 world_pos;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
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
    float a = value_noise(rotate2(xz, 0.23) * micro_grain_frequency + vec2(29.0, 83.0));
    float b = value_noise(rotate2(xz, -0.61) * (micro_grain_frequency * 1.91) + vec2(113.0, 17.0));
    return clamp(a * 0.62 + b * 0.38, 0.0, 1.0);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 xz = world_pos.xz;
    float broad = value_noise(xz * 0.085);
    float medium = value_noise(xz * 0.33 + vec2(17.0, 41.0));
    float authored_tone = clamp(broad * 0.72 + medium * 0.28, 0.0, 1.0);
    vec3 base = mix(dark_color.rgb, light_color.rgb, authored_tone);

    // Authored, isotropic, non-semantic fine grain. The high exponent keeps
    // stronger flecks sparse instead of creating lane-like bands or wear cues.
    float raw_grain = fine_grain(xz);
    float centered = raw_grain - 0.5;
    float normalized = clamp(abs(centered) * 2.0, 0.0, 1.0);
    float shaped = pow(normalized, 1.65);
    float grain = sign(centered) * shaped * 0.5 * micro_grain_strength;
    ALBEDO = clamp(base + vec3(grain * 0.18), vec3(0.0), vec3(1.0));
    ROUGHNESS = clamp(base_roughness + (0.5 - authored_tone) * 0.035 - grain * 0.050, 0.88, 0.99);
    METALLIC = 0.0;
    SPECULAR = 0.16;
}
"""
    return shader

static func _material(shader: Shader, dark: Color, light: Color, roughness: float, role: String) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("dark_color", dark)
    material.set_shader_parameter("light_color", light)
    material.set_shader_parameter("base_roughness", roughness)
    material.set_shader_parameter("micro_grain_strength", 0.35)
    material.set_shader_parameter("micro_grain_frequency", 7.0)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("presentation_revision", PRESENTATION_REVISION)
    material.set_meta("road_role", role)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("placement_and_class_source", "OpenStreetMap contributors via Overpass API")
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("procedural_only", true)
    material.set_meta("surface_composition_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("aggregate_scale_claimed", false)
    material.set_meta("wear_pattern_claimed", false)
    material.set_meta("crack_pattern_claimed", false)
    material.set_meta("road_marking_claimed", false)
    material.set_meta("geometry_changed", false)
    material.set_meta("authored_nonsemantic_microtexture", true)
    material.set_meta("microtexture_scale_source_measured", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material

static func create_materials() -> Dictionary:
    var shader := _shader()
    return {
        "regular": _material(
            shader,
            Color(0.082, 0.087, 0.092, 1.0),
            Color(0.135, 0.140, 0.145, 1.0),
            0.96,
            "regular"
        ),
        "major": _material(
            shader,
            Color(0.060, 0.065, 0.070, 1.0),
            Color(0.112, 0.117, 0.122, 1.0),
            0.95,
            "major"
        ),
    }
