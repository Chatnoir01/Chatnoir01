extends RefCounted
class_name BrusselsOsmRoofSurfaceMaterial

## Presentation-only surface for generic OSM-generated roofs.
## OpenStreetMap supports the footprint/placement chain used by the city builder,
## but the generic slice does not establish roof covering, composition, measured
## RGB, weathering or photometric reflectance. This material therefore adds only
## bounded deterministic tonal/roughness separation between existing roof masses.

const MATERIAL_FAMILY := "brussels_osm_roof_surface_v1"
const SOURCE := "OpenStreetMap contributors"
const LICENSE := "ODbL-1.0"
const VISUAL_RECIPE_PROVENANCE := "authored_presentation_not_source_measurement"

const SHADER_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec3 base_color = vec3(0.18, 0.19, 0.205);
varying float object_variation;

void vertex() {
    vec2 object_origin = MODEL_MATRIX[3].xz;
    float hash_value = sin(dot(object_origin, vec2(12.9898, 78.233))) * 43758.5453;
    object_variation = fract(hash_value);
}

void fragment() {
    float tone = mix(0.84, 1.12, object_variation);
    ALBEDO = base_color * tone;
    ROUGHNESS = mix(0.82, 0.94, object_variation);
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
