extends RefCounted
class_name BrusselsWhiteStoneMaterial

## Reusable, texture-free mineral presentation for source-verified Brussels
## white-stone facades. It intentionally avoids masonry joints, openings or
## location-specific ornament: only broad mineral tone/roughness variation is
## authored so verified Gobertange/Euville/white-stone identities stop reading
## as flat clay at normal gameplay distance.

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

uniform vec4 cool_color : source_color = vec4(0.74, 0.72, 0.67, 1.0);
uniform vec4 warm_color : source_color = vec4(0.84, 0.82, 0.76, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.80;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    // Broad-band mineral breakup only. Frequencies are deliberately larger
    // than architectural joints so this cannot imply stone block dimensions.
    float a = sin(world_pos.x * 0.31 + world_pos.y * 0.17 + world_pos.z * 0.23);
    float b = sin(world_pos.x * 0.57 - world_pos.y * 0.11 + world_pos.z * 0.41 + 1.9);
    float c = sin(world_pos.x * 0.13 + world_pos.y * 0.29 - world_pos.z * 0.19 + 4.2);
    float mineral = clamp(0.5 + a * 0.11 + b * 0.07 + c * 0.08, 0.0, 1.0);
    vec3 stone = mix(cool_color.rgb, warm_color.rgb, mineral);
    ALBEDO = stone;
    ROUGHNESS = clamp(base_roughness + (0.5 - mineral) * 0.10, 0.62, 0.96);
    METALLIC = 0.0;
    SPECULAR = 0.28;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("cool_color", cool_color)
    material.set_shader_parameter("warm_color", warm_color)
    material.set_shader_parameter("base_roughness", base_roughness)
    material.set_meta("material_family", "brussels_source_verified_white_stone")
    material.set_meta("source_label", source_label)
    material.set_meta("procedural_only", true)
    material.set_meta("masonry_joints_authored", false)
    material.set_meta("openings_authored", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    return material
