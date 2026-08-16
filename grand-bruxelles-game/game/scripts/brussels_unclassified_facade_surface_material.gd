extends RefCounted
class_name BrusselsUnclassifiedFacadeSurfaceMaterial

## Reusable texture-free presentation for generic OSM building facades whose exact
## physical material is unknown. It preserves the existing authored base colour
## and adds only broad, low-frequency tonal/roughness variation. It does not
## claim brick, stone, concrete, masonry-unit dimensions or measured reflectance.

static func create(base_color: Color, base_roughness: float, source_label: String) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.45, 0.40, 0.35, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.91;

varying vec3 world_pos;

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float a = sin(world_pos.x * 0.115 + world_pos.y * 0.173 + world_pos.z * 0.091);
    float b = sin(world_pos.x * 0.257 - world_pos.y * 0.067 + world_pos.z * 0.149 + 2.4);
    float c = sin(world_pos.x * 0.051 + world_pos.y * 0.293 - world_pos.z * 0.119 + 4.7);
    float broad = clamp(0.5 + a * 0.17 + b * 0.10 + c * 0.06, 0.0, 1.0);
    float tone = mix(0.84, 1.11, broad);
    ALBEDO = clamp(base_color.rgb * tone, vec3(0.0), vec3(1.0));
    ROUGHNESS = clamp(base_roughness + (0.5 - broad) * 0.08, 0.76, 0.98);
    METALLIC = 0.0;
    SPECULAR = 0.22;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("base_color", base_color)
    material.set_shader_parameter("base_roughness", base_roughness)
    material.set_meta("material_family", "brussels_unclassified_facade_surface")
    material.set_meta("source_label", source_label)
    material.set_meta("source_verified_material_identity", false)
    material.set_meta("presentation_only", true)
    material.set_meta("procedural_only", true)
    material.set_meta("masonry_pattern_authored", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("geometry_changed", false)
    return material
