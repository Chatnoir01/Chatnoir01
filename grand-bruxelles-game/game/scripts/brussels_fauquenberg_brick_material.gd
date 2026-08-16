extends RefCounted
class_name BrusselsFauquenbergBrickMaterial

## Reusable presentation material for source-verified yellow Fauquenberg facing
## brick. Brick dimensions and joint width are source-backed; color/PBR and the
## existing alternating presentation pattern are not claimed as measured.

static func create(
    brick_length_m: float,
    brick_height_m: float,
    joint_width_m: float,
    source_label: String
) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform float brick_length_m = 0.24;
uniform float brick_height_m = 0.04;
uniform float joint_width_m = 0.02;
uniform vec4 brick_cool : source_color = vec4(0.54, 0.45, 0.28, 1.0);
uniform vec4 brick_warm : source_color = vec4(0.72, 0.61, 0.37, 1.0);
uniform vec4 mortar_color : source_color = vec4(0.52, 0.49, 0.40, 1.0);

varying vec3 local_pos;

void vertex() {
    local_pos = VERTEX;
}

void fragment() {
    float pitch_x = brick_length_m + joint_width_m;
    float pitch_y = brick_height_m + joint_width_m;
    float course = floor((local_pos.y + 2048.0) / pitch_y);
    float course_offset = mod(course, 2.0) * pitch_x * 0.5;
    float along = local_pos.z + course_offset + 2048.0;
    float cell_x = mod(along, pitch_x);
    float cell_y = mod(local_pos.y + 2048.0, pitch_y);
    float brick_index = floor(along / pitch_x);
    float hash_value = fract(sin(brick_index * 12.9898 + course * 78.233) * 43758.5453);
    float mineral = clamp(0.22 + hash_value * 0.62 + 0.08 * sin(local_pos.z * 0.31 + local_pos.y * 0.17), 0.0, 1.0);
    float joint = max(step(brick_length_m, cell_x), step(brick_height_m, cell_y));
    vec3 brick = mix(brick_cool.rgb, brick_warm.rgb, mineral);
    ALBEDO = mix(brick, mortar_color.rgb, joint);
    ROUGHNESS = mix(clamp(0.88 + (0.5 - mineral) * 0.08, 0.80, 0.96), 0.97, joint);
    METALLIC = 0.0;
    SPECULAR = mix(0.20, 0.13, joint);
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("brick_length_m", brick_length_m)
    material.set_shader_parameter("brick_height_m", brick_height_m)
    material.set_shader_parameter("joint_width_m", joint_width_m)
    material.set_meta("material_family", "brussels_source_verified_fauquenberg_brick")
    material.set_meta("source_label", source_label)
    material.set_meta("source_brick_length_m", brick_length_m)
    material.set_meta("source_brick_height_m", brick_height_m)
    material.set_meta("source_joint_width_m", joint_width_m)
    material.set_meta("geometry_changed", false)
    material.set_meta("new_architectural_detail_authored", false)
    material.set_meta("exact_bond_pattern_claimed", false)
    material.set_meta("exact_reflectance_claimed", false)
    material.set_meta("external_texture_asset", false)
    return material
