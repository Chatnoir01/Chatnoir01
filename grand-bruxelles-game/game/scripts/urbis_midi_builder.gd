extends Node3D

@export_file("*.json") var data_path: String = "res://data/urbis/midi/midi_runtime.game.json"

const MIDI_WORLD := Vector3(-668.5, 0.0, 627.84)

var _road: StandardMaterial3D
var _sidewalk: StandardMaterial3D
var _island: StandardMaterial3D
var _paved: StandardMaterial3D
var _other_surface: StandardMaterial3D
var _building_materials: Array[StandardMaterial3D] = []
var _surface_family_counts: Dictionary = {}


func _ready() -> void:
    _make_materials()
    _build_from_runtime()


func _material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
    var material: StandardMaterial3D = StandardMaterial3D.new()
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


func _build_from_runtime() -> void:
    if not FileAccess.file_exists(data_path):
        push_warning("UrbIS Midi runtime missing: %s" % data_path)
        return
    var text: String = FileAccess.get_file_as_string(data_path)
    var parsed: Variant = JSON.parse_string(text)
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Invalid UrbIS Midi runtime: %s" % data_path)
        return
    var data: Dictionary = parsed
    var accuracy := data.get("accuracy", {}) as Dictionary
    if str(accuracy.get("street_surface_levels", "")) != "official_urbis":
        push_error("UrbIS Midi runtime missing official street-surface level contract")
        return
    var surface_count: int = _build_street_surfaces(data.get("street_surfaces", []))
    var building_count: int = _build_buildings(data.get("buildings", []))
    print(
        "Grand Bruxelles UrbIS Midi exact-plan: %d surfaces, %d hidden-level surfaces, %d buildings" %
        [surface_count, int(_surface_family_counts.get("hidden_level", 0)), building_count]
    )


func _world(local_point: Vector2, y: float) -> Vector3:
    return MIDI_WORLD + Vector3(local_point.x, y, local_point.y)


func _ring(raw_polygon: Array) -> PackedVector2Array:
    var polygon: PackedVector2Array = PackedVector2Array()
    for raw: Variant in raw_polygon:
        if typeof(raw) != TYPE_ARRAY or raw.size() < 2:
            continue
        polygon.append(Vector2(float(raw[0]), float(raw[1])))
    if polygon.size() >= 2 and polygon[0].is_equal_approx(polygon[polygon.size() - 1]):
        polygon.remove_at(polygon.size() - 1)
    return polygon


func _new_tool(material: Material) -> SurfaceTool:
    var tool: SurfaceTool = SurfaceTool.new()
    tool.begin(Mesh.PRIMITIVE_TRIANGLES)
    tool.set_material(material)
    return tool


func _append_flat_polygon(tool: SurfaceTool, polygon: PackedVector2Array, y: float) -> bool:
    if polygon.size() < 3:
        return false
    var indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
    if indices.size() < 3:
        return false
    for raw_index: int in indices:
        var point: Vector2 = polygon[raw_index]
        tool.set_normal(Vector3.UP)
        tool.add_vertex(_world(point, y))
    return true


func _commit_tool(tool: SurfaceTool, name: String, root: Node3D, make_solid: bool = false) -> void:
    var mesh: ArrayMesh = tool.commit()
    if mesh.get_surface_count() == 0:
        return
    var instance: MeshInstance3D = MeshInstance3D.new()
    instance.name = name
    instance.mesh = mesh
    root.add_child(instance)
    if make_solid:
        instance.create_trimesh_collision()
        for child: Node in instance.get_children():
            if child is StaticBody3D:
                var static_body := child as StaticBody3D
                static_body.collision_layer = 1
                static_body.collision_mask = 1


func surface_family(surface_type: String, level: float) -> String:
    # Official meanings come from Paradigm UrbIS Land Cover product
    # specification, section 4.1.3.2. In particular I=intersection and
    # M=median/berm/roundabout; they must not be guessed from their initials.
    # Non-zero LVL surfaces are vertically distinct and cannot be flattened
    # into this street-level mesh.
    if not is_zero_approx(level):
        return "hidden_level"
    match surface_type:
        "S", "A", "AC", "B", "C", "I", "IC", "IL", "K", "SC":
            return "road"
        "SW", "G":
            return "sidewalk"
        "M":
            return "island"
        "P":
            return "paved"
        "MS", "MT", "RS", "RT":
            return "transit"
        _:
            return "other"


func surface_family_counts() -> Dictionary:
    return _surface_family_counts.duplicate()


func _build_street_surfaces(features: Array) -> int:
    var root: Node3D = Node3D.new()
    root.name = "UrbISStreetSurfaces"
    add_child(root)

    var road_tool: SurfaceTool = _new_tool(_road)
    var sidewalk_tool: SurfaceTool = _new_tool(_sidewalk)
    var island_tool: SurfaceTool = _new_tool(_island)
    var paved_tool: SurfaceTool = _new_tool(_paved)
    var other_tool: SurfaceTool = _new_tool(_other_surface)
    var count: int = 0
    _surface_family_counts = {
        "road": 0,
        "sidewalk": 0,
        "island": 0,
        "paved": 0,
        "transit": 0,
        "other": 0,
        "hidden_level": 0,
    }

    for feature: Dictionary in features:
        var polygon: PackedVector2Array = _ring(feature.get("polygon", []))
        var surface_type: String = str(feature.get("type", ""))
        var level: float = float(feature.get("level", 0.0))
        var family: String = surface_family(surface_type, level)
        _surface_family_counts[family] = int(_surface_family_counts.get(family, 0)) + 1
        if family == "hidden_level":
            continue
        var target: SurfaceTool = other_tool
        match family:
            "road":
                target = road_tool
            "sidewalk":
                target = sidewalk_tool
            "island":
                target = island_tool
            "paved":
                target = paved_tool
        if _append_flat_polygon(target, polygon, 0.075):
            count += 1

    _commit_tool(road_tool, "ExactRoadCarriageways", root)
    _commit_tool(sidewalk_tool, "ExactSidewalks", root)
    _commit_tool(island_tool, "ExactTrafficIslands", root)
    _commit_tool(paved_tool, "ExactPavedAreas", root)
    _commit_tool(other_tool, "ExactOtherStreetSurfaces", root)
    return count


func _building_bucket(id_text: String) -> int:
    var hash_value: int = 0
    for character: int in id_text.to_utf8_buffer():
        hash_value = (hash_value * 31 + character) & 0x7fffffff
    return hash_value % _building_materials.size()


func _append_building(tool: SurfaceTool, polygon: PackedVector2Array, height: float) -> bool:
    if polygon.size() < 3:
        return false
    var base_y: float = 0.10
    var top_y: float = maxf(base_y + 3.0, height)

    for index: int in range(polygon.size()):
        var a: Vector2 = polygon[index]
        var b: Vector2 = polygon[(index + 1) % polygon.size()]
        var edge: Vector2 = b - a
        if edge.length_squared() < 0.01:
            continue
        var normal: Vector3 = Vector3(-edge.y, 0.0, edge.x).normalized()
        var a0: Vector3 = _world(a, base_y)
        var b0: Vector3 = _world(b, base_y)
        var a1: Vector3 = _world(a, top_y)
        var b1: Vector3 = _world(b, top_y)
        for vertex: Vector3 in [a0, b0, b1, a0, b1, a1]:
            tool.set_normal(normal)
            tool.add_vertex(vertex)

    var roof_indices: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
    for raw_index: int in roof_indices:
        tool.set_normal(Vector3.UP)
        tool.add_vertex(_world(polygon[raw_index], top_y))
    return true


func _build_buildings(features: Array) -> int:
    var root: Node3D = Node3D.new()
    root.name = "UrbISExactBuildings"
    add_child(root)

    var tools: Array[SurfaceTool] = []
    for material: StandardMaterial3D in _building_materials:
        tools.append(_new_tool(material))

    var count: int = 0
    for feature: Dictionary in features:
        var polygon: PackedVector2Array = _ring(feature.get("footprint", []))
        if polygon.size() < 3:
            continue
        var height: float = float(feature.get("height", 10.0))
        var id_text: String = str(feature.get("id", ""))
        var bucket: int = _building_bucket(id_text)
        if _append_building(tools[bucket], polygon, height):
            count += 1

    for index: int in range(tools.size()):
        _commit_tool(tools[index], "ExactBuildings_%d" % index, root, true)
    return count
