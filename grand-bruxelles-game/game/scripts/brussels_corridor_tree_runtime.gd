extends Node

const DATA_PATH := "res://data/osm/vertical_slice_01.game.json"
const ANNEESSENS_DATA_PATH := "res://data/osm/anneessens_environment_points.game.json"
const ASSET := preload("res://game/scripts/brussels_street_tree_asset.gd")
const EXPECTED_SOURCE_TREE_COUNT := 273
const EXPECTED_PREOWNED_TREE_COUNT := 7
const EXPECTED_RUNTIME_TREE_COUNT := 266
const POSITION_EPSILON_M := 0.0005

var _root: Node3D = null
var _scene: Node3D = null
var _trunk_batch: MultiMeshInstance3D = null
var _dark_batch: MultiMeshInstance3D = null
var _light_batch: MultiMeshInstance3D = null
var _collision_body: StaticBody3D = null
var _source_positions: Array[Vector3] = []
var _source_ids: Array[int] = []
var _ready_complete := false
var _failed := false
var _visual_enabled := true
var _manual_binding := false

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_bind_when_ready")

func _bind_when_ready() -> void:
    for _attempt: int in range(180):
        if _manual_binding or _ready_complete:
            return
        var current := get_tree().current_scene
        if current is Node3D:
            _scene = current as Node3D
            _build()
            return
        await get_tree().process_frame
    if not _manual_binding and not _ready_complete:
        _fail("production scene missing")

func bind_scene(scene: Node3D) -> void:
    if scene == null:
        _fail("manual scene binding received null scene")
        return
    if is_instance_valid(_root):
        _root.queue_free()
    _scene = scene
    _manual_binding = true
    _root = null
    _trunk_batch = null
    _dark_batch = null
    _light_batch = null
    _collision_body = null
    _source_positions.clear()
    _source_ids.clear()
    _ready_complete = false
    _failed = false
    _build()

func _fail(message: String) -> void:
    push_error("Brussels corridor tree runtime: %s" % message)
    _failed = true
    _ready_complete = true

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _preowned_tree_ids() -> Dictionary:
    var data := _load_json(ANNEESSENS_DATA_PATH)
    var ids := {}
    for raw: Variant in data.get("points", []):
        if raw is Dictionary:
            var point := raw as Dictionary
            if str(point.get("kind", "")) == "tree":
                ids[int(point.get("osm_id", 0))] = true
    return ids

func _build_batch(name: String, mesh: Mesh, transforms: Array[Transform3D]) -> MultiMeshInstance3D:
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.instance_count = transforms.size()
    multimesh.mesh = mesh
    for index: int in range(transforms.size()):
        multimesh.set_instance_transform(index, transforms[index])
    multimesh.visible_instance_count = transforms.size()
    var batch := MultiMeshInstance3D.new()
    batch.name = name
    batch.multimesh = multimesh
    return batch

func _build() -> void:
    if _scene == null:
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
    var trunk_transforms: Array[Transform3D] = []
    var dark_transforms: Array[Transform3D] = []
    var light_transforms: Array[Transform3D] = []
    for raw: Variant in data.get("environment_points", []):
        if not raw is Dictionary:
            continue
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "tree":
            continue
        all_source_tree_count += 1
        var osm_id := int(point.get("osm_id", 0))
        if preowned.has(osm_id):
            continue
        var position_value := point.get("position", []) as Array
        if position_value.size() != 2:
            _fail("malformed source tree position")
            return
        var base := Vector3(float(position_value[0]), 0.0, float(position_value[1]))
        _source_ids.append(osm_id)
        _source_positions.append(base)
        trunk_transforms.append(ASSET.trunk_transform(base))
        for lobe_index: int in range(ASSET.FOLIAGE_LOBE_COUNT):
            var transform: Transform3D = ASSET.foliage_lobe_transform(base, osm_id, lobe_index)
            if ASSET.foliage_is_light(lobe_index):
                light_transforms.append(transform)
            else:
                dark_transforms.append(transform)
    if all_source_tree_count != EXPECTED_SOURCE_TREE_COUNT:
        _fail("source tree count changed: %d" % all_source_tree_count)
        return
    if _source_positions.size() != EXPECTED_RUNTIME_TREE_COUNT:
        _fail("runtime tree count changed: %d" % _source_positions.size())
        return

    var materials := ASSET.create_materials()
    _root = Node3D.new()
    _root.name = "BrusselsCorridorTrees"
    _root.set_meta("asset_family", ASSET.ASSET_FAMILY)
    _root.set_meta("source", "OpenStreetMap contributors via Overpass API")
    _root.set_meta("license", "ODbL-1.0")
    _root.set_meta("species_claimed", false)
    _root.set_meta("source_dimensions_measured", false)
    _scene.add_child(_root)

    _trunk_batch = _build_batch("TreeTrunks", ASSET.create_trunk_mesh(materials["trunk"] as Material), trunk_transforms)
    _dark_batch = _build_batch("TreeFoliageDark", ASSET.create_foliage_mesh(materials["foliage_dark"] as Material), dark_transforms)
    _light_batch = _build_batch("TreeFoliageLight", ASSET.create_foliage_mesh(materials["foliage_light"] as Material), light_transforms)
    _root.add_child(_trunk_batch)
    _root.add_child(_dark_batch)
    _root.add_child(_light_batch)

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

    set_visual_enabled(_visual_enabled)
    _ready_complete = true
    print("BRUSSELS_CORRIDOR_TREES_READY: source_trees=%d preowned=%d runtime_trees=%d batches=%d source=OSM license=ODbL-1.0" % [all_source_tree_count, preowned.size(), _source_positions.size(), batch_count()])

func set_visual_enabled(enabled: bool) -> void:
    _visual_enabled = enabled
    for batch: MultiMeshInstance3D in [_trunk_batch, _dark_batch, _light_batch]:
        if is_instance_valid(batch):
            batch.visible = enabled

func source_positions_unchanged() -> bool:
    if _source_positions.size() != _source_ids.size():
        return false
    var data := _load_json(DATA_PATH)
    var preowned := _preowned_tree_ids()
    var index := 0
    for raw: Variant in data.get("environment_points", []):
        if not raw is Dictionary:
            continue
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "tree":
            continue
        var osm_id := int(point.get("osm_id", 0))
        if preowned.has(osm_id):
            continue
        if index >= _source_positions.size() or _source_ids[index] != osm_id:
            return false
        var position_value := point.get("position", []) as Array
        if position_value.size() != 2:
            return false
        var actual := _source_positions[index]
        if abs(actual.x - float(position_value[0])) > POSITION_EPSILON_M or abs(actual.z - float(position_value[1])) > POSITION_EPSILON_M:
            return false
        index += 1
    return index == _source_positions.size()

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func tree_count() -> int:
    return _source_positions.size()

func total_source_tree_count() -> int:
    return EXPECTED_SOURCE_TREE_COUNT

func preowned_tree_count() -> int:
    return EXPECTED_PREOWNED_TREE_COUNT

func batch_count() -> int:
    var count := 0
    for batch: MultiMeshInstance3D in [_trunk_batch, _dark_batch, _light_batch]:
        if is_instance_valid(batch):
            count += 1
    return count

func collision_count() -> int:
    return _collision_body.get_child_count() if is_instance_valid(_collision_body) else 0

func source_positions() -> Array[Vector3]:
    return _source_positions.duplicate()

func source_ids() -> Array[int]:
    return _source_ids.duplicate()

func claims_species() -> bool:
    return false

func claims_measured_dimensions() -> bool:
    return false

func visual_enabled() -> bool:
    return _visual_enabled
