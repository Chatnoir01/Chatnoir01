extends RefCounted
class_name BrusselsCorridorGenericGlazingMaterial

## Texture-free presentation for the already-generated generic corridor window and
## shopfront glass meshes. The surrounding corridor building context is backed by
## OpenStreetMap contributors under ODbL-1.0; individual pane placement and every
## optical/material parameter here remain authored presentation conventions.
const FAMILY := "brussels_corridor_generic_glazing_v1"

static func create(base_color: Color, base_roughness: float, base_metallic: float, phase: float, source_label: String) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_tint : source_color = vec4(0.06, 0.10, 0.13, 1.0);
uniform float authored_roughness : hint_range(0.0, 1.0) = 0.26;
uniform float authored_metallic : hint_range(0.0, 1.0) = 0.12;
uniform float authored_phase = 0.0;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fresnel = pow(1.0 - facing, 2.2);
    float broad_vertical = 0.5 + 0.5 * sin(world_pos.y * 0.19 + world_pos.x * 0.021 + world_pos.z * 0.017 + authored_phase);
    float broad_cross = 0.5 + 0.5 * sin(world_pos.y * 0.071 - world_pos.x * 0.013 + authored_phase * 1.7);
    float authored_response = clamp(0.76 + broad_vertical * 0.12 + broad_cross * 0.05 + fresnel * 0.19, 0.68, 1.12);
    ALBEDO = clamp(base_tint.rgb * authored_response, vec3(0.0), vec3(1.0));
    ROUGHNESS = clamp(authored_roughness + (broad_vertical - 0.5) * 0.08, 0.12, 0.42);
    METALLIC = authored_metallic;
    SPECULAR = clamp(0.58 + fresnel * 0.20, 0.0, 1.0);
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("base_tint", base_color)
    material.set_shader_parameter("authored_roughness", base_roughness)
    material.set_shader_parameter("authored_metallic", base_metallic)
    material.set_shader_parameter("authored_phase", phase)
    material.set_meta("material_family", FAMILY)
    material.set_meta("source_label", source_label)
    material.set_meta("source", "OpenStreetMap contributors")
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("geometry_changed", false)
    material.set_meta("material_identity_claimed", false)
    material.set_meta("glass_type_claimed", false)
    material.set_meta("pane_placement_source_claimed", false)
    material.set_meta("exact_reflectance_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("interior_authored", false)
    material.set_meta("procedural_presentation_only", true)
    return material
