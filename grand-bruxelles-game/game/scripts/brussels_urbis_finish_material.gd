extends RefCounted
class_name BrusselsUrbisFinishMaterial

## Reusable texture-free presentation family for UrbIS-owned geometry.
## UrbIS owns geometry/placement only. All colour, roughness and tonal variation
## below are authored presentation values, never a claim about measured material.

const MATERIAL_FAMILY := "brussels_urbis_finish_v1"
const SOURCE_LABEL := "UrbIS geometry/placement only; finish appearance authored; no material measurement claim"

static func _shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 dark_color : source_color = vec4(0.10, 0.10, 0.10, 1.0);
uniform vec4 light_color : source_color = vec4(0.18, 0.18, 0.18, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.94;
uniform float scale_a = 0.08;
uniform float scale_b = 0.31;

varying vec3 world_pos;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    vec2 s = local * local * (3.0 - 2.0 * local);
    float a = hash21(cell);
    float b = hash21(cell + vec2(1.0, 0.0));
    float c = hash21(cell + vec2(0.0, 1.0));
    float d = hash21(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, s.x), mix(c, d, s.x), s.y);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float a = value_noise(world_pos.xz * scale_a);
    float b = value_noise(world_pos.xz * scale_b + vec2(17.0, 41.0));
    float tone = clamp(a * 0.72 + b * 0.28, 0.0, 1.0);
    ALBEDO = mix(dark_color.rgb, light_color.rgb, tone);
    ROUGHNESS = clamp(base_roughness + (0.5 - tone) * 0.04, 0.84, 0.99);
    METALLIC = 0.0;
    SPECULAR = 0.15;
}
"""
    return shader

static func _material(role: String, dark: Color, light: Color, roughness: float, scale_a: float, scale_b: float) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = _shader()
    material.set_shader_parameter("dark_color", dark)
    material.set_shader_parameter("light_color", light)
    material.set_shader_parameter("base_roughness", roughness)
    material.set_shader_parameter("scale_a", scale_a)
    material.set_shader_parameter("scale_b", scale_b)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("finish_role", role)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("geometry_source", "UrbIS")
    material.set_meta("material_identity_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("surface_composition_claimed", false)
    material.set_meta("weathering_claimed", false)
    material.set_meta("geometry_changed", false)
    return material

static func create_road() -> ShaderMaterial:
    return _material("street_surface", Color(0.075, 0.080, 0.085, 1.0), Color(0.145, 0.150, 0.155, 1.0), 0.96, 0.085, 0.34)

static func create_facade() -> ShaderMaterial:
    return _material("generic_building", Color(0.43, 0.405, 0.37, 1.0), Color(0.66, 0.62, 0.56, 1.0), 0.92, 0.055, 0.17)
