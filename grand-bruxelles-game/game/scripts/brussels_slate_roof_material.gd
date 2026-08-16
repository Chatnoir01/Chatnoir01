extends RefCounted
class_name BrusselsSlateRoofMaterial

## Texture-free presentation for roof surfaces whose slate identity is explicitly
## source-verified. It does not author slate units, rows, dormers, ridges or other
## architectural detail; only broad tone and roughness breakup is added.

static func create(
    cool_color: Color,
    warm_color: Color,
    base_roughness: float,
    source_label: String
) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 cool_color : source_color = vec4(0.055, 0.070, 0.085, 1.0);
uniform vec4 warm_color : source_color = vec4(0.165, 0.170, 0.175, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.72;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // Broad non-periodic-looking breakup only. No directional course or unit
    // grid is encoded, so this cannot imply undocumented slate dimensions.
    float a = sin(world_pos.x * 0.47 + world_pos.z * 0.31 + world_pos.y * 0.09);
    float b = sin(world_pos.x * 0.19 - world_pos.z * 0.63 + world_pos.y * 0.14 + 2.1);
    float c = sin(world_pos.x * 0.73 + world_pos.z * 0.11 - world_pos.y * 0.07 + 4.7);
    float breakup = clamp(0.5 + a * 0.18 + b * 0.11 + c * 0.08, 0.0, 1.0);
    vec3 slate = mix(cool_color.rgb, warm_color.rgb, breakup);
    ALBEDO = slate;
    ROUGHNESS = clamp(base_roughness + (0.5 - breakup) * 0.12, 0.56, 0.90);
    METALLIC = 0.0;
    SPECULAR = 0.32;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("cool_color", cool_color)
    material.set_shader_parameter("warm_color", warm_color)
    material.set_shader_parameter("base_roughness", base_roughness)
    material.set_meta("material_family", "brussels_source_verified_slate_roof")
    material.set_meta("source_label", source_label)
    material.set_meta("procedural_only", true)
    material.set_meta("roofing_unit_pattern_authored", false)
    material.set_meta("dormers_authored", false)
    material.set_meta("geometry_changed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    return material
