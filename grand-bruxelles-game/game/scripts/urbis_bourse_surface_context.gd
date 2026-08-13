extends Node3D

const DATA_PATHS := [
    "res://data/urbis/bourse_street_surfaces.game.json",
    "res://data/urbis/bourse_street_surfaces_adjacent_22982.game.json",
    "res://data/urbis/bourse_street_surfaces_adjacent_41098.game.json",
]
const SUPPORTED_TYPES := ["I", "P", "S", "SW"]
const PRESENTATION_Y_OFFSET_M := 0.17

var _materials: Dictionary = {}
var _surface_count: int = 0
var _triangle_count: int = 0
var _source_area_m2: float = 0.0
var _runtime_vertex_count: int = 0
var _type_counts: Dictionary = {}


func _ready() -> void:
    _make_materials()
    _build()


func _material(color: Color, roughness: float) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _make_materials() -> void:
    _materials = {
        "S": _material(Color(0.105, 0.108, 0.112, 1.0), 0.98),
        "SW": _material(Color(0.48, 0.455, 0.415, 1.0), 0.95),
        "I": _material(Color(0.385, 0.37, 0.34, 1.0), 0.95),
        "P": _material(Color(0.43, 0.405, 0.365, 1.0), 0.96),
    }


func _new_tool(surface_type: String) -> SurfaceTool:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(_materials[surface_type])
    return tool


func _polygon(raw_polygon: Array) -> PackedVector2Array:
    var polygon := PackedVector2Array()
    for raw_point: Variant in raw_polygon:
        if typeof(raw_point) == TYPE_ARRAY and raw_point.size() >= 2:
            polygon.append(Vector2(float(raw_point[0]), float(raw_point[1])))
    if polygon.size() >= 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
        polygon.remove_at(polygon.size() - 1)
    return polygon


func _append_polygon(tool: SurfaceTool, polygon: PackedVector2Array, height: float) -> int:
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
        tool.add_vertex(Vector3(point.x, height, point.y))
    return indices.size() / 3


func _commit_tool(tool: SurfaceTool, surface_type: String) -> void:
    var mesh := tool.commit()
    if mesh == null or mesh.get_surface_count() == 0:
        return
    var instance := MeshInstance3D.new()
    instance.name = "OfficialBourseSurface_%s" % surface_type
    instance.mesh = mesh
    instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(instance)


func _append_data_file(data_path: String, tools: Dictionary) -> void:
    if not FileAccess.file_exists(data_path):
        push_error("Bourse UrbIS surface data missing: %s" % data_path)
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid Bourse UrbIS surface JSON: %s" % data_path)
        return
    var data: Dictionary = parsed
    if str(data.get("schema", "")) != "grand-bruxelles-urbis-bourse-surfaces-v1":
        push_error("Unsupported Bourse surface schema: %s" % data_path)
        return

    for raw_surface: Variant in data.get("surfaces", []):
        if typeof(raw_surface) != TYPE_DICTIONARY:
            continue
        var surface: Dictionary = raw_surface
        if int(surface.get("level", 999)) != 0:
            push_error("Bourse runtime rejects non-surface LVL: %s" % str(surface.get("inspire_id", "unknown")))
            continue
        var surface_type := str(surface.get("type_uninterpreted", ""))
        if not tools.has(surface_type):
            continue
        var rings: Array = surface.get("world_rings_xz", [])
        if rings.size() != 1:
            push_error("Bourse runtime currently requires exactly one exterior ring: %s" % str(surface.get("inspire_id", "unknown")))
            continue
        var polygon := _polygon(rings[0])
        var triangles := _append_polygon(tools[surface_type], polygon, PRESENTATION_Y_OFFSET_M)
        if triangles <= 0:
            push_error("Could not triangulate Bourse surface: %s" % str(surface.get("inspire_id", "unknown")))
            continue
        _surface_count += 1
        _triangle_count += triangles
        _runtime_vertex_count += polygon.size()
        _source_area_m2 += float(surface.get("area_m2", 0.0))
        _type_counts[surface_type] = int(_type_counts[surface_type]) + 1


func _build() -> void:
    var tools: Dictionary = {}
    for surface_type: String in SUPPORTED_TYPES:
        tools[surface_type] = _new_tool(surface_type)
        _type_counts[surface_type] = 0

    for data_path: String in DATA_PATHS:
        _append_data_file(data_path, tools)

    for surface_type: String in SUPPORTED_TYPES:
        _commit_tool(tools[surface_type], surface_type)
    print(
        "Bourse UrbIS exact surfaces: %d polygons, %d triangles, %.0f m2" %
        [_surface_count, _triangle_count, _source_area_m2]
    )


func official_surface_count() -> int:
    return _surface_count


func official_triangle_count() -> int:
    return _triangle_count


func official_runtime_vertex_count() -> int:
    return _runtime_vertex_count


func official_source_area_m2() -> float:
    return _source_area_m2


func official_type_counts() -> Dictionary:
    return _type_counts.duplicate(true)
