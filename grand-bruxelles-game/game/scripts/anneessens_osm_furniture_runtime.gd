extends Node

const DATA_PATH := "res://data/osm/anneessens_environment_points.game.json"
const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)
const TREE_ASSET := preload("res://game/scripts/brussels_street_tree_asset.gd")

@export var activation_radius_m: float = 170.0

var _scene: Node3D = null
var _player: Node3D = null
var _root: Node3D = null
var _tree_materials: Dictionary = {}
var _trees: Array[StaticBody3D] = []
var _enhanced_trees_enabled := true

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_try_bind")

func _process(_delta: float) -> void:
    if not is_instance_valid(_scene) or get_tree().current_scene != _scene:
        _reset()
        _try_bind()
        return
    if not is_instance_valid(_player):
        _player = _scene.get_node_or_null("Player") as Node3D
    if is_instance_valid(_root) and is_instance_valid(_player):
        _root.visible = Vector2(_player.global_position.x - ANNEESSENS.x, _player.global_position.z - ANNEESSENS.z).length() <= activation_radius_m

func _try_bind() -> void:
    var current := get_tree().current_scene
    if current == null or not current is Node3D:
        return
    var player := current.get_node_or_null("Player") as Node3D
    if player == null:
        return
    _scene = current as Node3D
    _player = player
    _build_once()

func _reset() -> void:
    _scene = null
    _player = null
    _root = null
    _trees.clear()
    _tree_materials.clear()

func _build_once() -> void:
    if not is_instance_valid(_scene) or is_instance_valid(_root):
        return
    if not FileAccess.file_exists(DATA_PATH):
        push_warning("Anneessens OSM furniture data missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not parsed is Dictionary:
        push_error("Anneessens OSM furniture JSON invalid")
        return
    var data := parsed as Dictionary
    if str(data.get("format", "")) != "grand-bruxelles-osm-environment-points-v1":
        push_error("Anneessens OSM furniture schema invalid")
        return
    if str(data.get("license", "")) != "ODbL-1.0":
        push_error("Anneessens OSM furniture license missing")
        return

    _root = Node3D.new()
    _root.name = "AnneessensOsmFurniture"
    _scene.add_child(_root)
    _tree_materials = TREE_ASSET.create_materials()

    var built := 0
    for raw: Variant in data.get("points", []):
        if not raw is Dictionary:
            continue
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "tree":
            continue
        var position_value: Variant = point.get("position", null)
        if not position_value is Array or (position_value as Array).size() < 2:
            continue
        var position := position_value as Array
        _add_tree(int(point.get("osm_id", 0)), Vector3(float(position[0]), 0.0, float(position[1])))
        built += 1

    _root.visible = Vector2(_player.global_position.x - ANNEESSENS.x, _player.global_position.z - ANNEESSENS.z).length() <= activation_radius_m
    print("ANNEESSENS_OSM_FURNITURE_READY: trees=%d asset_family=%s source=OSM license=ODbL-1.0" % [built, TREE_ASSET.ASSET_FAMILY])

func _add_tree(osm_id: int, world_position: Vector3) -> void:
    var tree := StaticBody3D.new()
    tree.name = "OsmTree_%d" % osm_id
    tree.position = world_position
    tree.add_to_group("osm_environment_furniture")
    tree.set_meta("osm_id", osm_id)
    tree.set_meta("source", "OpenStreetMap contributors via Overpass API")
    tree.set_meta("license", "ODbL-1.0")
    _root.add_child(tree)
    _trees.append(tree)

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var shape := CylinderShape3D.new()
    shape.radius = 0.28
    shape.height = 2.6
    collision.shape = shape
    collision.position.y = 1.3
    tree.add_child(collision)

    _rebuild_tree_visual(tree)

func _rebuild_tree_visual(tree: StaticBody3D) -> void:
    for child_name: String in ["StreetTreeVisual", "LegacyTreeVisual"]:
        var existing := tree.get_node_or_null(child_name)
        if existing != null:
            existing.queue_free()
    var osm_id := int(tree.get_meta("osm_id", 0))
    if _enhanced_trees_enabled:
        TREE_ASSET.populate(tree, osm_id, _tree_materials)
        return
    tree.set_meta("asset_family", "legacy_primitive_tree")
    tree.set_meta("source_dimensions_measured", false)
    tree.set_meta("species_claimed", false)
    var legacy := Node3D.new()
    legacy.name = "LegacyTreeVisual"
    tree.add_child(legacy)
    var trunk_mesh := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.16
    cylinder.bottom_radius = 0.21
    cylinder.height = 2.6
    trunk_mesh.mesh = cylinder
    trunk_mesh.material_override = _tree_materials["trunk"] as Material
    trunk_mesh.position.y = 1.3
    legacy.add_child(trunk_mesh)
    var crown := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radius = 1.45
    sphere.height = 2.9
    crown.mesh = sphere
    crown.material_override = _tree_materials["foliage_dark"] as Material
    crown.position.y = 3.15
    legacy.add_child(crown)

func set_enhanced_trees_enabled(enabled: bool) -> void:
    if _enhanced_trees_enabled == enabled:
        return
    _enhanced_trees_enabled = enabled
    for tree: StaticBody3D in _trees:
        if is_instance_valid(tree):
            _rebuild_tree_visual(tree)
    await get_tree().process_frame

func enhanced_trees_enabled() -> bool:
    return _enhanced_trees_enabled

func tree_count() -> int:
    return _trees.size()
