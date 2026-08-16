extends RefCounted
class_name BrusselsBlueStoneMaterial

## Reusable, texture-free mineral presentation for source-verified Belgian blue
## stone surfaces. It does not author masonry joints, chisel patterns, panel
## dimensions or location-specific ornament; only broad mineral tone and
## roughness variation are added so large verified surfaces stop reading flat.

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

uniform vec4 cool_color : source_color = vec4(0.115, 0.145, 0.165, 1.0);
uniform vec4 warm_color : source_color = vec4(0.245, 0.265, 0.275, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.78;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // Broad mineral breakup only; no grid or directional tooling pattern is
    // encoded, so the shader cannot imply undocumented stone block dimensions.
    float a = sin(world_pos.x * 0.29 + world_pos.y * 0.19 + world_pos.z * 0.37);
    float b = sin(world_pos.x * 0.61 - world_pos.y * 0.09 + world_pos.z * 0.17 + 1.7);
    float c = sin(world_pos.x * 0.11 + world_pos.y * 0.33 - world_pos.z * 0.43 + 4.4);
    float mineral = clamp(0.5 + a * 0.18 + b * 0.11 + c * 0.09, 0.0, 1.0);
    vec3 stone = mix(cool_color.rgb, warm_color.rgb, mineral);
    ALBEDO = stone;
    ROUGHNESS = clamp(base_roughness + (0.5 - mineral) * 0.12, 0.58, 0.94);
    METALLIC = 0.0;
    SPECULAR = 0.30;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("cool_color", cool_color)
    material.set_shader_parameter("warm_color", warm_color)
    material.set_shader_parameter("base_roughness", base_roughness)
    material.set_meta("material_family", "brussels_source_verified_blue_stone")
    material.set_meta("source_label", source_label)
    material.set_meta("procedural_only", true)
    material.set_meta("masonry_joints_authored", false)
    material.set_meta("tooling_pattern_authored", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("geometry_changed", false)
    return material
