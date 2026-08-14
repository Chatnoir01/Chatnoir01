extends Node3D

const DATA_PATH := "res://data/urbis/bourse_official_sidewalks.game.json"
const BLUE_STONE_VISUAL := preload("res://game/scripts/blue_stone_visual_material.gd")
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
    var material := BLUE_STONE_VISUAL.create_boundary_material()

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

    # City of Brussels public-space documentation resolves bluestone coverage
    # around the Bourse. Exact color, roughness, finish and module are not
    # calibrated by that source, so the shared material keeps those values
    # explicitly authored and does not add slab seams or physical curb claims.
    var material := BLUE_STONE_VISUAL.create_paving_material()

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
    _build_boundary_mesh(segment_records)
    print(
        "Bourse official sidewalk overlay: %d polygons, %d triangles, %d exterior boundary segments" %
        [_polygon_count, _triangle_count, _boundary_segment_count]
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
