extends Node

## Official orthophoto visual pass for Laeken phase 1.
## Geometry stays authoritative from UrbIS WFS + DTM. This pass only samples the
## committed CC0 orthophoto by the same EPSG:31370 bbox to restore real surface
## colour/markings on terrain and street polygons.

const ORTHO_PATH := "res://data/orthophoto/laeken_jette/phase1_ortho.jpg"
const PHASE_MIN_X := -568.29422791934
const PHASE_MAX_X := 1231.70577208066
const PHASE_NORTH_Z := -7211.37585073803
const PHASE_SOUTH_Z := -4111.37585073803

var orthophoto_active: bool = false
var terrain_material_applied: bool = false
var road_material_applied: bool = false


func _ready() -> void:
    call_deferred("_apply")


func _load_ortho_texture() -> Texture2D:
    # In a normal editor/export run the imported Texture2D is preferred. In
    # headless CI there may be no .godot/imported cache yet, so load the JPEG
    # bytes directly instead of falsely reporting that the source is missing.
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
    var texture := _load_ortho_texture()
    if texture == null:
        push_warning("LaekenOrthophotoPass: official orthophoto texture missing or unreadable")
        return

    var zone := get_parent()
    var terrain := zone.get_node_or_null("LaekenTerrain/OfficialDTMTerrainMesh") as MeshInstance3D
    var roads := zone.get_node_or_null("OfficialStreetSurfaces") as MeshInstance3D

    if terrain != null:
        terrain.material_override = _terrain_ortho_material(texture)
        terrain_material_applied = true
    if roads != null:
        roads.material_override = _road_ortho_material(texture)
        road_material_applied = true

    orthophoto_active = terrain_material_applied and road_material_applied
    print("LAEKEN_ORTHOPHOTO_READY: active=%s terrain=%s roads=%s texture=%s" % [orthophoto_active, terrain_material_applied, road_material_applied, ORTHO_PATH])


func _terrain_ortho_material(texture: Texture2D) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = _shader_prefix() + """
void fragment() {
    vec2 uv = ortho_uv(local_pos.xz);
    vec3 aerial = texture(ortho_texture, uv).rgb;
    float slope = 1.0 - clamp(normalize(local_normal).y, 0.0, 1.0);
    float slope_shade = mix(1.0, 0.82, smoothstep(0.10, 0.55, slope));
    ALBEDO = aerial * slope_shade;
    ROUGHNESS = 0.96;
    METALLIC = 0.0;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("ortho_texture", texture)
    return material


func _road_ortho_material(texture: Texture2D) -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = _shader_prefix() + """
float luminance(vec3 c) {
    return dot(c, vec3(0.2126, 0.7152, 0.0722));
}
void fragment() {
    vec2 uv = ortho_uv(local_pos.xz);
    vec3 aerial = texture(ortho_texture, uv).rgb;
    float lum = luminance(aerial);
    // Keep real lane markings, crossings and pavement variation but dampen
    // bright aerial artefacts so the road still reads as a 3D game surface.
    vec3 asphalt = vec3(0.105, 0.112, 0.118);
    float marking_hint = smoothstep(0.58, 0.88, lum);
    float aerial_weight = mix(0.62, 0.86, marking_hint);
    vec3 colour = mix(asphalt, aerial, aerial_weight);
    ALBEDO = colour;
    ROUGHNESS = 0.94;
    METALLIC = 0.0;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    material.set_shader_parameter("ortho_texture", texture)
    return material


func _shader_prefix() -> String:
    return """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D ortho_texture : source_color, filter_linear_mipmap_anisotropic;
varying vec3 local_pos;
varying vec3 local_normal;
const float MIN_X = -568.29422791934;
const float MAX_X = 1231.70577208066;
const float NORTH_Z = -7211.37585073803;
const float SOUTH_Z = -4111.37585073803;
void vertex() {
    local_pos = VERTEX;
    local_normal = NORMAL;
}
vec2 ortho_uv(vec2 xz) {
    float u = (xz.x - MIN_X) / (MAX_X - MIN_X);
    float v = (xz.y - NORTH_Z) / (SOUTH_Z - NORTH_Z);
    return clamp(vec2(u, v), vec2(0.0), vec2(1.0));
}
"""
