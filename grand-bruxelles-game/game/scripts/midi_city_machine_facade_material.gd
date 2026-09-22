extends RefCounted
class_name MidiCityMachineFacadeMaterial

## Authored presentation for the Midi City Machine LABO only.
## UrbIS remains the geometry authority. The pattern below is deliberately
## non-semantic: it does not claim measured windows, doors, materials or colors.

const MATERIAL_FAMILY := "midi_city_machine_labo_facade_v1"
const GEOMETRY_SOURCE := "UrbIS normalized building geometry"
const VISUAL_PROVENANCE := "authored procedural LABO presentation; not source measurement"


static func _shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
uniform vec4 base_color : source_color = vec4(0.58, 0.56, 0.53, 1.0);
uniform vec4 articulation_color : source_color = vec4(0.18, 0.24, 0.28, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.92;
varying vec3 world_pos;
varying vec3 world_normal;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    float vertical_surface = smoothstep(0.45, 0.92, 1.0 - abs(world_normal.y));
    float horizontal_axis = abs(world_normal.x) > abs(world_normal.z) ? world_pos.z : world_pos.x;
    float floor_phase = fract((world_pos.y + 0.20) / 3.15);
    float bay_phase = fract((horizontal_axis + 0.35) / 3.60);
    float floor_panel = step(0.20, floor_phase) * (1.0 - step(0.82, floor_phase));
    float bay_panel = step(0.18, bay_phase) * (1.0 - step(0.82, bay_phase));
    float authored_panel = floor_panel * bay_panel * vertical_surface;
    float cell_noise = hash21(floor(vec2(horizontal_axis / 3.60, world_pos.y / 3.15)));
    float wall_variation = (cell_noise - 0.5) * 0.055 * vertical_surface;
    vec3 wall = clamp(base_color.rgb * (1.0 + wall_variation), vec3(0.0), vec3(1.0));
    vec3 panel = articulation_color.rgb * (0.88 + cell_noise * 0.12);
    ALBEDO = mix(wall, panel, authored_panel * 0.68);
    ROUGHNESS = mix(base_roughness, 0.62, authored_panel * 0.55);
    METALLIC = 0.0;
    SPECULAR = mix(0.12, 0.28, authored_panel);
}
"""
    return shader


static func create_material(base_color: Color = Color(0.58, 0.56, 0.53, 1.0)) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = _shader()
    material.set_shader_parameter("base_color", base_color)
    material.set_shader_parameter("articulation_color", Color(0.18, 0.24, 0.28, 1.0))
    material.set_shader_parameter("base_roughness", 0.92)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("geometry_source", GEOMETRY_SOURCE)
    material.set_meta("visual_provenance", VISUAL_PROVENANCE)
    material.set_meta("procedural_only", true)
    material.set_meta("geometry_changed", false)
    material.set_meta("semantic_windows_claimed", false)
    material.set_meta("semantic_doors_claimed", false)
    material.set_meta("building_material_identity_claimed", false)
    material.set_meta("exact_color_is_source_measurement", false)
    material.set_meta("jouable_authorized", false)
    material.set_meta("promotion_performed", false)
    return material
