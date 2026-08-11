extends Node3D
class_name UrbisCellBuilder

@export_file("*.json") var data_path: String = ""
@export var expected_cell_id: String = ""
@export var build_collisions: bool = false

var _road: StandardMaterial3D
var _sidewalk: StandardMaterial3D
var _island: StandardMaterial3D
var _paved: StandardMaterial3D
var _other_surface: StandardMaterial3D
var _building_materials: Array[StandardMaterial3D] = []


func _ready() -> void:
    _make_materials()
    if not data_path.is_empty():
        build_from_path(data_path)


func _material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.cull_mode = BaseMaterial3D.CULL_DISABLED
    return material


func _make_materials() -> void:
    _road = _material(Color(0.075, 0.078, 0.082, 1.0), 0.97)
    _sidewalk = _material(Color(0.45, 0.435, 0.405, 1.0), 0.94)
    _island = _material(Color(0.36, 0.35, 0.325, 1.0), 0.94)
    _paved = _material(Color(0.39, 0.375, 0.345, 1.0), 0.95)
    _other_surface = _material(Color(0.28, 0.285, 0.28, 1.0), 0.95)
    _building_materials = [
        _material(Color(0.47, 0.31, 0.22, 1.0), 0.92),
        _material(Color(0.60, 0.54, 0.43, 1.0), 0.91),
        _material(Color(0.36, 0.275, 0.235, 1.0), 0.93),
        _material(Color(0.49, 0.48, 0.445, 1.0), 0.91),
    ]


func build_from_path(path: String) -> bool:
    if not FileAccess.file_exists(path):
        push_warning("UrbIS runtime cell missing: %s" % path)
        return false
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid UrbIS runtime cell: %s" % path)
        return false
    return build_from_data(parsed as Dictionary)


func build_from_data(data: Dictionary) -> bool:
    if str(data.get("format", "")) != "grand-bruxelles-urbis-cell-runtime-v1":
        push_error("Unsupported UrbIS cell format")
        return false
    var cell_id := str(data.get("cell_id", ""))
    if not expected_cell_id.is_empty() and cell_id != expected_cell_id:
        push_error("UrbIS cell mismatch: expected %s, got %s" % [expected_cell_id, cell_id])
        return false

    _clear_generated_children()
    var surface_count := _build_street_surfaces(data.get("street_surfaces", []))
    var building_count := _build_buildings(data.get("buildings", []))
    name = "UrbISCell_%s" % cell_id
    print("Grand Bruxelles UrbIS cell %s: %d surfaces, %d buildings" % [cell_id, surface_count, building_count])
    return true


func _clear_generated_children() -> void:
    for child in get_children():
        if child is Node3D and (child.name == "UrbISStreetSurfaces" or child.name == "UrbISExactBuildings"):
            child.queue_free()


func _world(point: Vector2, y: float) -> Vector3:
    # Runtime coordinates already use the shared project origin. No per-zone
    # translation is allowed here or neighbouring cells would drift apart.
    return Vector3(point.x, y, point.y)


func _ring(raw_polygon: Array) -> PackedVector2Array:
    var polygon := PackedVector2Array()
    for raw: Variant in raw_polygon:
        if typeof(raw) != TYPE_ARRAY or raw.size() < 2:
            continue
        polygon.append(Vector2(float(raw[0]), float(raw[1])))
    if polygon.size() >= 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
        polygon.remove_at(polygon.size() - 1)
    return polygon


func _new_tool(material: Material) -> SurfaceTool:
    var tool := SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    return tool


func _append_flat_polygon(tool: SurfaceTool, polygon: PackedVector2Array, y: float) -> bool:
    if polygon.size() < 3:
        return false
    var indices := Geometry2D.triangulate_polygon(polygon)
    if indices.size() < 3:
        return false
    for raw_index: int in indices:
        tool.set_normal(Vector3.UP)
        tool.add_vertex(_world(polygon[raw_index], y))
    return true


func _commit_tool(tool: SurfaceTool, mesh_name: String, root: Node3D, collision: bool = false) -> void:
    var mesh := tool.commit()
    if mesh.get_surface_count() == 0:
        return
    var instance := MeshInstance3D.new()
    instance.name = mesh_name
    instance.mesh = mesh
    root.add_child(instance)
    if collision and build_collisions:
        instance.create_trimesh_collision()


func _build_street_surfaces(features: Array) -> int:
    var root := Node3D.new()
    root.name = "UrbISStreetSurfaces"
    add_child(root)

    var road_tool := _new_tool(_road)
    var sidewalk_tool := _new_tool(_sidewalk)
    var island_tool := _new_tool(_island)
    var paved_tool := _new_tool(_paved)
    var other_tool := _new_tool(_other_surface)
    var count := 0

    for raw_feature: Variant in features:
        if typeof(raw_feature) != TYPE_DICTIONARY:
            continue
        var feature := raw_feature as Dictionary
        var polygon := _ring(feature.get("polygon", []))
        var surface_type := str(feature.get("type", ""))
        var target := other_tool
        if surface_type == "S":
            target = road_tool
        elif surface_type == "SW":
            target = sidewalk_tool
        elif surface_type == "I":
            target = island_tool
        elif surface_type == "P":
            target = paved_tool
        if _append_flat_polygon(target, polygon, 0.075):
            count += 1

    _commit_tool(road_tool, "ExactRoadCarriageways", root, true)
    _commit_tool(sidewalk_tool, "ExactSidewalks", root, true)
    _commit_tool(island_tool, "ExactTrafficIslands", root, true)
    _commit_tool(paved_tool, "ExactPavedAreas", root, true)
    _commit_tool(other_tool, "ExactOtherStreetSurfaces", root, false)
    return count


func _building_bucket(id_text: String) -> int:
    var hash_value := 0
    for character: int in id_text.to_utf8_buffer():
        hash_value = (hash_value * 31 + character) & 0x7fffffff
    return hash_value % _building_materials.size()


func _append_building(tool: SurfaceTool, polygon: PackedVector2Array, height: float) -> bool:
    if polygon.size() < 3:
        return false
    var base_y := 0.10
    var top_y := maxf(base_y + 3.0, height)

    for index: int in range(polygon.size()):
        var a := polygon[index]
        var b := polygon[(index + 1) % polygon.size()]
        var edge := b - a
        if edge.length_squared() < 0.01:
            continue
        var normal := Vector3(-edge.y, 0.0, edge.x).normalized()
        var a0 := _world(a, base_y)
        var b0 := _world(b, base_y)
        var a1 := _world(a, top_y)
        var b1 := _world(b, top_y)
        for vertex: Vector3 in [a0, b0, b1, a0, b1, a1]:
            tool.set_normal(normal)
            tool.add_vertex(vertex)

    var roof_indices := Geometry2D.triangulate_polygon(polygon)
    for raw_index: int in roof_indices:
        tool.set_normal(Vector3.UP)
        tool.add_vertex(_world(polygon[raw_index], top_y))
    return true


func _build_buildings(features: Array) -> int:
    var root := Node3D.new()
    root.name = "UrbISExactBuildings"
    add_child(root)

    var tools: Array[SurfaceTool] = []
    for material: StandardMaterial3D in _building_materials:
        tools.append(_new_tool(material))

    var count := 0
    for raw_feature: Variant in features:
        if typeof(raw_feature) != TYPE_DICTIONARY:
            continue
        var feature := raw_feature as Dictionary
        var polygon := _ring(feature.get("footprint", []))
        if polygon.size() < 3:
            continue
        var height := float(feature.get("height", 10.0))
        var id_text := str(feature.get("id", ""))
        var bucket := _building_bucket(id_text)
        if _append_building(tools[bucket], polygon, height):
            count += 1

    for index: int in range(tools.size()):
        _commit_tool(tools[index], "ExactBuildings_%d" % index, root, true)
    return count
