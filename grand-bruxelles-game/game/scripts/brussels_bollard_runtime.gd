extends Node

const DATA_PATH := "res://data/osm/fontainas_bollards.game.json"
const ASSET := preload("res://game/scripts/brussels_bollard_asset.gd")
const POSITION_EPSILON_METERS := 0.0005

var _root: Node3D = null
var _scene: Node3D = null
var _body_batch: MultiMeshInstance3D = null
var _cap_batch: MultiMeshInstance3D = null
var _collision_body: StaticBody3D = null
var _source_positions: Array[Vector3] = []
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
    _body_batch = null
    _cap_batch = null
    _collision_body = null
    _source_positions.clear()
    _failed = false
    _ready_complete = false
    _build()

func _fail(message: String) -> void:
    push_error("Brussels source-backed bollard runtime: %s" % message)
    _failed = true
    _ready_complete = true

func _load_data() -> Dictionary:
    if not FileAccess.file_exists(DATA_PATH):
        return {}
    var file := FileAccess.open(DATA_PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    return parsed as Dictionary if parsed is Dictionary else {}

func _point_base_position(raw: Variant) -> Variant:
    if not raw is Dictionary:
        return null
    var point := raw as Dictionary
    var position_value := point.get("position", []) as Array
    if position_value.size() != 2:
        return null
    return Vector3(float(position_value[0]), 0.0, float(position_value[1]))

func _build() -> void:
    if _scene == null:
        _fail("scene missing during build")
        return
    var data := _load_data()
    if data.is_empty():
        _fail("source payload missing")
        return
    var points := data.get("points", []) as Array
    if points.is_empty():
        _fail("source payload has no points")
        return

    _source_positions.clear()
    for raw: Variant in points:
        var parsed_position: Variant = _point_base_position(raw)
        if not parsed_position is Vector3:
            _fail("malformed source point")
            return
        _source_positions.append(parsed_position as Vector3)

    var materials := ASSET.create_materials()
    var body_multimesh := MultiMesh.new()
    body_multimesh.transform_format = MultiMesh.TRANSFORM_3D
    body_multimesh.instance_count = _source_positions.size()
    body_multimesh.mesh = ASSET.create_body_mesh(materials["body"] as Material)

    var cap_multimesh := MultiMesh.new()
    cap_multimesh.transform_format = MultiMesh.TRANSFORM_3D
    cap_multimesh.instance_count = _source_positions.size()
    cap_multimesh.mesh = ASSET.create_cap_mesh(materials["cap"] as Material)

    for index: int in range(_source_positions.size()):
        var source_base := _source_positions[index]
        body_multimesh.set_instance_transform(index, ASSET.body_transform(source_base))
        cap_multimesh.set_instance_transform(index, ASSET.cap_transform(source_base))
    body_multimesh.visible_instance_count = _source_positions.size()
    cap_multimesh.visible_instance_count = _source_positions.size()

    for index: int in range(_source_positions.size()):
        var source_base := _source_positions[index]
        if not _same_source_xz(body_multimesh.get_instance_transform(index).origin, source_base):
            _fail("body MultiMesh placement buffer mismatch")
            return
        if not _same_source_xz(cap_multimesh.get_instance_transform(index).origin, source_base):
            _fail("cap MultiMesh placement buffer mismatch")
            return

    _root = Node3D.new()
    _root.name = "BrusselsSourceBackedBollards"
    _root.set_meta("asset_family", ASSET.ASSET_FAMILY)
    _root.set_meta("source", str(data.get("source", "")))
    _root.set_meta("license", str(data.get("license", "")))
    _root.set_meta("placement_source_backed", true)
    _root.set_meta("visual_dimensions_source_backed", false)
    _root.set_meta("visual_material_source_backed", false)
    _root.set_meta("visual_colour_source_backed", false)
    _root.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    _scene.add_child(_root)

    _body_batch = MultiMeshInstance3D.new()
    _body_batch.name = "BollardBodies"
    _body_batch.multimesh = body_multimesh
    _root.add_child(_body_batch)

    _cap_batch = MultiMeshInstance3D.new()
    _cap_batch.name = "BollardCaps"
    _cap_batch.multimesh = cap_multimesh
    _root.add_child(_cap_batch)

    _collision_body = StaticBody3D.new()
    _collision_body.name = "BollardCollisions"
    _root.add_child(_collision_body)

    for index: int in range(points.size()):
        var point := points[index] as Dictionary
        var base_position := _source_positions[index]
        var collision := CollisionShape3D.new()
        collision.name = "Bollard_%d" % int(point.get("osm_id", 0))
        collision.shape = ASSET.collision_shape()
        collision.position = base_position + Vector3(0.0, ASSET.COLLISION_HEIGHT * 0.5, 0.0)
        collision.set_meta("osm_id", int(point.get("osm_id", 0)))
        collision.set_meta("source_base_position", base_position)
        _collision_body.add_child(collision)

    set_visual_enabled(_visual_enabled)
    _ready_complete = true
    print("BRUSSELS_BOLLARD_READY: points=%d collisions=%d batches=%d family=%s source=OSM license=ODbL-1.0" % [point_count(), collision_count(), visual_batch_count(), ASSET.ASSET_FAMILY])

func set_visual_enabled(enabled: bool) -> void:
    _visual_enabled = enabled
    if is_instance_valid(_body_batch):
        _body_batch.visible = enabled
    if is_instance_valid(_cap_batch):
        _cap_batch.visible = enabled

func visual_enabled() -> bool:
    return _visual_enabled

func ready_complete() -> bool:
    return _ready_complete

func failed() -> bool:
    return _failed

func point_count() -> int:
    return _source_positions.size()

func collision_count() -> int:
    if not is_instance_valid(_collision_body):
        return 0
    var count := 0
    for child: Node in _collision_body.get_children():
        if child is CollisionShape3D:
            count += 1
    return count

func visual_batch_count() -> int:
    var count := 0
    if is_instance_valid(_body_batch):
        count += 1
    if is_instance_valid(_cap_batch):
        count += 1
    return count

func asset_family() -> String:
    return ASSET.ASSET_FAMILY

func _same_source_xz(actual: Vector3, source: Vector3) -> bool:
    return absf(actual.x - source.x) <= POSITION_EPSILON_METERS and absf(actual.z - source.z) <= POSITION_EPSILON_METERS

func _same_authored_y(actual_y: float, expected_y: float) -> bool:
    return absf(actual_y - expected_y) <= POSITION_EPSILON_METERS

func source_positions_unchanged() -> bool:
    if not is_instance_valid(_body_batch) or not is_instance_valid(_cap_batch) or not is_instance_valid(_collision_body):
        return false
    if _source_positions.size() != _body_batch.multimesh.instance_count or _source_positions.size() != _cap_batch.multimesh.instance_count:
        return false
    if collision_count() != _source_positions.size():
        return false

    for index: int in range(_source_positions.size()):
        var source_base := _source_positions[index]
        var body_origin := _body_batch.multimesh.get_instance_transform(index).origin
        var cap_origin := _cap_batch.multimesh.get_instance_transform(index).origin
        if not _same_source_xz(body_origin, source_base) or not _same_source_xz(cap_origin, source_base):
            return false
        if not _same_authored_y(body_origin.y, ASSET.BODY_HEIGHT * 0.5):
            return false
        if not _same_authored_y(cap_origin.y, ASSET.BODY_HEIGHT + ASSET.CAP_HEIGHT * 0.5):
            return false

        var collision := _collision_body.get_child(index) as CollisionShape3D
        if collision == null:
            return false
        if not _same_source_xz(collision.position, source_base):
            return false
        if not _same_authored_y(collision.position.y, ASSET.COLLISION_HEIGHT * 0.5):
            return false
        var metadata_position: Variant = collision.get_meta("source_base_position", null)
        if not metadata_position is Vector3 or not (metadata_position as Vector3).is_equal_approx(source_base):
            return false
    return true
