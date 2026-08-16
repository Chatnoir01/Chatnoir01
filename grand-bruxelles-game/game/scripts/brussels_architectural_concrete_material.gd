extends RefCounted
class_name BrusselsArchitecturalConcreteMaterial

## Reusable texture-free presentation for source-verified architectural concrete.
## The shader adds broad mineral tonal variation only. It does not encode
## formwork boards, aggregate size, joints, weather streaks or measured colour.

static func create(source_label: String) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 cool_color : source_color = vec4(0.38, 0.395, 0.39, 1.0);
uniform vec4 warm_color : source_color = vec4(0.58, 0.565, 0.53, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.86;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float a = sin(world_pos.x * 0.21 + world_pos.y * 0.31 + world_pos.z * 0.17);
    float b = sin(world_pos.x * 0.47 - world_pos.y * 0.13 + world_pos.z * 0.29 + 1.9);
    float c = sin(world_pos.x * 0.09 + world_pos.y * 0.57 - world_pos.z * 0.23 + 4.1);
    float mineral = clamp(0.5 + a * 0.16 + b * 0.09 + c * 0.07, 0.0, 1.0);
    vec3 concrete = mix(cool_color.rgb, warm_color.rgb, mineral);
    ALBEDO = concrete;
    ROUGHNESS = clamp(base_roughness + (0.5 - mineral) * 0.10, 0.68, 0.96);
    METALLIC = 0.0;
    SPECULAR = 0.24;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_meta("material_family", "brussels_source_verified_architectural_concrete")
    material.set_meta("source_label", source_label)
    material.set_meta("procedural_only", true)
    material.set_meta("formwork_pattern_authored", false)
    material.set_meta("aggregate_scale_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("geometry_changed", false)
    return material
