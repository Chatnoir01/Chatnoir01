extends RefCounted
class_name BrusselsSharedRailMaterial

const FAMILY := "brussels_shared_rail_surface_v1"
const SOURCE_NAME := "OpenStreetMap contributors"
const SOURCE_LICENSE := "ODbL-1.0"

static func _stamp(material: Material, role: String) -> Material:
    material.set_meta("material_family", FAMILY)
    material.set_meta("surface_role", role)
    material.set_meta("geometry_changed", false)
    material.set_meta("source_name", SOURCE_NAME)
    material.set_meta("source_license", SOURCE_LICENSE)
    material.set_meta("source_material_identity_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("weathering_claimed", false)
    return material

static func create_rail_material() -> ShaderMaterial:
    var material := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

void fragment() {
    float broad = 0.5 + 0.5 * sin((WORLD_MATRIX * vec4(VERTEX, 1.0)).z * 0.115 + (WORLD_MATRIX * vec4(VERTEX, 1.0)).x * 0.071);
    vec3 base = mix(vec3(0.145, 0.158, 0.170), vec3(0.205, 0.218, 0.232), broad * 0.28);
    ALBEDO = base;
    METALLIC = 0.72;
    ROUGHNESS = mix(0.34, 0.48, broad);
}
"""
    material.shader = shader
    return _stamp(material, "rail") as ShaderMaterial

static func create_sleeper_material() -> ShaderMaterial:
    var material := ShaderMaterial.new()
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

void fragment() {
    vec3 world = (WORLD_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float broad = 0.5 + 0.5 * sin(world.x * 0.083 + world.z * 0.129);
    vec3 base = mix(vec3(0.185, 0.180, 0.168), vec3(0.255, 0.247, 0.228), broad * 0.36);
    ALBEDO = base;
    METALLIC = 0.0;
    ROUGHNESS = mix(0.86, 0.96, broad);
}
"""
    material.shader = shader
    return _stamp(material, "sleeper") as ShaderMaterial
