extends Node3D

const DATA_PATH := "res://data/urbis/bourse_official_sidewalks.game.json"
const BASE_SURFACE_Y_M := 0.17
# Renderer-only depth separation. This is not a measured or claimed curb elevation.
const PRESENTATION_EPSILON_M := 0.006

var _polygon_count: int = 0
var _triangle_count: int = 0
var _vertex_count: int = 0
var _height_is_renderer_bias_only: bool = false

func _ready() -> void:
    _build()

func _fail(message: String) -> void:
    push_error("Bourse official sidewalk overlay: %s" % message)

func _polygon(raw_polygon: Array) -> PackedVector2Array:
    var polygon := PackedVector2Array()
    for raw_point: Variant in raw_polygon:
        if typeof(raw_point) == TYPE_ARRAY and raw_point.size() >= 2:
            polygon.append(Vector2(float(raw_point[0]), float(raw_point[1])))
    if polygon.size() >= 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
        polygon.remove_at(polygon.size() - 1)
    return polygon

func _append_polygon(tool: SurfaceTool, polygon: PackedVector2Array) -> int:
    if polygon.size() < 3:
        return 0
    var indices := Geometry2D.triangulate_polygon(polygon)
    if indices.size() < 3:
        polygon.reverse()
        indices = Geometry2D.triangulate_polygon(polygon)
    if indices.size() < 3:
        return 0
    for raw_index: int in indices:
        var point := polygon[raw_index]
        tool.set_normal(Vector3.UP)
        tool.add_vertex(Vector3(point.x, BASE_SURFACE_Y_M + PRESENTATION_EPSILON_M, point.y))
    return indices.size() / 3

func _build() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _fail("data missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("invalid JSON")
        return
    var data: Dictionary = parsed
    if str(data.get("schema", "")) != "grand-bruxelles-bourse-official-sidewalk-runtime-v1":
        _fail("unsupported schema")
        return
    if bool(data.get("runtime_approved", true)):
        _fail("evidence must remain runtime-unapproved")
        return
    if bool(data.get("curb_elevation_resolved", true)):
        _fail("curb elevation must remain unresolved")
        return
    if not bool(data.get("presentation_height_is_renderer_bias_only", false)):
        _fail("renderer-bias provenance missing")
        return
    _height_is_renderer_bias_only = true

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.48, 0.455, 0.415, 1.0)
    material.roughness = 0.95
    material.cull_mode = BaseMaterial3D.CULL_DISABLED

    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    for raw_sidewalk: Variant in data.get("sidewalks", []):
        if typeof(raw_sidewalk) != TYPE_DICTIONARY:
            continue
        var sidewalk: Dictionary = raw_sidewalk
        if int(sidewalk.get("source_level", 999)) != 0:
            _fail("non-surface source level: %s" % str(sidewalk.get("source_id", "unknown")))
            continue
        var rings: Array = sidewalk.get("world_rings_xz", [])
        if rings.size() != 1:
            _fail("requires one exterior ring: %s" % str(sidewalk.get("source_id", "unknown")))
            continue
        var polygon := _polygon(rings[0])
        var triangles := _append_polygon(tool, polygon)
        if triangles <= 0:
            _fail("triangulation failed: %s" % str(sidewalk.get("source_id", "unknown")))
            continue
        _polygon_count += 1
        _triangle_count += triangles
        _vertex_count += polygon.size()

    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        _fail("no renderable overlay")
        return
    var instance := MeshInstance3D.new()
    instance.name = "OfficialBourseSidewalkMesh"
    instance.mesh = mesh
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(instance)
    print("Bourse official sidewalk overlay: %d polygons, %d triangles" % [_polygon_count, _triangle_count])

func official_sidewalk_overlay_count() -> int:
    return _polygon_count

func official_sidewalk_overlay_triangle_count() -> int:
    return _triangle_count

func official_sidewalk_overlay_vertex_count() -> int:
    return _vertex_count

func sidewalk_overlay_height_is_renderer_bias_only() -> bool:
    return _height_is_renderer_bias_only
