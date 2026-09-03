extends Node

const DATA_PATH := "res://data/osm/zones/anneessens/environment.game.json"
const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)
const TREE_ASSET := preload("res://game/scripts/brussels_street_tree_asset.gd")
const VISUAL_OWNER_META := "shared_environment_visual_owner"
const VISUAL_OWNER_ID := "anneessens_osm_furniture_runtime"
const MAX_EXACT_JSON_INTEGER := 9007199254740991.0

@export var activation_radius_m: float = 170.0

var _scene: Node3D = null
var _player: Node3D = null
var _root: Node3D = null
var _tree_materials: Dictionary = {}
var _trees: Array[StaticBody3D] = []
var _enhanced_trees_enabled := true
var _manual_binding := false
var _watching_tree := false
var _tearing_down := false
var _tree_activation_initialized := false
var _tree_active := false

func _ready() -> void:
    _tearing_down = false
    process_mode = Node.PROCESS_MODE_ALWAYS
    _start_watching()
    call_deferred("_try_bind")

func _exit_tree() -> void:
    _tearing_down = true
    _stop_watching()
    _release_owned_root()
    _scene = null
    _player = null
    _manual_binding = false

func _process(_delta: float) -> void:
    if _tearing_down or not is_inside_tree():
        return
    if not is_instance_valid(_scene):
        _reset()
        _start_watching()
        call_deferred("_try_bind")
        return
    if not is_instance_valid(_player):
        _player = _scene.get_node_or_null("Player") as Node3D
    if is_instance_valid(_player) and not _player.is_inside_tree():
        _player = _scene.get_node_or_null("Player") as Node3D
    if is_instance_valid(_root) and _root.get_parent() != _scene:
        _release_owned_root()
    if not is_instance_valid(_player) or not _player.is_inside_tree():
        _apply_tree_activation(false)
        return
    if not is_instance_valid(_root):
        _build_once()
    if is_instance_valid(_root) and is_instance_valid(_player):
        var active := Vector2(_player.global_position.x - ANNEESSENS.x, _player.global_position.z - ANNEESSENS.z).length() <= activation_radius_m
        _apply_tree_activation(active)

func _start_watching() -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or _watching_tree:
        return
    var tree: SceneTree = get_tree()
    if tree == null:
        return
    if not tree.node_added.is_connected(_on_tree_node_added):
        tree.node_added.connect(_on_tree_node_added)
    if not tree.node_removed.is_connected(_on_tree_node_removed):
        tree.node_removed.connect(_on_tree_node_removed)
    _watching_tree = true

func _stop_watching() -> void:
    var tree: SceneTree = get_tree()
    if tree != null:
        if tree.node_added.is_connected(_on_tree_node_added):
            tree.node_added.disconnect(_on_tree_node_added)
        if tree.node_removed.is_connected(_on_tree_node_removed):
            tree.node_removed.disconnect(_on_tree_node_removed)
    _watching_tree = false

func _release_owned_root() -> void:
    if is_instance_valid(_root):
        var parent := _root.get_parent()
        if parent != null and not _tearing_down:
            parent.remove_child(_root)
        _root.queue_free()
    _root = null
    _trees.clear()
    _tree_materials.clear()
    _tree_activation_initialized = false
    _tree_active = false

func _on_tree_node_added(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or is_instance_valid(_scene):
        return
    var node_name := str(node.name)
    if node_name not in ["Main", "BrusselsOSM", "UrbISMidiExact", "Player"]:
        return
    call_deferred("_try_bind")

func _on_tree_node_removed(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or not is_instance_valid(_scene) or node != _scene:
        return
    _reset()
    _start_watching()
    call_deferred("_try_bind")

func _is_production_scene(candidate: Node3D) -> bool:
    return (
        candidate.get_node_or_null("BrusselsOSM") != null
        and candidate.get_node_or_null("UrbISMidiExact") != null
        and candidate.get_node_or_null("Player") is Node3D
    )

func _is_authoritative_production_scene(candidate: Node3D) -> bool:
    if candidate == null or not _is_production_scene(candidate) or not is_inside_tree():
        return false
    var tree: SceneTree = get_tree()
    if tree == null:
        return false
    if tree.current_scene == candidate:
        return true
    var parent := candidate.get_parent()
    if parent == tree.root:
        return true
    return (
        str(candidate.name) == "Main"
        and parent is Viewport
        and parent.get_parent() == tree.root
    )

func _find_nested_production_scene(node: Node) -> Node3D:
    if node is Node3D and _is_authoritative_production_scene(node as Node3D):
        return node as Node3D
    for child: Node in node.get_children():
        var nested := _find_nested_production_scene(child)
        if nested != null:
            return nested
    return null

func _find_production_scene() -> Node3D:
    if _tearing_down or not is_inside_tree():
        return null
    var tree: SceneTree = get_tree()
    if tree == null:
        return null
    var current := tree.current_scene
    if current is Node3D and _is_authoritative_production_scene(current as Node3D):
        return current as Node3D
    return _find_nested_production_scene(tree.root)

func _try_bind() -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or is_instance_valid(_scene):
        return
    var candidate := _find_production_scene()
    if candidate == null:
        return
    _bind_scene(candidate, false)

func bind_scene(scene: Node3D) -> void:
    if _tearing_down:
        return
    _bind_scene(scene, true)

func _bind_scene(scene: Node3D, manual: bool) -> void:
    if _tearing_down or scene == null:
        return
    if not manual and not is_inside_tree():
        return
    var player := scene.get_node_or_null("Player") as Node3D
    if player == null:
        return
    if is_instance_valid(_root) and _scene != scene:
        _release_owned_root()
    _manual_binding = manual
    _scene = scene
    _player = player
    if manual:
        _stop_watching()
    else:
        _start_watching()
    _build_once()

func _reset() -> void:
    _release_owned_root()
    _scene = null
    _player = null
    _manual_binding = false

func _collect_validated_tree_points(data: Dictionary) -> Variant:
    var environment_points: Variant = data.get("environment_points", null)
    if not environment_points is Array:
        push_error("Anneessens OSM furniture environment_points invalid")
        return null
    var validated: Array = []
    var seen_osm_ids: Dictionary = {}
    for raw: Variant in environment_points as Array:
        if not raw is Dictionary:
            push_error("Anneessens OSM furniture point invalid")
            return null
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "tree":
            continue
        var osm_id_value: Variant = point.get("osm_id", null)
        if typeof(osm_id_value) not in [TYPE_FLOAT, TYPE_INT]:
            push_error("Anneessens OSM tree osm_id must be numeric")
            return null
        var osm_id_number := float(osm_id_value)
        if not is_finite(osm_id_number) or osm_id_number <= 0.0 or osm_id_number > MAX_EXACT_JSON_INTEGER or floor(osm_id_number) != osm_id_number:
            push_error("Anneessens OSM tree osm_id must be a positive exact integer")
            return null
        var osm_id := int(osm_id_number)
        if seen_osm_ids.has(osm_id):
            push_error("Anneessens OSM tree osm_id duplicated")
            return null
        var position_value: Variant = point.get("position", null)
        if not position_value is Array or (position_value as Array).size() < 2:
            push_error("Anneessens OSM tree position invalid")
            return null
        var position := position_value as Array
        var x_value: Variant = position[0]
        var z_value: Variant = position[1]
        if typeof(x_value) not in [TYPE_FLOAT, TYPE_INT] or typeof(z_value) not in [TYPE_FLOAT, TYPE_INT]:
            push_error("Anneessens OSM tree coordinates must be numeric")
            return null
        var x := float(x_value)
        var z := float(z_value)
        if not is_finite(x) or not is_finite(z):
            push_error("Anneessens OSM tree coordinates must be finite")
            return null
        seen_osm_ids[osm_id] = true
        validated.append({"osm_id": osm_id, "position": Vector3(x, 0.0, z)})
    return validated

func _build_once() -> void:
    if _tearing_down or not is_instance_valid(_scene) or is_instance_valid(_root):
        return
    if not FileAccess.file_exists(DATA_PATH):
        push_warning("Anneessens OSM furniture data missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if not parsed is Dictionary:
        push_error("Anneessens OSM furniture JSON invalid")
        return
    var data := parsed as Dictionary
    if str(data.get("format", "")) != "grand-bruxelles-osm-zone-environment-v1":
        push_error("Anneessens OSM furniture schema invalid")
        return
    if str(data.get("zone", "")) != "anneessens":
        push_error("Anneessens OSM furniture zone invalid")
        return
    if str(data.get("source", "")) != "OpenStreetMap contributors via Overpass API":
        push_error("Anneessens OSM furniture source invalid")
        return
    if str(data.get("license", "")) != "ODbL-1.0":
        push_error("Anneessens OSM furniture license missing")
        return
    if str(data.get("coordinate_space", "")) != "game_xz_m":
        push_error("Anneessens OSM furniture coordinate space invalid")
        return

    var validated_tree_points: Variant = _collect_validated_tree_points(data)
    if validated_tree_points == null:
        return
    var tree_points := validated_tree_points as Array

    _root = Node3D.new()
    _root.name = "AnneessensOsmFurniture"
    _root.set_meta("source", str(data.get("source", "")))
    _root.set_meta("license", str(data.get("license", "")))
    _root.set_meta("placement_source_backed", true)
    _root.set_meta("visual_dimensions_source_backed", false)
    _root.set_meta("source_height_measured", false)
    _root.set_meta("source_species_measured", false)
    _scene.add_child(_root)
    _tree_materials = TREE_ASSET.create_materials()

    for tree_point: Variant in tree_points:
        var validated_point := tree_point as Dictionary
        var world_position: Vector3 = validated_point["position"]
        _add_tree(int(validated_point["osm_id"]), world_position)

    _tree_activation_initialized = false
    var active := Vector2(_player.global_position.x - ANNEESSENS.x, _player.global_position.z - ANNEESSENS.z).length() <= activation_radius_m
    _apply_tree_activation(active)
    print("ANNEESSENS_OSM_FURNITURE_READY: trees=%d asset_family=%s source=OSM license=ODbL-1.0" % [tree_points.size(), TREE_ASSET.ASSET_FAMILY])

func _apply_tree_activation(active: bool) -> void:
    if not is_instance_valid(_root):
        _tree_active = active
        _tree_activation_initialized = false
        return
    if _tree_activation_initialized and _tree_active == active:
        return
    _tree_active = active
    _tree_activation_initialized = true
    _root.visible = active
    for tree: StaticBody3D in _trees:
        if not is_instance_valid(tree):
            continue
        var collision := tree.get_node_or_null("CollisionShape3D") as CollisionShape3D
        if collision != null:
            collision.disabled = not active

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

func _is_owned_tree_visual(node: Node) -> bool:
    return str(node.get_meta(VISUAL_OWNER_META, "")) == VISUAL_OWNER_ID

func _mark_owned_tree_visual(node: Node) -> void:
    if node != null:
        node.set_meta(VISUAL_OWNER_META, VISUAL_OWNER_ID)

func _remove_owned_tree_visuals(tree: StaticBody3D) -> void:
    for child: Node in tree.get_children():
        if not _is_owned_tree_visual(child):
            continue
        tree.remove_child(child)
        child.queue_free()

func _rebuild_tree_visual(tree: StaticBody3D) -> void:
    _remove_owned_tree_visuals(tree)
    var osm_id := int(tree.get_meta("osm_id", 0))
    if _enhanced_trees_enabled:
        var enhanced_visual := TREE_ASSET.populate(tree, osm_id, _tree_materials)
        _mark_owned_tree_visual(enhanced_visual)
        return
    tree.set_meta("asset_family", "legacy_primitive_tree")
    tree.set_meta("source_dimensions_measured", false)
    tree.set_meta("species_claimed", false)
    var legacy := Node3D.new()
    legacy.name = "LegacyTreeVisual"
    _mark_owned_tree_visual(legacy)
    tree.add_child(legacy)
    var trunk_mesh := MeshInstance3D.new()
    trunk_mesh.name = "Trunk"
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = 0.16
    cylinder.bottom_radius = 0.21
    cylinder.height = 2.6
    trunk_mesh.mesh = cylinder
    trunk_mesh.material_override = _tree_materials["trunk"] as Material
    trunk_mesh.position.y = 1.3
    legacy.add_child(trunk_mesh)
    var crown := MeshInstance3D.new()
    crown.name = "Crown"
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

func enhanced_trees_enabled() -> bool:
    return _enhanced_trees_enabled

func tree_count() -> int:
    return _trees.size()
