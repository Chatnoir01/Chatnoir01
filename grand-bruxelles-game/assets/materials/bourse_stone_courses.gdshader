shader_type spatial;
render_mode cull_disabled;

uniform vec4 base_color : source_color = vec4(0.74, 0.71, 0.64, 1.0);
uniform float base_roughness : hint_range(0.0, 1.0) = 0.91;
uniform float course_height_m : hint_range(0.2, 2.0) = 0.62;
uniform float joint_half_width_m : hint_range(0.002, 0.08) = 0.018;
uniform float joint_darkening : hint_range(0.0, 0.2) = 0.065;
uniform float roughness_lift : hint_range(0.0, 0.2) = 0.035;

varying vec3 local_position;

void vertex() {
    local_position = VERTEX;
}

void fragment() {
    float period = max(course_height_m, 0.001);
    float y_in_course = mod(local_position.y, period);
    float distance_to_joint = min(y_in_course, period - y_in_course);
    float aa = max(fwidth(local_position.y), 0.0015);
    float joint = 1.0 - smoothstep(joint_half_width_m, joint_half_width_m + aa * 1.5, distance_to_joint);
    float shade = 1.0 - joint * joint_darkening;
    ALBEDO = base_color.rgb * shade;
    ROUGHNESS = clamp(base_roughness + joint * roughness_lift, 0.0, 1.0);
    METALLIC = 0.0;
}
