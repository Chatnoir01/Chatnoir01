extends RefCounted
class_name BrusselsStreetTreeMaterial

const MATERIAL_FAMILY := "brussels_street_tree_v1"
const MATERIAL_REVISION := 2
const SOURCE_LABEL := "OpenStreetMap contributors via Overpass API; existence/position only; ODbL-1.0"

static func _meta(material: Material, role: String, enhanced: bool) -> Material:
    material.set_meta("asset_family", MATERIAL_FAMILY)
    material.set_meta("material_revision", MATERIAL_REVISION if enhanced else 1)
    material.set_meta("tree_role", role)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    material.set_meta("species_claimed", false)
    material.set_meta("source_dimensions_measured", false)
    material.set_meta("season_claimed", false)
    material.set_meta("health_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("reflectance_claimed", false)
    material.set_meta("geometry_changed", false)
    return material

static func _legacy(color: Color, roughness: float, role: String) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = 0.0
    _meta(material, role, false)
    return material

static func create_legacy_materials() -> Dictionary:
    return {
        "foliage_dark": _legacy(Color(0.145, 0.245, 0.115, 1.0), 0.97, "foliage_dark"),
        "foliage_light": _legacy(Color(0.235, 0.345, 0.165, 1.0), 0.96, "foliage_light"),
        "trunk": _legacy(Color(0.175, 0.125, 0.085, 1.0), 0.99, "trunk"),
    }

static func _foliage_shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color;
uniform vec4 lift_color : source_color;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.96;
varying vec3 world_pos;
varying vec3 world_normal;
float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}
float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}
void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}
void fragment() {
    float broad = value_noise(world_pos.xz * 0.18 + vec2(world_pos.y * 0.11));
    float upward = clamp(world_normal.y * 0.5 + 0.5, 0.0, 1.0);
    float underside_lift = mix(0.19, 0.0, upward);
    float authored = clamp(0.24 + broad * 0.34 + upward * 0.30 + underside_lift, 0.0, 1.0);
    ALBEDO = mix(base_color.rgb, lift_color.rgb, authored);
    ROUGHNESS = clamp(roughness_value + (0.5 - broad) * 0.025, 0.90, 0.99);
    METALLIC = 0.0;
    SPECULAR = 0.12;
}
"""
    return shader

static func _trunk_shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 dark_color : source_color;
uniform vec4 light_color : source_color;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
    float authored = 0.5 + 0.18 * sin(world_pos.y * 2.7 + world_pos.x * 0.13 + world_pos.z * 0.17);
    ALBEDO = mix(dark_color.rgb, light_color.rgb, clamp(authored, 0.0, 1.0));
    ROUGHNESS = 0.985;
    METALLIC = 0.0;
    SPECULAR = 0.08;
}
"""
    return shader

static func _foliage(shader: Shader, base: Color, lift: Color, role: String) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("base_color", base)
    material.set_shader_parameter("lift_color", lift)
    material.set_shader_parameter("roughness_value", 0.965 if role == "foliage_dark" else 0.955)
    _meta(material, role, true)
    return material

static func _trunk() -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = _trunk_shader()
    material.set_shader_parameter("dark_color", Color(0.115, 0.078, 0.052, 1.0))
    material.set_shader_parameter("light_color", Color(0.245, 0.175, 0.112, 1.0))
    _meta(material, "trunk", true)
    return material

static func create_materials() -> Dictionary:
    var foliage_shader := _foliage_shader()
    return {
        "foliage_dark": _foliage(foliage_shader, Color(0.095, 0.175, 0.075, 1.0), Color(0.255, 0.390, 0.175, 1.0), "foliage_dark"),
        "foliage_light": _foliage(foliage_shader, Color(0.145, 0.235, 0.095, 1.0), Color(0.345, 0.475, 0.215, 1.0), "foliage_light"),
        "trunk": _trunk(),
    }
