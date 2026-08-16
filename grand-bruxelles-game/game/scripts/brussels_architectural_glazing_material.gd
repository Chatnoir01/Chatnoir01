extends RefCounted
class_name BrusselsArchitecturalGlazingMaterial

## Reusable texture-free presentation for source-verified architectural glazing.
## This deliberately models only a broad cool glass response. It does not
## author pane divisions, mullions, dirt, stickers, interiors or measured optics.

static func create(source_label: String) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 deep_tint : source_color = vec4(0.028, 0.055, 0.073, 1.0);
uniform vec4 sky_tint : source_color = vec4(0.18, 0.29, 0.35, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.16;
uniform float base_specular : hint_range(0.0, 1.0) = 0.82;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - facing, 2.6);
    float broad = 0.5 + 0.5 * sin(world_pos.y * 0.115 + world_pos.z * 0.018);
    float response = clamp(0.12 + fresnel * 0.70 + broad * 0.18, 0.0, 1.0);
    ALBEDO = mix(deep_tint.rgb, sky_tint.rgb, response);
    ROUGHNESS = clamp(base_roughness + broad * 0.055, 0.10, 0.24);
    METALLIC = 0.08;
    SPECULAR = base_specular;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_meta("material_family", "brussels_source_verified_architectural_glazing")
    material.set_meta("source_label", source_label)
    material.set_meta("procedural_only", true)
    material.set_meta("pane_layout_authored", false)
    material.set_meta("interior_authored", false)
    material.set_meta("exact_reflectance_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("geometry_changed", false)
    return material
