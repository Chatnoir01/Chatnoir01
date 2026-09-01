extends Node

const DATA_PATH := "res://data/osm/vertical_slice_01.game.json"
const ANNEESSENS_DATA_PATH := "res://data/osm/anneessens_environment_points.game.json"
const ASSET := preload("res://game/scripts/brussels_street_tree_asset.gd")
const EXPECTED_SOURCE_TREE_COUNT := 273
const EXPECTED_PREOWNED_TREE_COUNT := 7
const EXPECTED_RUNTIME_TREE_COUNT := 266
const POSITION_EPSILON_M := 0.0005
const FAR_LOBE_INDICES := [0, 3, 6]

@export var tree_full_detail_radius_m := 140.0
@export var tree_lod_rebuild_distance_m := 45.0

var _root: Node3D = null
var _scene: Node3D = null
var _trunk_batch: MultiMeshInstance3D = null
var _dark_batch: MultiMeshInstance3D = null
var _light_batch: MultiMeshInstance3D = null
var _collision_body: StaticBody3D = null
var _source_positions: Array[Vector3] = []
var _source_ids: Array[int] = []
var _enhanced_materials: Dictionary = {}
var _legacy_materials: Dictionary = {}
var _ready_complete := false
var _failed := false
var _visual_enabled := true
var _material_enhanced_enabled := true
var _manual_binding := false
var _lod_active := false
var _last_lod_anchor := Vector3(INF, INF, INF)
var _near_tree_count := 0
var _far_tree_count := 0
var _foliage_instance_count := 0
var _tearing_down := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    if not get_tree().node_removed.is_connected(_on_tree_node_removed):
        get_tree().node_removed.connect(_on_tree_node_removed)
    call_deferred("_start_scene_watch")

func _exit_tree() -> void:
    _tearing_down = true
    if is_inside_tree() and get_tree().node_removed.is_connected(_on_tree_node_removed):
        get_tree().node_removed.disconnect(_on_tree_node_removed)
    _disconnect_scene_watch()
    _release_owned_root()
    _scene = null

func _release_owned_root() -> void:
    if is_instance_valid(_root):
        var parent := _root.get_parent()
        if parent != null:
            parent.remove_child(_root)
        _root.queue_free()
    _root = null
    _trunk_batch = null
    _dark_batch = null
    _light_batch = null
    _collision_body = null
    _source_positions.clear()
    _source_ids.clear()
    _enhanced_materials.clear()
    _legacy_materials.clear()
    _lod_active = false
    _last_lod_anchor = Vector3(INF, INF, INF)
    _near_tree_count = 0
    _far_tree_count = 0
    _foliage_instance_count = 0

func _process(_delta: float) -> void:
    if _tearing_down or not _ready_complete or _failed or not is_instance_valid(_scene) or _source_positions.is_empty():
        return
    var anchor := _player_anchor()
    if not is_finite(anchor.x):
        return
    var relevant := lod_anchor_is_corridor_relevant(anchor, _source_positions)
    if relevant != _lod_active:
        _rebuild_visual_batches(anchor, relevant)
        return
    if relevant and (not is_finite(_last_lod_anchor.x) or _xz_distance(anchor, _last_lod_anchor) >= tree_lod_rebuild_distance_m):
        _rebuild_visual_batches(anchor, true)

func _scene_has_production_anchors(candidate: Node3D) -> bool:
    if candidate == null or not is_instance_valid(candidate):
        return false
    return candidate.get_node_or_null("BrusselsOSM/GeneratedRoads") != null \
        and candidate.get_node_or_null("UrbISMidiExact") != null \
        and candidate.get_node_or_null("Player") != null

func _scene_has_runtime_authority(candidate: Node3D) -> bool:
    if candidate == null or not is_instance_valid(candidate) or not is_inside_tree():
        return false
    if not _scene_has_production_anchors(candidate):
        return false
    if get_tree().current_scene == candidate:
        return true
    var parent := candidate.get_parent()
    if parent == get_tree().root:
        return true
    if parent is Viewport and parent.get_parent() == get_tree().root:
        return true
    return false

func _production_scene_from_node(node: Node) -> Node3D:
    var cursor: Node = node
    while cursor != null:
        if cursor is Node3D and _scene_has_runtime_authority(cursor as Node3D):
            return cursor as Node3D
        cursor = cursor.get_parent()
    return null

func _discover_production_scene() -> Node3D:
    if _tearing_down or not is_inside_tree():
        return null
    var current := get_tree().current_scene
    if current is Node3D and _scene_has_runtime_authority(current as Node3D):
        return current as Node3D
    for child: Node in get_tree().root.get_children():
        if child is Node3D and _scene_has_runtime_authority(child as Node3D):
            return child as Node3D
        if child is Viewport:
            for viewport_child: Node in child.get_children():
                if viewport_child is Node3D and _scene_has_runtime_authority(viewport_child as Node3D):
                    return viewport_child as Node3D
    return null

func _disconnect_scene_watch() -> void:
    if not is_inside_tree():
        return
    var callback := Callable(self, "_on_tree_node_added")
    if get_tree().node_added.is_connected(callback):
        get_tree().node_added.disconnect(callback)

func _try_bind_scene(candidate: Node3D) -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or _ready_complete or candidate == null or not _scene_has_runtime_authority(candidate):
        return
    _disconnect_scene_watch()
    _scene = candidate
    _build()

func _on_tree_node_added(node: Node) -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or _ready_complete:
        _disconnect_scene_watch()
        return
    if str(node.name) not in ["GeneratedRoads", "UrbISMidiExact", "Player"]:
        return
    var candidate := _production_scene_from_node(node)
    if candidate != null:
        call_deferred("_try_bind_scene", candidate)

func _on_tree_node_removed(node: Node) -> void:
    if _tearing_down or _manual_binding or not _ready_complete or node != _scene:
        return
    _release_owned_root()
    _scene = null
    _ready_complete = false
    _failed = false
    call_deferred("_start_scene_watch")

func _start_scene_watch() -> void:
    if _tearing_down or not is_inside_tree() or _manual_binding or _ready_complete:
        return
    var callback := Callable(self, "_on_tree_node_added")
    if not get_tree().node_added.is_connected(callback):
        get_tree().node_added.connect(callback)
    _try_bind_scene(_discover_production_scene())

func bind_scene(scene: Node3D) -> void:
    if _tearing_down:
        return
    if scene == null:
        _fail("manual scene binding received null scene")
        return
    _disconnect_scene_watch()
    _release_owned_root()
    _scene = scene
    _manual_binding = true
    _ready_complete = false
    _failed = false
    _build()

func _fail(message: String) -> void:
    if _tearing_down:
        return
    _disconnect_scene_watch()
    push_error("Brussels corridor tree runtime: %s" % message)
    _failed = true
    _ready_complete = true

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path): return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null: return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _preowned_tree_ids() -> Dictionary:
    var data := _load_json(ANNEESSENS_DATA_PATH)
    var ids := {}
    for raw: Variant in data.get("points", []):
        if raw is Dictionary:
            var point := raw as Dictionary
            if str(point.get("kind", "")) == "tree": ids[int(point.get("osm_id", 0))] = true
    return ids

func _build_batch(name: String, mesh: Mesh, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.instance_count = transforms.size()
    multimesh.mesh = mesh
    for index: int in range(transforms.size()): multimesh.set_instance_transform(index, transforms[index])
    multimesh.visible_instance_count = transforms.size()
    var batch := MultiMeshInstance3D.new()
    batch.name = name
    batch.multimesh = multimesh
    return batch

func _xz_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x - b.x, a.z - b.z).length()

func _player_anchor() -> Vector3:
    if not is_instance_valid(_scene):
        return Vector3(INF, INF, INF)
    var player := _scene.get_node_or_null("Player") as Node3D
    if player == null:
        return Vector3(INF, INF, INF)
    return player.global_position

func foliage_lobe_indices_for_distance(distance_m: float) -> Array:
    if distance_m <= tree_full_detail_radius_m:
        return range(ASSET.FOLIAGE_LOBE_COUNT)
    return FAR_LOBE_INDICES.duplicate()

func lod_anchor_is_corridor_relevant(anchor: Vector3, positions: Array[Vector3]) -> bool:
    if not is_finite(anchor.x) or positions.is_empty():
        return false
    for position: Vector3 in positions:
        if _xz_distance(anchor, position) <= tree_full_detail_radius_m:
            return true
    return false

func _detach_visual_batch(batch: MultiMeshInstance3D) -> void:
    if not is_instance_valid(batch):
        return
    if batch.get_parent() != null:
        batch.get_parent().remove_child(batch)
    batch.queue_free()

func _rebuild_visual_batches(anchor: Vector3, use_lod: bool) -> void:
    if _tearing_down or not is_instance_valid(_root) or _enhanced_materials.is_empty():
        return
    _detach_visual_batch(_trunk_batch)
    _detach_visual_batch(_dark_batch)
    _detach_visual_batch(_light_batch)
    _trunk_batch = null
    _dark_batch = null
    _light_batch = null

    var trunk_transforms: Array[Transform3D] = []
    var dark_transforms: Array[Transform3D] = []
    var light_transforms: Array[Transform3D] = []
    var near_count := 0
    var far_count := 0
    for index: int in range(_source_positions.size()):
        var base := _source_positions[index]
        var osm_id := _source_ids[index]
        trunk_transforms.append(ASSET.trunk_transform(base))
        var distance_m := _xz_distance(anchor, base) if use_lod else 0.0
        var lobe_indices := foliage_lobe_indices_for_distance(distance_m)
        if use_lod and distance_m > tree_full_detail_radius_m:
            far_count += 1
        else:
            near_count += 1
        for lobe_variant: Variant in lobe_indices:
            var lobe_index := int(lobe_variant)
            var transform: Transform3D = ASSET.foliage_lobe_transform(base, osm_id, lobe_index)
            if ASSET.foliage_is_light(lobe_index): light_transforms.append(transform)
            else: dark_transforms.append(transform)

    _trunk_batch = _build_batch("TreeTrunks", ASSET.create_trunk_mesh(_enhanced_materials["trunk"] as Material), trunk_transforms)
    _dark_batch = _build_batch("TreeFoliageDark", ASSET.create_foliage_mesh(_enhanced_materials["foliage_dark"] as Material), dark_transforms)
    _light_batch = _build_batch("TreeFoliageLight", ASSET.create_foliage_mesh(_enhanced_materials["foliage_light"] as Material), light_transforms)
    _root.add_child(_trunk_batch)
    _root.add_child(_dark_batch)
    _root.add_child(_light_batch)
    _near_tree_count = near_count
    _far_tree_count = far_count
    _foliage_instance_count = dark_transforms.size() + light_transforms.size()
    _lod_active = use_lod
    _last_lod_anchor = anchor if use_lod else Vector3(INF, INF, INF)
    set_material_enhanced_enabled(_material_enhanced_enabled)
    set_visual_enabled(_visual_enabled)

func rebuild_visual_batches_for_anchor(anchor: Vector3) -> void:
    if _tearing_down:
        return
    _rebuild_visual_batches(anchor, lod_anchor_is_corridor_relevant(anchor, _source_positions))

func _build() -> void:
    if _tearing_down:
        return
    if not is_instance_valid(_scene):
        _fail("scene missing during build")
        return
    var data := _load_json(DATA_PATH)
    if data.is_empty():
        _fail("vertical-slice source payload missing")
        return
    if str(data.get("source", "")) != "OpenStreetMap contributors via Overpass API" or str(data.get("license", "")) != "ODbL-1.0":
        _fail("source provenance changed")
        return
    var preowned := _preowned_tree_ids()
    if preowned.size() != EXPECTED_PREOWNED_TREE_COUNT:
        _fail("Anneessens pre-owned tree contract changed: %d" % preowned.size())
        return

    var all_source_tree_count := 0
    for raw: Variant in data.get("environment_points", []):
        if not raw is Dictionary: continue
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "tree": continue
        all_source_tree_count += 1
        var osm_id := int(point.get("osm_id", 0))
        if preowned.has(osm_id): continue
        var position_value := point.get("position", []) as Array
        if position_value.size() != 2:
            _fail("malformed source tree position")
            return
        var base := Vector3(float(position_value[0]), 0.0, float(position_value[1]))
        _source_ids.append(osm_id)
        _source_positions.append(base)
    if all_source_tree_count != EXPECTED_SOURCE_TREE_COUNT:
        _fail("source tree count changed: %d" % all_source_tree_count)
        return
    if _source_positions.size() != EXPECTED_RUNTIME_TREE_COUNT:
        _fail("runtime tree count changed: %d" % _source_positions.size())
        return

    _enhanced_materials = ASSET.create_materials()
    _legacy_materials = ASSET.create_legacy_materials()
    _root = Node3D.new()
    _root.name = "BrusselsCorridorTrees"
    _root.set_meta("asset_family", ASSET.ASSET_FAMILY)
    _root.set_meta("silhouette_revision", ASSET.SILHOUETTE_REVISION)
    _root.set_meta("material_revision", ASSET.MATERIAL_REVISION)
    _root.set_meta("source", "OpenStreetMap contributors via Overpass API")
    _root.set_meta("license", "ODbL-1.0")
    _root.set_meta("species_claimed", false)
    _root.set_meta("source_dimensions_measured", false)
    _root.set_meta("season_claimed", false)
    _root.set_meta("health_claimed", false)
    _root.set_meta("geometry_changed_by_tree_material", false)
    _scene.add_child(_root)

    var anchor := _player_anchor()
    var activate_lod := lod_anchor_is_corridor_relevant(anchor, _source_positions)
    _rebuild_visual_batches(anchor if is_finite(anchor.x) else Vector3.ZERO, activate_lod)

    _collision_body = StaticBody3D.new()
    _collision_body.name = "TreeCollisions"
    _root.add_child(_collision_body)
    for base: Vector3 in _source_positions:
        var collision := CollisionShape3D.new()
        var shape := CylinderShape3D.new()
        shape.radius = 0.28
        shape.height = ASSET.TRUNK_HEIGHT
        collision.shape = shape
        collision.position = base + Vector3(0.0, ASSET.TRUNK_HEIGHT * 0.5, 0.0)
        _collision_body.add_child(collision)

    _ready_complete = true
    print("BRUSSELS_CORRIDOR_TREES_READY: source_trees=%d preowned=%d runtime_trees=%d batches=%d material_revision=%d lod_active=%s near=%d far=%d foliage_instances=%d source=OSM license=ODbL-1.0" % [all_source_tree_count, preowned.size(), _source_positions.size(), batch_count(), ASSET.MATERIAL_REVISION, str(_lod_active), _near_tree_count, _far_tree_count, _foliage_instance_count])

func _set_batch_material(batch: MultiMeshInstance3D, material: Material) -> void:
    if not is_instance_valid(batch) or batch.multimesh == null or batch.multimesh.mesh == null:
        return
    batch.multimesh.mesh.material = material

func set_material_enhanced_enabled(enabled: bool) -> void:
    _material_enhanced_enabled = enabled
    if _enhanced_materials.is_empty() or _legacy_materials.is_empty():
        return
    var materials := _enhanced_materials if enabled else _legacy_materials
    _set_batch_material(_trunk_batch, materials["trunk"] as Material)
    _set_batch_material(_dark_batch, materials["foliage_dark"] as Material)
    _set_batch_material(_light_batch, materials["foliage_light"] as Material)

func material_enhanced_enabled() -> bool:
    return _material_enhanced_enabled

func set_visual_enabled(enabled: bool) -> void:
    _visual_enabled = enabled
    for batch: MultiMeshInstance3D in [_trunk_batch, _dark_batch, _light_batch]:
        if is_instance_valid(batch): batch.visible = enabled

func source_positions_unchanged() -> bool:
    if _source_positions.size() != _source_ids.size(): return false
    var data := _load_json(DATA_PATH)
    var preowned := _preowned_tree_ids()
    var index := 0
    for raw: Variant in data.get("environment_points", []):
        if not raw is Dictionary: continue
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "tree": continue
        var osm_id := int(point.get("osm_id", 0))
        if preowned.has(osm_id): continue
        if index >= _source_positions.size() or _source_ids[index] != osm_id: return false
        var position_value := point.get("position", []) as Array
        if position_value.size() != 2: return false
        var actual := _source_positions[index]
        if abs(actual.x - float(position_value[0])) > POSITION_EPSILON_M or abs(actual.z - float(position_value[1])) > POSITION_EPSILON_M: return false
        index += 1
    return index == _source_positions.size()

func ready_complete() -> bool: return _ready_complete
func failed() -> bool: return _failed
func tree_count() -> int: return _source_positions.size()
func total_source_tree_count() -> int: return EXPECTED_SOURCE_TREE_COUNT
func preowned_tree_count() -> int: return EXPECTED_PREOWNED_TREE_COUNT
func batch_count() -> int:
    var count := 0
    for batch: MultiMeshInstance3D in [_trunk_batch, _dark_batch, _light_batch]:
        if is_instance_valid(batch): count += 1
    return count
func collision_count() -> int: return _collision_body.get_child_count() if is_instance_valid(_collision_body) else 0
func source_positions() -> Array[Vector3]: return _source_positions.duplicate()
func source_ids() -> Array[int]: return _source_ids.duplicate()
func claims_species() -> bool: return false
func claims_measured_dimensions() -> bool: return false
func visual_enabled() -> bool: return _visual_enabled
func lod_active() -> bool: return _lod_active
func near_tree_count() -> int: return _near_tree_count
func far_tree_count() -> int: return _far_tree_count
func foliage_instance_count() -> int: return _foliage_instance_count
