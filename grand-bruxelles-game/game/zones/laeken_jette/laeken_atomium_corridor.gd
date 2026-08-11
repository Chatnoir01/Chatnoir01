extends Node3D

## Photo-guided Atomium approach corridor.
## Position/orientation comes from the nearest official UrbIS StreetAxes segment.
## Furniture spacing and lateral offsets remain explicitly provisional until a
## dedicated street-furniture / orthophoto / LiDAR pass is available.

const DATA_PATH := "res://data/urbis/laeken_jette/street_axes.game.json"
const ATOMIUM := Vector2(224.92615906274295, -6553.143077999353)
const HALF_LENGTH_M := 260.0
const MAX_RADIUS_M := 340.0

var official_axis_distance_m: float = INF
var official_axis_origin: Vector2 = Vector2.ZERO
var official_axis_direction: Vector2 = Vector2.UP
var generated_trees: int = 0
var generated_lamps: int = 0
var generated_dashes: int = 0

var _tree_trunk: StandardMaterial3D
var _tree_leaf: StandardMaterial3D
var _tree_leaf_dark: StandardMaterial3D
var _lamp_metal: StandardMaterial3D
var _lamp_head: StandardMaterial3D
var _road_marking: StandardMaterial3D


func _ready() -> void:
    call_deferred("_build")


func _build() -> void:
    _make_materials()
    if not _resolve_official_axis():
        push_warning("Atomium corridor: no official UrbIS StreetAxes segment found")
        return
    _build_corridor()
    print("LAEKEN_ATOMIUM_CORRIDOR_READY: axis_distance=%.2f trees=%d lamps=%d dashes=%d" % [official_axis_distance_m, generated_trees, generated_lamps, generated_dashes])


func _make_materials() -> void:
    _tree_trunk = _material(Color(0.18, 0.105, 0.055, 1.0), 0.98)
    _tree_leaf = _material(Color(0.055, 0.18, 0.065, 1.0), 0.96)
    _tree_leaf_dark = _material(Color(0.035, 0.125, 0.045, 1.0), 0.97)
    _lamp_metal = _material(Color(0.14, 0.15, 0.16, 1.0), 0.34, 0.72)
    _lamp_head = _material(Color(0.91, 0.88, 0.74, 1.0), 0.28, 0.05)
    _road_marking = _material(Color(0.91, 0.90, 0.83, 1.0), 0.92)


func _material(color: Color, roughness: float, metallic: float = 0.0) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material


func _terrain_y(xz: Vector2) -> float:
    var terrain := get_parent().get_node_or_null("LaekenTerrain")
    if terrain != null and terrain.has_method("sample_height"):
        return float(terrain.call("sample_height", xz.x, xz.y))
    return 0.0


func _load_data() -> Dictionary:
    if not FileAccess.file_exists(DATA_PATH):
        return {}
    var file := FileAccess.open(DATA_PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}


func _line_strings(geometry: Dictionary) -> Array:
    var result: Array = []
    var kind := String(geometry.get("type", ""))
    var coordinates = geometry.get("coordinates", [])
    if kind == "LineString" and coordinates is Array:
        result.append(coordinates)
    elif kind == "MultiLineString" and coordinates is Array:
        for line in coordinates:
            if line is Array:
                result.append(line)
    return result


func _closest_on_segment(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
    var delta := b - a
    var denominator := delta.length_squared()
    if denominator < 0.000001:
        return a
    var t := clampf((point - a).dot(delta) / denominator, 0.0, 1.0)
    return a + delta * t


func _resolve_official_axis() -> bool:
    var data := _load_data()
    var features = data.get("features", [])
    if not (features is Array):
        return false

    for feature in features:
        if not (feature is Dictionary):
            continue
        var geometry = feature.get("geometry", {})
        if not (geometry is Dictionary):
            continue
        for line in _line_strings(geometry):
            if not (line is Array) or line.size() < 2:
                continue
            for index in range(line.size() - 1):
                var raw_a = line[index]
                var raw_b = line[index + 1]
                if not (raw_a is Array and raw_b is Array and raw_a.size() >= 2 and raw_b.size() >= 2):
                    continue
                var a := Vector2(float(raw_a[0]), float(raw_a[1]))
                var b := Vector2(float(raw_b[0]), float(raw_b[1]))
                var delta := b - a
                if delta.length_squared() < 0.01:
                    continue
                var closest := _closest_on_segment(ATOMIUM, a, b)
                var distance := closest.distance_to(ATOMIUM)
                if distance < official_axis_distance_m:
                    official_axis_distance_m = distance
                    official_axis_origin = closest
                    official_axis_direction = delta.normalized()
    return official_axis_distance_m < INF


func _build_corridor() -> void:
    var start := official_axis_origin - official_axis_direction * HALF_LENGTH_M
    var side := Vector2(-official_axis_direction.y, official_axis_direction.x)

    var distance := 8.0
    while distance < HALF_LENGTH_M * 2.0 - 4.0:
        var centre := start + official_axis_direction * distance
        if centre.distance_to(ATOMIUM) <= MAX_RADIUS_M:
            _add_box("LaneDash", Vector3(0.14, 0.025, 3.8), Vector3(centre.x, _terrain_y(centre) + 0.08, centre.y), atan2(official_axis_direction.x, official_axis_direction.y), _road_marking)
            generated_dashes += 1
        distance += 10.0

    distance = 18.0
    while distance < HALF_LENGTH_M * 2.0:
        var centre_tree := start + official_axis_direction * distance
        if centre_tree.distance_to(ATOMIUM) <= MAX_RADIUS_M and centre_tree.distance_to(ATOMIUM) >= 32.0:
            for side_sign in [-1.0, 1.0]:
                var tree_pos: Vector2 = centre_tree + side * 12.5 * float(side_sign)
                _add_tree(tree_pos)
                generated_trees += 1
        distance += 24.0

    distance = 12.0
    while distance < HALF_LENGTH_M * 2.0:
        var centre_lamp := start + official_axis_direction * distance
        if centre_lamp.distance_to(ATOMIUM) <= MAX_RADIUS_M and centre_lamp.distance_to(ATOMIUM) >= 28.0:
            for side_sign in [-1.0, 1.0]:
                var lamp_pos: Vector2 = centre_lamp + side * 8.7 * float(side_sign)
                _add_lamp(lamp_pos)
                generated_lamps += 1
        distance += 32.0


func _add_tree(xz: Vector2) -> void:
    var tree := Node3D.new()
    tree.name = "PhotoGuidedTree"
    tree.position = Vector3(xz.x, _terrain_y(xz), xz.y)
    add_child(tree)

    # Deterministic variation from position keeps the corridor lightweight while
    # avoiding the repeated perfect-sphere placeholder look.
    var seed := absf(sin(xz.x * 0.031 + xz.y * 0.017))
    var trunk_height := 4.1 + seed * 1.1
    var crown_radius := 1.85 + seed * 0.55

    var trunk := CylinderMesh.new()
    trunk.top_radius = 0.18 + seed * 0.04
    trunk.bottom_radius = 0.30 + seed * 0.05
    trunk.height = trunk_height
    trunk.radial_segments = 7
    trunk.material = _tree_trunk
    var trunk_instance := MeshInstance3D.new()
    trunk_instance.mesh = trunk
    trunk_instance.position.y = trunk_height * 0.5
    tree.add_child(trunk_instance)

    var crown_y := trunk_height + 1.15
    _add_leaf_lobe(tree, Vector3(0.0, crown_y + 0.65, 0.0), crown_radius, _tree_leaf)
    _add_leaf_lobe(tree, Vector3(crown_radius * 0.58, crown_y + 0.15, 0.15), crown_radius * 0.72, _tree_leaf_dark)
    _add_leaf_lobe(tree, Vector3(-crown_radius * 0.52, crown_y + 0.10, -0.22), crown_radius * 0.76, _tree_leaf)
    _add_leaf_lobe(tree, Vector3(0.10, crown_y - 0.10, crown_radius * 0.55), crown_radius * 0.68, _tree_leaf_dark)
    _add_leaf_lobe(tree, Vector3(-0.18, crown_y + 0.05, -crown_radius * 0.55), crown_radius * 0.70, _tree_leaf)


func _add_leaf_lobe(parent: Node3D, position: Vector3, radius: float, material: Material) -> void:
    var crown := SphereMesh.new()
    crown.radius = radius
    crown.height = radius * 1.85
    crown.radial_segments = 8
    crown.rings = 5
    crown.material = material
    var crown_instance := MeshInstance3D.new()
    crown_instance.name = "LeafCluster"
    crown_instance.mesh = crown
    crown_instance.position = position
    parent.add_child(crown_instance)


func _add_lamp(xz: Vector2) -> void:
    var lamp := Node3D.new()
    lamp.name = "PhotoGuidedLamp"
    lamp.position = Vector3(xz.x, _terrain_y(xz), xz.y)
    add_child(lamp)

    var pole := CylinderMesh.new()
    pole.top_radius = 0.075
    pole.bottom_radius = 0.105
    pole.height = 7.4
    pole.radial_segments = 8
    pole.material = _lamp_metal
    var pole_instance := MeshInstance3D.new()
    pole_instance.mesh = pole
    pole_instance.position.y = 3.7
    lamp.add_child(pole_instance)

    var head := BoxMesh.new()
    head.size = Vector3(0.30, 0.14, 0.78)
    head.material = _lamp_head
    var head_instance := MeshInstance3D.new()
    head_instance.mesh = head
    head_instance.position.y = 7.32
    lamp.add_child(head_instance)


func _add_box(node_name: String, size: Vector3, position: Vector3, rotation_y: float, material: Material) -> void:
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    var instance := MeshInstance3D.new()
    instance.name = node_name
    instance.mesh = mesh
    instance.position = position
    instance.rotation.y = rotation_y
    add_child(instance)
