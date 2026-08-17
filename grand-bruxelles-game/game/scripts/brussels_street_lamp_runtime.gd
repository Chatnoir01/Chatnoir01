extends Node

const DATA_PATH := "res://data/osm/corridor_street_lamps.game.json"
const ASSET := preload("res://game/scripts/brussels_street_lamp_asset.gd")
const POSITION_EPSILON_METERS := 0.0005

var _root: Node3D = null
var _scene: Node3D = null
var _pole_batch: MultiMeshInstance3D = null
var _arm_batch: MultiMeshInstance3D = null
var _luminaire_batch: MultiMeshInstance3D = null
var _collision_body: StaticBody3D = null
var _source_positions: Array[Vector3] = []
var _pole_transforms: Array[Transform3D] = []
var _arm_transforms: Array[Transform3D] = []
var _luminaire_transforms: Array[Transform3D] = []
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
    _pole_batch = null
    _arm_batch = null
    _luminaire_batch = null
    _collision_body = null
    _source_positions.clear()
    _pole_transforms.clear()
    _arm_transforms.clear()
    _luminaire_transforms.clear()
    _failed = false
    _ready_complete = false
    _build()

func _fail(message: String) -> void:
    push_error("Brussels source-backed street lamp runtime: %s" % message)
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
    var data := _load_data()
    if data.is_empty():
        _fail("source payload missing")
        return
    var points := data.get("points", []) as Array
    if points.is_empty():
        _fail("source payload has no points")
        return

    _source_positions.clear()
    _pole_transforms.clear()
    _arm_transforms.clear()
    _luminaire_transforms.clear()
    for raw: Variant in points:
        var parsed_position: Variant = _point_base_position(raw)
        if not parsed_position is Vector3:
            _fail("malformed source point")
            return
        var source_base := parsed_position as Vector3
        _source_positions.append(source_base)
        _pole_transforms.append(ASSET.pole_transform(source_base))
        _arm_transforms.append(ASSET.arm_transform(source_base))
        _luminaire_transforms.append(ASSET.luminaire_transform(source_base))

    if not _placement_contract_matches_source():
        _fail("authored placement contract moved source positions")
        return

    var materials := ASSET.create_materials()
    _root = Node3D.new()
    _root.name = "BrusselsSourceBackedStreetLamps"
    _root.set_meta("asset_family", ASSET.ASSET_FAMILY)
    _root.set_meta("source", str(data.get("source", "")))
    _root.set_meta("license", str(data.get("license", "")))
    _root.set_meta("placement_source_backed", true)
    _root.set_meta("visual_dimensions_source_backed", false)
    _root.set_meta("visual_material_source_backed", false)
    _root.set_meta("light_photometry_source_backed", false)
    _root.set_meta("visual_recipe_provenance", "authored_presentation_not_source_measurement")
    _scene.add_child(_root)

    _pole_batch = _build_batch("StreetLampPoles", ASSET.create_pole_mesh(materials["metal"] as Material), _pole_transforms)
    _arm_batch = _build_batch("StreetLampArms", ASSET.create_arm_mesh(materials["metal"] as Material), _arm_transforms)
    _luminaire_batch = _build_batch("StreetLampLuminaires", ASSET.create_luminaire_mesh(materials["luminaire"] as Material), _luminaire_transforms)
    _root.add_child(_pole_batch)
    _root.add_child(_arm_batch)
    _root.add_child(_luminaire_batch)

    _collision_body = StaticBody3D.new()
    _collision_body.name = "StreetLampCollisions"
    _root.add_child(_collision_body)
    for index: int in range(points.size()):
        var point := points[index] as Dictionary
        var base_position := _source_positions[index]
        var collision := CollisionShape3D.new()
        collision.name = "StreetLamp_%d" % int(point.get("osm_id", 0))
        collision.shape = ASSET.collision_shape()
        collision.position = base_position + Vector3(0.0, ASSET.COLLISION_HEIGHT * 0.5, 0.0)
        collision.set_meta("osm_id", int(point.get("osm_id", 0)))
        collision.set_meta("source_base_position", base_position)
        _collision_body.add_child(collision)

    set_visual_enabled(_visual_enabled)
    _ready_complete = true
    print("BRUSSELS_STREET_LAMP_READY: points=%d collisions=%d batches=%d family=%s source=OSM license=ODbL-1.0" % [point_count(), collision_count(), visual_batch_count(), ASSET.ASSET_FAMILY])

func set_visual_enabled(enabled: bool) -> void:
    _visual_enabled = enabled
    for batch: MultiMeshInstance3D in [_pole_batch, _arm_batch, _luminaire_batch]:
        if is_instance_valid(batch):
            batch.visible = enabled

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
    for batch: MultiMeshInstance3D in [_pole_batch, _arm_batch, _luminaire_batch]:
        if is_instance_valid(batch):
            count += 1
    return count

func asset_family() -> String:
    return ASSET.ASSET_FAMILY

func _same_source_xz(actual: Vector3, source: Vector3) -> bool:
    return absf(actual.x - source.x) <= POSITION_EPSILON_METERS and absf(actual.z - source.z) <= POSITION_EPSILON_METERS

func _placement_contract_matches_source() -> bool:
    if _source_positions.size() != _pole_transforms.size() or _source_positions.size() != _arm_transforms.size() or _source_positions.size() != _luminaire_transforms.size():
        return false
    for index: int in range(_source_positions.size()):
        var source_base := _source_positions[index]
        if not _same_source_xz(_pole_transforms[index].origin, source_base):
            return false
        var expected_arm_x := source_base.x + ASSET.ARM_LENGTH * 0.5
        var expected_luminaire_x := source_base.x + ASSET.ARM_LENGTH + ASSET.LUMINAIRE_LENGTH * 0.28
        if absf(_arm_transforms[index].origin.x - expected_arm_x) > POSITION_EPSILON_METERS or absf(_arm_transforms[index].origin.z - source_base.z) > POSITION_EPSILON_METERS:
            return false
        if absf(_luminaire_transforms[index].origin.x - expected_luminaire_x) > POSITION_EPSILON_METERS or absf(_luminaire_transforms[index].origin.z - source_base.z) > POSITION_EPSILON_METERS:
            return false
    return true

func source_positions_unchanged() -> bool:
    if not _placement_contract_matches_source() or collision_count() != _source_positions.size():
        return false
    for index: int in range(_source_positions.size()):
        var collision := _collision_body.get_child(index) as CollisionShape3D
        if collision == null or not _same_source_xz(collision.position, _source_positions[index]):
            return false
        var metadata_position: Variant = collision.get_meta("source_base_position", null)
        if not metadata_position is Vector3 or not (metadata_position as Vector3).is_equal_approx(_source_positions[index]):
            return false
    return true
