extends RefCounted
class_name BrusselsOsmFacadeArticulationMaterial

const MATERIAL_FAMILY := "brussels_osm_facade_articulation_v1"
const PRESENTATION_REVISION := 2
const ROUGHNESS_MICRO_VARIATION := 0.018
const SOURCE_LABEL := "OpenStreetMap contributors via Overpass API; generic building footprint/placement/kind only; ODbL-1.0"

static func _shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 base_color : source_color = vec4(0.45, 0.40, 0.34, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.91;
uniform float roughness_micro_variation : hint_range(0.0, 0.04) = 0.018;
varying vec3 world_pos;
varying vec3 world_normal;
float hash31(vec3 p) { p = fract(p * 0.1031); p += dot(p, p.yzx + 33.33); return fract((p.x + p.y) * p.z); }
float value_noise3(vec3 p) {
    vec3 i = floor(p); vec3 f = fract(p); f = f * f * (3.0 - 2.0 * f);
    float n000=hash31(i+vec3(0,0,0)); float n100=hash31(i+vec3(1,0,0)); float n010=hash31(i+vec3(0,1,0)); float n110=hash31(i+vec3(1,1,0));
    float n001=hash31(i+vec3(0,0,1)); float n101=hash31(i+vec3(1,0,1)); float n011=hash31(i+vec3(0,1,1)); float n111=hash31(i+vec3(1,1,1));
    float nx00=mix(n000,n100,f.x); float nx10=mix(n010,n110,f.x); float nx01=mix(n001,n101,f.x); float nx11=mix(n011,n111,f.x);
    return mix(mix(nx00,nx10,f.y),mix(nx01,nx11,f.y),f.z);
}
float roughness_response(vec3 p) {
    float fine_a=value_noise3(p*vec3(0.83,0.71,0.83)+vec3(13,47,29));
    float fine_b=value_noise3(p*vec3(1.47,1.19,1.47)+vec3(61,17,43));
    return clamp(((fine_a*0.62+fine_b*0.38)-0.5)*2.0,-1.0,1.0);
}
void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; world_normal=normalize(MODEL_NORMAL_MATRIX*NORMAL); }
void fragment(){
    float broad=value_noise3(world_pos*vec3(0.055,0.075,0.055)+vec3(7,19,31));
    float medium=value_noise3(world_pos*vec3(0.17,0.13,0.17)+vec3(41,5,23));
    float baseline_tone=clamp((broad-0.5)*0.22+(medium-0.5)*0.07,-0.12,0.12);
    vec2 hn=world_normal.xz; float hl=length(hn); float orientation=0.5;
    if(hl>0.001){ vec2 n=hn/hl; orientation=abs(dot(n,normalize(vec2(0.78,0.625)))); }
    float plane=(orientation-0.5)*0.28; float tone=clamp(baseline_tone+plane,-0.24,0.24);
    ALBEDO=clamp(base_color.rgb*(1.0+tone),vec3(0.0),vec3(1.0)); ROUGHNESS=clamp(base_roughness+(0.5-broad)*0.035-plane*0.08+roughness_micro_variation*roughness_response(world_pos),0.85,0.97); METALLIC=0.0; SPECULAR=0.14;
}
"""
    return shader

static func create_material(base_color: Color, roughness: float = 0.91) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = _shader()
    material.set_shader_parameter("base_color", base_color)
    material.set_shader_parameter("base_roughness", roughness)
    material.set_shader_parameter("roughness_micro_variation", ROUGHNESS_MICRO_VARIATION)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("presentation_revision", PRESENTATION_REVISION)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("license", "ODbL-1.0")
    material.set_meta("procedural_only", true)
    material.set_meta("geometry_changed", false)
    material.set_meta("uses_external_textures", false)
    material.set_meta("building_material_claimed", false)
    material.set_meta("window_geometry_claimed", false)
    material.set_meta("masonry_units_claimed", false)
    material.set_meta("weathering_claimed", false)
    material.set_meta("surface_detail_semantics_claimed", false)
    material.set_meta("roughness_microvariation_source_measured", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("normal_is_source_measurement", false)
    material.set_meta("visual_recipe_provenance", "authored_presentation_from_existing_mesh_normal_not_source_measurement")
    return material
