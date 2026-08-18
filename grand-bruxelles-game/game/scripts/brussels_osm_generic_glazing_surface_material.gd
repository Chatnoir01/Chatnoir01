extends RefCounted
class_name BrusselsOsmGenericGlazingSurfaceMaterial

const MATERIAL_FAMILY := "brussels_osm_generic_glazing_surface_v1"
const SOURCE_LABEL := "OpenStreetMap contributors via Overpass API; generic building footprint/type context only; ODbL-1.0"

static func _shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 dark_color : source_color = vec4(0.028, 0.060, 0.078, 1.0);
uniform vec4 light_color : source_color = vec4(0.090, 0.145, 0.168, 1.0);
uniform float roughness_base : hint_range(0.0, 1.0) = 0.22;
uniform float metallic_base : hint_range(0.0, 1.0) = 0.10;

varying vec3 world_pos;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = hash21(i);
    float b = hash21(i + vec2(1.0, 0.0));
    float c = hash21(i + vec2(0.0, 1.0));
    float d = hash21(i + vec2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    float broad = value_noise(world_pos.xz * 0.055 + vec2(13.0, 29.0));
    float vertical = clamp(0.45 + 0.06 * sin(world_pos.y * 0.42), 0.0, 1.0);
    float tone = clamp(0.70 * broad + 0.30 * vertical, 0.0, 1.0);
    ALBEDO = mix(dark_color.rgb, light_color.rgb, tone);
    ROUGHNESS = clamp(roughness_base + (0.5 - tone) * 0.06, 0.12, 0.36);
    METALLIC = metallic_base;
    SPECULAR = 0.55;
}
"""
    return shader

static func _material(shader: Shader, dark: Color, light: Color, roughness: float, metallic: float, role: String) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("dark_color", dark)
    material.set_shader_parameter("light_color", light)
    material.set_shader_parameter("roughness_base", roughness)
    material.set_shader_parameter("metallic_base", metallic)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("glazing_role", role)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("geometry_changed", false)
    material.set_meta("glass_composition_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("reflectance_is_measured", false)
    material.set_meta("window_identity_source_claimed", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material

static func create_materials() -> Dictionary:
    var shader := _shader()
    return {
        "window": _material(shader, Color(0.026, 0.055, 0.074, 1.0), Color(0.090, 0.145, 0.168, 1.0), 0.24, 0.08, "generic_window"),
        "shop": _material(shader, Color(0.035, 0.075, 0.090, 1.0), Color(0.105, 0.175, 0.190, 1.0), 0.20, 0.10, "generic_shopfront"),
    }
