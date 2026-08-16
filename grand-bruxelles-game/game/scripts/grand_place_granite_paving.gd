extends Node3D

const DATA_PATH := "res://data/visual/grand_place_granite_paving.json"
const SURFACE_Y := 0.012

var _surface: MeshInstance3D
var _collision_body: StaticBody3D
var _feature_id := ""
var _polygon_area_m2 := 0.0
var _loaded := false

func _ready() -> void:
    name = "GrandPlaceGranitePaving"
    _build_from_source()

func _fail(message: String) -> void:
    push_error("Grand-Place granite paving: %s" % message)

func _polygon_area(points: Array) -> float:
    var area := 0.0
    for index: int in range(points.size()):
        var a := points[index] as Array
        var b := points[(index + 1) % points.size()] as Array
        area += float(a[0]) * float(b[1]) - float(b[0]) * float(a[1])
    return absf(area) * 0.5

func _build_material() -> ShaderMaterial:
    var shader := Shader.new()
    shader.code = """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

varying vec2 world_xz;

void vertex() {
    world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
    // Source truth establishes granite, but not unit dimensions or a joint layout.
    // Keep the authored presentation broad-band only so it reads as mineral tone
    // at normal player distance without inventing paver seams or aliasing into moire.
    float n1 = sin(world_xz.x * 0.73 + world_xz.y * 1.09);
    float n2 = sin(world_xz.x * 1.31 - world_xz.y * 0.91 + 1.7);
    float n3 = sin(world_xz.x * 0.39 + world_xz.y * 0.47 + 4.1);
    float variation = clamp(0.5 + n1 * 0.07 + n2 * 0.045 + n3 * 0.055, 0.0, 1.0);
    vec3 cool_granite = vec3(0.292, 0.291, 0.286);
    vec3 warm_granite = vec3(0.342, 0.334, 0.318);
    ALBEDO = mix(cool_granite, warm_granite, variation);
    ROUGHNESS = 0.88;
    METALLIC = 0.015;
    SPECULAR = 0.28;
}
"""
    var material := ShaderMaterial.new()
    material.shader = shader
    return material

func _build_collision(mesh: ArrayMesh) -> bool:
    var shape := mesh.create_trimesh_shape()
    if shape == null:
        _fail("collision trimesh creation failed")
        return false
    _collision_body = StaticBody3D.new()
    _collision_body.name = "OfficialGraniteStreetSurfaceCollision"
    _collision_body.collision_layer = 1
    _collision_body.collision_mask = 1
    _collision_body.set_meta("source_feature_id", _feature_id)
    _collision_body.set_meta("geometry_source", "same_official_granite_mesh")
    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    collision.shape = shape
    _collision_body.add_child(collision)
    add_child(_collision_body)
    return true

func _build_from_source() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _fail("source file missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("invalid source JSON")
        return
    var data := parsed as Dictionary
    var source := data.get("source", {}) as Dictionary
    var transform := data.get("transform", {}) as Dictionary
    var raw_polygon := data.get("polygon_lambert72", []) as Array
    if raw_polygon.size() < 4:
        _fail("official street-surface polygon missing")
        return
    var lambert_origin := transform.get("lambert72_origin", []) as Array
    var world_origin := transform.get("world_origin", []) as Array
    if lambert_origin.size() != 2 or world_origin.size() != 2:
        _fail("Lambert72-to-world transform missing")
        return

    _feature_id = str(source.get("feature_id", ""))
    _polygon_area_m2 = _polygon_area(raw_polygon)
    var polygon := PackedVector2Array()
    for raw: Variant in raw_polygon:
        var point := raw as Array
        polygon.append(Vector2(
            float(point[0]) - float(lambert_origin[0]) + float(world_origin[0]),
            -(float(point[1]) - float(lambert_origin[1])) + float(world_origin[1])
        ))
    if polygon.size() >= 2 and polygon[0].distance_to(polygon[polygon.size() - 1]) < 0.001:
        polygon.resize(polygon.size() - 1)
    var triangles := Geometry2D.triangulate_polygon(polygon)
    if triangles.is_empty():
        _fail("official polygon triangulation failed")
        return

    var surface_tool := SurfaceTool.new()
    surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    for triangle_index: int in triangles:
        var point := polygon[triangle_index]
        surface_tool.set_normal(Vector3.UP)
        surface_tool.add_vertex(Vector3(point.x, SURFACE_Y, point.y))
    var mesh := surface_tool.commit()
    if mesh == null:
        _fail("mesh creation failed")
        return

    _surface = MeshInstance3D.new()
    _surface.name = "OfficialGraniteStreetSurface"
    _surface.mesh = mesh
    _surface.material_override = _build_material()
    _surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    _surface.set_meta("source_feature_id", _feature_id)
    _surface.set_meta("source_layer", "urbisvector:StreetSurfaces")
    _surface.set_meta("material_identity_source", "urban.brussels Grand-Place site 322")
    _surface.set_meta("exact_rgb_is_photometric_measurement", false)
    _surface.set_meta("joint_pattern_authored", false)
    add_child(_surface)
    if not _build_collision(mesh):
        return
    _loaded = true

func set_presentation_enabled(enabled: bool) -> void:
    if _surface != null:
        _surface.visible = enabled

func presentation_enabled() -> bool:
    return _surface != null and _surface.visible

func source_feature_id() -> String:
    return _feature_id

func source_polygon_area_m2() -> float:
    return _polygon_area_m2

func geometry_loaded() -> bool:
    return _loaded

func collision_ready() -> bool:
    return _collision_body != null and _collision_body.get_node_or_null("CollisionShape3D") != null
