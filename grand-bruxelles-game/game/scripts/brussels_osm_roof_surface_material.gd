extends RefCounted
class_name BrusselsOsmRoofSurfaceMaterial

## Presentation-only surface for generic OSM-generated roofs.
## OpenStreetMap supports the footprint/placement chain used by the city builder,
## but the generic slice does not establish roof covering, composition, measured
## RGB, weathering or photometric reflectance. This material therefore adds only
## bounded deterministic tonal/roughness separation over existing roof surfaces.

const MATERIAL_FAMILY := "brussels_osm_roof_surface_v1"
const SOURCE := "OpenStreetMap contributors"
const LICENSE := "ODbL-1.0"
const VISUAL_RECIPE_PROVENANCE := "authored_presentation_not_source_measurement"

const SHADER_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 dark_color = vec3(0.125, 0.135, 0.150);
uniform vec3 light_color = vec3(0.235, 0.245, 0.260);
varying vec3 world_pos;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
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
    vec2 p = world_pos.xz;
    float broad = value_noise(p * 0.055);
    float secondary = value_noise(p * 0.17 + vec2(19.0, 37.0));
    float authored_tone = clamp(broad * 0.72 + secondary * 0.28, 0.0, 1.0);
    ALBEDO = mix(dark_color, light_color, authored_tone);
    ROUGHNESS = mix(0.94, 0.82, authored_tone);
    METALLIC = 0.0;
}
"""

static func create_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = SHADER_CODE
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("source", SOURCE)
    material.set_meta("license", LICENSE)
    material.set_meta("visual_recipe_provenance", VISUAL_RECIPE_PROVENANCE)
    material.set_meta("roof_material_claimed", false)
    material.set_meta("roof_covering_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("weathering_claimed", false)
    material.set_meta("geometry_changed", false)
    return material
