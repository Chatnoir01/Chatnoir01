extends RefCounted
class_name IxellesSourceFacadeMaterial

## Texture-free presentation material for the bounded Ixelles strong-height massing.
## UrbIS/DTM evidence supports footprint placement and the accepted semantic heights only.
## The tonal facade rhythm below is authored visual treatment: it does not claim surveyed
## windows, floors, bays, materials, colours, weathering, or facade-unit dimensions.

const MATERIAL_FAMILY := "ixelles_source_facade_articulation_v1"
const SOURCE_LABEL := "Brussels UrbIS footprint + accepted Ixelles strong-height evidence; authored presentation only"

static func _shader() -> Shader:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.52, 0.45, 0.38, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.92;
uniform float rhythm_seed : hint_range(0.0, 1.0) = 0.0;

varying vec3 world_pos;
varying vec3 world_normal;

float hash21(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
    world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    vec3 n = normalize(world_normal);
    float wall = 1.0 - smoothstep(0.48, 0.82, abs(n.y));
    float along = abs(n.x) > abs(n.z) ? world_pos.z : world_pos.x;

    float broad = hash21(floor(world_pos.xz * 0.075 + vec2(rhythm_seed * 17.0, rhythm_seed * 29.0)));
    float plane = (abs(dot(normalize(n.xz + vec2(0.0001)), normalize(vec2(0.78, 0.625)))) - 0.5) * 0.13;
    float base_tone = (broad - 0.5) * 0.12 + plane;
    vec3 facade = clamp(base_color.rgb * (1.0 + base_tone), vec3(0.0), vec3(1.0));

    // Presentation rhythm only. Dimensions deliberately do not encode surveyed bays/floors.
    float bay_phase = fract((along + rhythm_seed * 13.0) / 3.35);
    float level_phase = fract((world_pos.y + rhythm_seed * 9.0) / 3.20);
    float bay_inner = smoothstep(0.13, 0.20, bay_phase) * (1.0 - smoothstep(0.80, 0.87, bay_phase));
    float level_inner = smoothstep(0.20, 0.28, level_phase) * (1.0 - smoothstep(0.72, 0.80, level_phase));
    float panel = bay_inner * level_inner * wall;

    float belt_low = smoothstep(0.08, 0.12, level_phase);
    float belt_high = 1.0 - smoothstep(0.16, 0.20, level_phase);
    float belt = belt_low * belt_high * wall;

    vec3 panel_tone = mix(base_color.rgb * 0.37, vec3(0.12, 0.16, 0.20), 0.50);
    vec3 articulated = mix(facade, panel_tone, panel * 0.82);
    articulated *= 1.0 - belt * 0.08;

    ALBEDO = clamp(articulated, vec3(0.0), vec3(1.0));
    ROUGHNESS = clamp(mix(base_roughness, 0.72, panel * 0.42) + (0.5 - broad) * 0.025, 0.70, 0.97);
    METALLIC = 0.0;
    SPECULAR = mix(0.12, 0.34, panel * 0.42);
}
"""
    return shader

static func create_material(base_color: Color, roughness: float, profile_index: int) -> ShaderMaterial:
    var material := ShaderMaterial.new()
    material.shader = _shader()
    material.set_shader_parameter("base_color", base_color)
    material.set_shader_parameter("base_roughness", roughness)
    material.set_shader_parameter("rhythm_seed", float(profile_index) / 3.0)
    material.set_meta("material_family", MATERIAL_FAMILY)
    material.set_meta("source_label", SOURCE_LABEL)
    material.set_meta("source_crs", "EPSG:31370")
    material.set_meta("procedural_only", true)
    material.set_meta("presentation_only", true)
    material.set_meta("geometry_changed", false)
    material.set_meta("collision_changed", false)
    material.set_meta("building_material_claimed", false)
    material.set_meta("window_geometry_claimed", false)
    material.set_meta("floor_count_claimed", false)
    material.set_meta("facade_unit_scale_claimed", false)
    material.set_meta("exact_rgb_is_photometric_measurement", false)
    material.set_meta("weathering_claimed", false)
    material.set_meta("visual_recipe_provenance", "authored_texture_free_presentation_over_source_backed_massing")
    return material
