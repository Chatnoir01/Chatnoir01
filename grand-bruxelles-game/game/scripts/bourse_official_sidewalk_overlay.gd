extends Node3D

const DATA_PATH := "res://data/urbis/bourse_official_sidewalks.game.json"
const BASE_SURFACE_Y_M := 0.17
# Renderer-only depth separation. This is not a measured or claimed curb elevation.
const PRESENTATION_EPSILON_M := 0.006
# Thin presentation seam used to make the official sidewalk footprint readable.
# Width and height are rendering choices only; this is NOT physical curb geometry.
const BOUNDARY_PRESENTATION_WIDTH_M := 0.05
const BOUNDARY_PRESENTATION_EPSILON_M := 0.010
const SEGMENT_KEY_MM := 1000.0

var _polygon_count: int = 0
var _triangle_count: int = 0
var _vertex_count: int = 0
var _height_is_renderer_bias_only: bool = false
var _boundary_segment_count: int = 0
var _boundary_triangle_count: int = 0
var _boundary_is_renderer_only: bool = false
var _collision_ready: bool = false
var _collision_triangle_count: int = 0
var _collision_vertex_count: int = 0

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

func _point_key(point: Vector2) -> String:
    return "%d,%d" % [roundi(point.x * SEGMENT_KEY_MM), roundi(point.y * SEGMENT_KEY_MM)]

func _segment_key(a: Vector2, b: Vector2) -> String:
    var a_key := _point_key(a)
    var b_key := _point_key(b)
    if a_key < b_key:
        return "%s|%s" % [a_key, b_key]
    return "%s|%s" % [b_key, a_key]

func _collect_segments(polygon: PackedVector2Array, records: Dictionary) -> void:
    if polygon.size() < 2:
        return
    for index in range(polygon.size()):
        var a := polygon[index]
        var b := polygon[(index + 1) % polygon.size()]
        if a.distance_to(b) < 0.001:
            continue
        var key := _segment_key(a, b)
        if records.has(key):
            var record: Dictionary = records[key]
            record["count"] = int(record.get("count", 0)) + 1
            records[key] = record
        else:
            records[key] = {"count": 1, "a": a, "b": b}

func _append_boundary_segment(tool: SurfaceTool, a: Vector2, b: Vector2) -> bool:
    var delta := b - a
    if delta.length() < 0.001:
        return false
    var side := Vector2(-delta.y, delta.x).normalized() * (BOUNDARY_PRESENTATION_WIDTH_M * 0.5)
    var p0 := a + side
    var p1 := b + side
    var p2 := b - side
    var p3 := a - side
    var height := BASE_SURFACE_Y_M + PRESENTATION_EPSILON_M + BOUNDARY_PRESENTATION_EPSILON_M
    for point: Vector2 in [p0, p1, p2, p0, p2, p3]:
        tool.set_normal(Vector3.UP)
        tool.add_vertex(Vector3(point.x, height, point.y))
    return true

func _build_boundary_mesh(records: Dictionary) -> void:
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.255, 0.245, 0.225, 1.0)
    material.roughness = 0.98
    material.cull_mode = BaseMaterial3D.CULL_DISABLED

    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    for key: String in records:
        var record: Dictionary = records[key]
        # Shared polygon subdivision edges occur twice and are intentionally hidden.
        # Only the exterior boundary of the bounded official sidewalk subset is articulated.
        if int(record.get("count", 0)) != 1:
            continue
        if _append_boundary_segment(tool, record["a"], record["b"]):
            _boundary_segment_count += 1
            _boundary_triangle_count += 2

    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        _fail("no renderable sidewalk boundary articulation")
        return
    var instance := MeshInstance3D.new()
    instance.name = "OfficialBourseSidewalkBoundaryMesh"
    instance.mesh = mesh
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(instance)
    _boundary_is_renderer_only = true

func _append_collision_surface_faces(arrays: Array, collision_faces: PackedVector3Array) -> void:
    if arrays.size() <= Mesh.ARRAY_VERTEX:
        return
    var vertices_value: Variant = arrays[Mesh.ARRAY_VERTEX]
    if typeof(vertices_value) != TYPE_PACKED_VECTOR3_ARRAY:
        return
    var vertices: PackedVector3Array = vertices_value

    var indices := PackedInt32Array()
    if arrays.size() > Mesh.ARRAY_INDEX:
        var indices_value: Variant = arrays[Mesh.ARRAY_INDEX]
        if typeof(indices_value) == TYPE_PACKED_INT32_ARRAY:
            indices = indices_value

    if indices.is_empty():
        for vertex: Vector3 in vertices:
            collision_faces.append(Vector3(vertex.x, BASE_SURFACE_Y_M, vertex.z))
        return

    for vertex_index: int in indices:
        if vertex_index < 0 or vertex_index >= vertices.size():
            _fail("render mesh contains an invalid collision vertex index")
            collision_faces.clear()
            return
        var vertex := vertices[vertex_index]
        collision_faces.append(Vector3(vertex.x, BASE_SURFACE_Y_M, vertex.z))

func _build_collision_from_render_mesh(mesh: ArrayMesh, data: Dictionary) -> void:
    if mesh == null or mesh.get_surface_count() == 0:
        _fail("cannot derive public-space collision from empty render mesh")
        return

    var collision_faces := PackedVector3Array()
    for surface_index in range(mesh.get_surface_count()):
        var arrays := mesh.surface_get_arrays(surface_index)
        _append_collision_surface_faces(arrays, collision_faces)
        if collision_faces.is_empty():
            _fail("could not derive collision faces from official render mesh")
            return

    if collision_faces.size() < 3 or collision_faces.size() % 3 != 0:
        _fail("invalid collision face topology derived from official render mesh")
        return

    var shape := ConcavePolygonShape3D.new()
    shape.set_faces(collision_faces)
    var shape_node := CollisionShape3D.new()
    shape_node.name = "CollisionShape3D"
    shape_node.shape = shape

    var body := StaticBody3D.new()
    body.name = "OfficialBourseSidewalkCollision"
    body.set_meta("geometry_source", "same_official_urbis_sidewalk_mesh")
    body.set_meta("height_authority", "gameplay_base_surface_datum")
    body.set_meta("source_elevation_authority", false)
    body.set_meta("no_curb_height_inference", true)
    body.set_meta("no_wall_height_inference", true)
    body.set_meta("presentation_bias_applied", false)
    body.set_meta("data_path", DATA_PATH)
    body.set_meta("source_release", str(data.get("source_release", "")))
    body.add_child(shape_node)
    add_child(body)

    _collision_vertex_count = collision_faces.size()
    _collision_triangle_count = collision_faces.size() / 3
    _collision_ready = true

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
    var segment_records: Dictionary = {}
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
        _collect_segments(polygon, segment_records)
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
    _build_collision_from_render_mesh(mesh, data)
    _build_boundary_mesh(segment_records)
    print(
        "Bourse official sidewalk overlay: %d polygons, %d triangles, %d collision triangles, %d exterior boundary segments" %
        [_polygon_count, _triangle_count, _collision_triangle_count, _boundary_segment_count]
    )

func official_sidewalk_overlay_count() -> int:
    return _polygon_count

func official_sidewalk_overlay_triangle_count() -> int:
    return _triangle_count

func official_sidewalk_overlay_vertex_count() -> int:
    return _vertex_count

func sidewalk_overlay_height_is_renderer_bias_only() -> bool:
    return _height_is_renderer_bias_only

func official_sidewalk_boundary_segment_count() -> int:
    return _boundary_segment_count

func official_sidewalk_boundary_triangle_count() -> int:
    return _boundary_triangle_count

func sidewalk_boundary_is_renderer_only() -> bool:
    return _boundary_is_renderer_only

func collision_ready() -> bool:
    return _collision_ready

func collision_triangle_count() -> int:
    return _collision_triangle_count

func collision_vertex_count() -> int:
    return _collision_vertex_count

func base_surface_y_m() -> float:
    return BASE_SURFACE_Y_M

func presentation_y_m() -> float:
    return BASE_SURFACE_Y_M + PRESENTATION_EPSILON_M

func render_bias_m() -> float:
    return PRESENTATION_EPSILON_M
