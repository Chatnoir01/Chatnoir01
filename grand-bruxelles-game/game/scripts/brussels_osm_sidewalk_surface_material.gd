extends RefCounted
class_name BrusselsOsmSidewalkSurfaceMaterial

## Reusable texture-free presentation family for the existing OSM-derived
## sidewalk meshes generated beside drivable roads in the current vertical slice.
## The committed corridor snapshot proves road placement/class/width, while the
## sidewalk widths and presentation recipe are authored runtime conventions.
## This material therefore makes no claim about real paving composition, slab
## dimensions, aggregate, wear, exact colour, or measured photometry.

const MATERIAL_FAMILY := "brussels_osm_sidewalk_surface_v1"
const SOURCE_LABEL := "OpenStreetMap contributors via Overpass API; adjacent road placement/class/width only; ODbL-1.0"

static func _shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 dark_color : source_color = vec4(0.315, 0.305, 0.285, 1.0);
uniform vec4 light_color : source_color = vec4(0.455, 0.442, 0.410, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.93;

varying vec3 world_pos;

float hash21(vec2 p) {
    p = fract(p * vec2(127.1, 311.7));
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float value_noise(vec2 p) {
    vec2 cell = floor(p);
    vec2 local = fract(p);
    vec2 smooth_local = local * local * (3.0 - 2.0 * local);
    float a = hash21(cell);
    float b = hash21(cell + vec2(1.0, 0.0));
    float c = hash21(cell + vec2(0.0, 1.0));
    float d = hash21(cell + vec2(1.0, 1.0));
    return mix(mix(a, b, smooth_local.x), mix(c, d, smooth_local.x), smooth_local.y);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 xz = world_pos.xz;
    float broad = value_noise(xz * 0.11 + vec2(5.0, 29.0));
    float medium = value_noise(xz * 0.48 + vec2(37.0, 13.0));
    float fine = value_noise(xz * 1.35 + vec2(73.0, 47.0));
    float authored_tone = clamp(broad * 0.58 + medium * 0.30 + fine * 0.12, 0.0, 1.0);
    ALBEDO = mix(dark_color.rgb, light_color.rgb, authored_tone);
    ROUGHNESS = clamp(base_roughness + (0.5 - authored_tone) * 0.045, 0.86, 0.99);
    METALLIC = 0.0;
    SPECULAR = 0.13;
}
"""
    return shader

static func create_material() -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = _shader()
    material.set_shader_parameter("dark_color", Color(0.315, 0.305, 0.285, 1.0))
    material.set_shader_parameter("light_color", Color(0.455, 0.442, 0.410, 1.0))
    material.set_shader_parameter("base_roughness", 0.93)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("placement_source", "OpenStreetMap contributors via Overpass API")
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("procedural_only", true)
    material.set_meta("surface_composition_claimed", false)
    material.set_meta("paving_unit_dimensions_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("wear_pattern_claimed", false)
    material.set_meta("geometry_changed", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    return material
