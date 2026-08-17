extends RefCounted
class_name BrusselsOsmFacadeSurfaceMaterial

## Reusable texture-free presentation family for generic OSM building walls.
## OSM supports the footprint/placement/kind data consumed by the production
## builder, but the committed vertical-slice snapshot does not retain a
## building:material claim. The existing six base colours and all procedural
## tonal variation below are therefore authored presentation values only.
## This family does not claim brick, stone, concrete, render, paint, measured
## colour, facade-unit scale, weathering, or photometric roughness.

const MATERIAL_FAMILY := "brussels_osm_facade_surface_v1"
const SOURCE_LABEL := "OpenStreetMap contributors via Overpass API; generic building footprint/placement/kind only; ODbL-1.0"

static func _shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.45, 0.40, 0.34, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.91;

varying vec3 world_pos;

float hash31(vec3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float value_noise3(vec3 p) {
    vec3 i = floor(p);
    vec3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = hash31(i + vec3(0.0, 0.0, 0.0));
    float n100 = hash31(i + vec3(1.0, 0.0, 0.0));
    float n010 = hash31(i + vec3(0.0, 1.0, 0.0));
    float n110 = hash31(i + vec3(1.0, 1.0, 0.0));
    float n001 = hash31(i + vec3(0.0, 0.0, 1.0));
    float n101 = hash31(i + vec3(1.0, 0.0, 1.0));
    float n011 = hash31(i + vec3(0.0, 1.0, 1.0));
    float n111 = hash31(i + vec3(1.0, 1.0, 1.0));
    float nx00 = mix(n000, n100, f.x);
    float nx10 = mix(n010, n110, f.x);
    float nx01 = mix(n001, n101, f.x);
    float nx11 = mix(n011, n111, f.x);
    return mix(mix(nx00, nx10, f.y), mix(nx01, nx11, f.y), f.z);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec3 p = world_pos;
    float broad = value_noise3(p * vec3(0.055, 0.075, 0.055) + vec3(7.0, 19.0, 31.0));
    float medium = value_noise3(p * vec3(0.17, 0.13, 0.17) + vec3(41.0, 5.0, 23.0));
    float tone = clamp((broad - 0.5) * 0.22 + (medium - 0.5) * 0.07, -0.12, 0.12);
    ALBEDO = clamp(base_color.rgb * (1.0 + tone), vec3(0.0), vec3(1.0));
    ROUGHNESS = clamp(base_roughness + (0.5 - broad) * 0.035, 0.86, 0.97);
    METALLIC = 0.0;
    SPECULAR = 0.14;
}
"""
    return shader

static func create_material(base_color: Color, roughness: float = 0.91) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = _shader()
    material.set_shader_parameter("base_color", base_color)
    material.set_shader_parameter("base_roughness", roughness)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("procedural_only", true)
    material.set_meta("building_material_claimed", false)
    material.set_meta("brick_claimed", false)
    material.set_meta("stone_claimed", false)
    material.set_meta("concrete_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("weathering_claimed", false)
    material.set_meta("facade_unit_scale_claimed", false)
    material.set_meta("geometry_changed", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material
