extends Node

## Building visual pass grounded in official data.
## Footprints and positions remain UrbIS. The replacement mesh uses DSM-DTM
## derived heights for 9,163 / 9,518 buildings, with the explicit fallback kept
## only where remote-sensing samples are insufficient. Horizontal/roof-facing
## surfaces sample the official 2024 orthophoto by the exact phase bbox; vertical
## facades remain a procedural Brussels-material approximation.

const ORTHO_PATH := "res://data/orthophoto/laeken_jette/phase1_ortho.jpg"

var building_visual_active: bool = false
var orthophoto_roof_active: bool = false


func _ready() -> void:
    call_deferred("_apply")


func _load_ortho_texture() -> Texture2D:
    if ResourceLoader.exists(ORTHO_PATH):
        var imported := load(ORTHO_PATH) as Texture2D
        if imported != null:
            return imported
    if not FileAccess.file_exists(ORTHO_PATH):
        return null
    var image := Image.load_from_file(ORTHO_PATH)
    if image == null or image.is_empty():
        return null
    return ImageTexture.create_from_image(image)


func _apply() -> void:
    var buildings := get_parent().get_node_or_null("OfficialBuildings") as MeshInstance3D
    if buildings == null:
        push_warning("LaekenBuildingVisualPass: OfficialBuildings missing")
        return

    var ortho := _load_ortho_texture()
    var material := _building_material(ortho)
    buildings.material_override = material
    building_visual_active = true
    orthophoto_roof_active = ortho != null
    print("LAEKEN_BUILDING_VISUAL_READY: active=%s ortho_roofs=%s" % [building_visual_active, orthophoto_roof_active])


func _building_material(ortho: Texture2D) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D ortho_texture : source_color, filter_linear_mipmap_anisotropic;
uniform bool use_ortho = false;

varying vec3 local_pos;
varying vec3 local_normal;

const float MIN_X = -568.29422791934;
const float MAX_X = 1231.70577208066;
const float NORTH_Z = -7211.37585073803;
const float SOUTH_Z = -4111.37585073803;

float hash21(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

vec2 ortho_uv(vec2 xz) {
    float u = (xz.x - MIN_X) / (MAX_X - MIN_X);
    float v = (xz.y - NORTH_Z) / (SOUTH_Z - NORTH_Z);
    return clamp(vec2(u, v), vec2(0.0), vec2(1.0));
}

void vertex() {
    local_pos = VERTEX;
    local_normal = NORMAL;
}

void fragment() {
    vec3 n = normalize(local_normal);
    float top_face = step(0.72, n.y);
    float underside = step(0.72, -n.y);
    vec2 ouv = ortho_uv(local_pos.xz);
    vec3 aerial = use_ortho ? texture(ortho_texture, ouv).rgb : vec3(0.24, 0.20, 0.17);

    float side_coord = abs(n.x) > abs(n.z) ? local_pos.z : local_pos.x;
    float seed = hash21(floor(local_pos.xz / 18.0));
    float aerial_lum = dot(aerial, vec3(0.2126, 0.7152, 0.0722));

    vec3 brick_red = vec3(0.40, 0.17, 0.105);
    vec3 brick_brown = vec3(0.29, 0.19, 0.14);
    vec3 warm_stone = vec3(0.56, 0.50, 0.40);
    vec3 pale_stucco = vec3(0.68, 0.65, 0.58);
    vec3 facade = mix(brick_red, brick_brown, step(0.30, seed));
    facade = mix(facade, warm_stone, step(0.58, seed));
    facade = mix(facade, pale_stucco, step(0.82, seed));

    // Aerial roof colour is real; only a small amount influences the facade
    // palette so it does not masquerade as a photographed facade texture.
    facade = mix(facade, mix(aerial, vec3(aerial_lum), 0.50), 0.12);

    float floor_band = fract(local_pos.y / 3.15);
    float bay = fract(side_coord / 3.0);
    float is_window = step(0.18, bay) * step(bay, 0.80) * step(0.21, floor_band) * step(floor_band, 0.73);
    float narrow_window = step(0.36, bay) * step(bay, 0.64) * step(0.18, floor_band) * step(floor_band, 0.78);
    is_window = mix(is_window, narrow_window, step(0.72, seed));

    float frame = max(step(bay, 0.15), step(0.84, bay));
    vec3 trim = mix(vec3(0.50, 0.48, 0.43), vec3(0.74, 0.70, 0.62), seed);
    vec3 glass = mix(vec3(0.045, 0.065, 0.078), vec3(0.10, 0.14, 0.16), aerial_lum);

    float mortar_x = step(fract(side_coord / 0.62), 0.035);
    float mortar_y = step(fract(local_pos.y / 0.22), 0.055);
    float brick_pattern = max(mortar_x, mortar_y) * (1.0 - step(0.58, seed));
    facade = mix(facade, facade * 1.16, brick_pattern * 0.30);

    float ground_floor = 1.0 - step(3.45, local_pos.y);
    float shop_glass = ground_floor * step(0.10, bay) * step(bay, 0.90);

    vec3 side_colour = facade;
    side_colour = mix(side_colour, trim, frame * 0.18);
    side_colour = mix(side_colour, glass, is_window * 0.92);
    side_colour = mix(side_colour, vec3(0.055, 0.065, 0.07), shop_glass * 0.62);

    // The exact roof surface appearance comes from the georeferenced WMS image.
    vec3 roof_colour = mix(aerial, aerial * 0.86, 0.18);
    vec3 colour = mix(side_colour, roof_colour, top_face * float(use_ortho));
    colour = mix(colour, vec3(0.18, 0.17, 0.16), underside);

    ALBEDO = colour;
    ROUGHNESS = mix(0.90, 0.25, is_window * (1.0 - top_face));
    METALLIC = is_window * 0.06 * (1.0 - top_face);
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("use_ortho", ortho != null)
    if ortho != null:
        material.set_shader_parameter("ortho_texture", ortho)
    return material
