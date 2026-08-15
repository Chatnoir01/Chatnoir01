extends RefCounted

# Authored reusable post-rain presentation for already source-backed paved surfaces.
# It does not claim a measured weather state, puddle depth, material chemistry, or
# exact reflectance. Broad world-space modulation avoids high-frequency texture noise.

const SHADER_CODE := """
shader_type spatial;
render_mode cull_disabled;

uniform vec4 dry_color : source_color = vec4(0.4, 0.4, 0.4, 1.0);
uniform float dry_roughness : hint_range(0.0, 1.0) = 0.94;
uniform float wetness : hint_range(0.0, 1.0) = 0.62;

varying vec2 world_xz;

void vertex() {
    vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_xz = world_position.xz;
}

void fragment() {
    float broad_a = sin(world_xz.x * 0.19 + world_xz.y * 0.11);
    float broad_b = sin(world_xz.x * 0.071 - world_xz.y * 0.137 + 1.7);
    float patch = clamp(0.5 + broad_a * 0.22 + broad_b * 0.18, 0.0, 1.0);
    float local_wetness = clamp(wetness * mix(0.56, 1.0, patch), 0.0, 1.0);
    vec3 wet_color = dry_color.rgb * 0.72;
    ALBEDO = mix(dry_color.rgb, wet_color, local_wetness);
    ROUGHNESS = mix(dry_roughness, 0.28, local_wetness);
    SPECULAR = mix(0.5, 0.78, local_wetness);
    METALLIC = 0.0;
}
"""

static func make(base_color: Color, dry_roughness: float, wetness_strength: float) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = SHADER_CODE
    var material := ShaderMaterial.new()
    material.shader = shader
    var clamped := clampf(wetness_strength, 0.0, 1.0)
    material.set_shader_parameter("dry_color", base_color)
    material.set_shader_parameter("dry_roughness", clampf(dry_roughness, 0.0, 1.0))
    material.set_shader_parameter("wetness", clamped)
    material.set_meta("brussels_post_rain", true)
    material.set_meta("wetness_strength", clamped)
    material.set_meta("presentation_authored", true)
    return material
