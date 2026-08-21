extends Node3D
class_name RgsdevVehicleVisual

const PACK_CONTRACT := "rgsdev_cc0_vehicles_v1"
const MODEL_PATHS := {
    "ambulance": "res://game/assets/vehicles/rgsdev/ambulance.fbx",
    "bus": "res://game/assets/vehicles/rgsdev/bus.fbx",
    "firetruck": "res://game/assets/vehicles/rgsdev/firetruck.fbx",
    "hatchback": "res://game/assets/vehicles/rgsdev/hatchback.fbx",
    "limousine": "res://game/assets/vehicles/rgsdev/limousine.fbx",
    "monster_truck": "res://game/assets/vehicles/rgsdev/monster_truck.fbx",
    "muscle": "res://game/assets/vehicles/rgsdev/muscle.fbx",
    "muscle_2": "res://game/assets/vehicles/rgsdev/muscle_2.fbx",
    "pickup": "res://game/assets/vehicles/rgsdev/pickup.fbx",
    "police_muscle": "res://game/assets/vehicles/rgsdev/police_muscle.fbx",
    "police_sedan": "res://game/assets/vehicles/rgsdev/police_sedan.fbx",
    "police_sports": "res://game/assets/vehicles/rgsdev/police_sports.fbx",
    "police_suv": "res://game/assets/vehicles/rgsdev/police_suv.fbx",
    "roadster": "res://game/assets/vehicles/rgsdev/roadster.fbx",
    "sedan": "res://game/assets/vehicles/rgsdev/sedan.fbx",
    "sports": "res://game/assets/vehicles/rgsdev/sports.fbx",
    "suv": "res://game/assets/vehicles/rgsdev/suv.fbx",
    "taxi": "res://game/assets/vehicles/rgsdev/taxi.fbx",
    "truck": "res://game/assets/vehicles/rgsdev/truck.fbx",
    "truck_with_trailer": "res://game/assets/vehicles/rgsdev/truck_with_trailer.fbx",
    "van": "res://game/assets/vehicles/rgsdev/van.fbx",
}
const MODEL_IDS := [
    "sedan", "hatchback", "suv", "van", "pickup", "muscle", "muscle_2", "roadster", "sports", "taxi", "limousine",
    "bus", "truck", "truck_with_trailer", "ambulance", "firetruck", "monster_truck",
    "police_sedan", "police_suv", "police_muscle", "police_sports",
]
const CIVILIAN_MODELS := [
    "sedan", "hatchback", "suv", "van", "pickup", "muscle", "muscle_2", "roadster", "sports", "taxi", "limousine"
]
const HEAVY_MODELS := ["bus", "truck", "truck_with_trailer", "ambulance", "firetruck", "monster_truck"]
const POLICE_MODELS := ["police_sedan", "police_suv", "police_muscle", "police_sports"]
const MODEL_SCALES := {
    "sedan": Vector3(0.647, 0.721, 0.818),
    "hatchback": Vector3(0.640, 0.726, 0.803),
    "suv": Vector3(0.675, 0.749, 0.903),
    "van": Vector3(0.718, 0.812, 0.872),
    "pickup": Vector3(0.711, 0.859, 1.012),
    "muscle": Vector3(0.675, 0.733, 0.784),
    "muscle_2": Vector3(0.675, 0.733, 0.784),
    "roadster": Vector3(0.702, 0.679, 0.751),
    "sports": Vector3(0.702, 0.679, 0.751),
    "taxi": Vector3(0.647, 0.638, 0.818),
    "limousine": Vector3(0.682, 0.746, 0.615),
    "police_sedan": Vector3(0.647, 0.708, 0.818),
    "police_suv": Vector3(0.675, 0.795, 0.903),
    "police_muscle": Vector3(0.675, 0.718, 0.784),
    "police_sports": Vector3(0.702, 0.728, 0.751),
    "ambulance": Vector3(0.729, 0.982, 0.982),
    "bus": Vector3(0.669, 0.876, 0.727),
    "firetruck": Vector3(0.732, 0.833, 0.884),
    "monster_truck": Vector3(0.537, 0.875, 0.643),
    "truck": Vector3(0.732, 1.077, 0.982),
    "truck_with_trailer": Vector3(0.732, 0.969, 0.977),
}

static var _scene_cache: Dictionary = {}

@export var model_id: String = "sedan"
@export var model_scale: Vector3 = Vector3.ONE
@export var model_rotation_degrees: Vector3 = Vector3.ZERO
@export var model_offset: Vector3 = Vector3.ZERO
@export var wheel_radius_m: float = 0.34
@export var animate_wheels: bool = true
@export var auto_align_forward: bool = true
@export var auto_ground_model: bool = true
@export_range(0.0, 0.08, 0.001) var ground_clearance_m: float = 0.008

var _instance: Node3D = null
var _wheel_nodes: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _rear_wheels: Array[Node3D] = []
var _wheel_base_rotation: Dictionary = {}
var _spin_angle: float = 0.0
var _forward_yaw_correction_rad: float = 0.0
var _ground_offset_applied_m: float = 0.0

func _ready() -> void:
    _load_model()

func configure_for_traffic(serial: int) -> void:
    model_id = CIVILIAN_MODELS[posmod(serial, CIVILIAN_MODELS.size())]

func configure_for_police(serial: int = 0) -> void:
    model_id = POLICE_MODELS[posmod(serial, POLICE_MODELS.size())]

func configure_model(new_model_id: String) -> void:
    if MODEL_PATHS.has(new_model_id):
        model_id = new_model_id
    if is_inside_tree():
        _load_model()

func get_visual_contract() -> Dictionary:
    return {
        "quality": PACK_CONTRACT,
        "model_id": model_id,
        "source_path": str(MODEL_PATHS.get(model_id, "")),
        "license": "CC0",
        "wheel_animation": animate_wheels,
        "wheel_count": _wheel_nodes.size(),
        "model_count": MODEL_PATHS.size(),
        "heavy_models": HEAVY_MODELS.duplicate(),
        "police_models": POLICE_MODELS.duplicate(),
        "auto_align_forward": auto_align_forward,
        "auto_ground_model": auto_ground_model,
        "forward_yaw_correction_rad": _forward_yaw_correction_rad,
        "ground_offset_applied_m": _ground_offset_applied_m,
        "ground_contact_y": get_ground_contact_y(),
        "target_ground_y": _target_ground_y(),
        "visual_forward_dot_body_forward": get_visual_forward_dot_body_forward(),
    }

func instantiate_model_for_test(test_model_id: String) -> Node3D:
    return _instantiate_model(test_model_id)

func get_ground_contact_y() -> float:
    var wheel_bounds := _wheel_bounds_in_visual_space()
    if bool(wheel_bounds.get("valid", false)):
        return float(wheel_bounds.get("min_y", 0.0))
    var bounds := _mesh_bounds_in_visual_space()
    if bool(bounds.get("valid", false)):
        return float(bounds.get("min_y", 0.0))
    return INF

func get_visual_forward_dot_body_forward() -> float:
    if _front_wheels.is_empty() or _rear_wheels.is_empty():
        return -1.0
    var front_center := _wheel_center_in_visual_space(_front_wheels)
    var rear_center := _wheel_center_in_visual_space(_rear_wheels)
    var direction := front_center - rear_center
    direction.y = 0.0
    if direction.length_squared() <= 0.0001:
        return -1.0
    return direction.normalized().dot(Vector3.FORWARD)

func _load_model() -> void:
    if _instance != null and is_instance_valid(_instance):
        _instance.queue_free()
    _wheel_nodes.clear()
    _front_wheels.clear()
    _rear_wheels.clear()
    _wheel_base_rotation.clear()
    _forward_yaw_correction_rad = 0.0
    _ground_offset_applied_m = 0.0
    _instance = _instantiate_model(model_id)
    if _instance == null:
        return
    _instance.name = "ImportedModel"
    var authored_scale: Vector3 = MODEL_SCALES.get(model_id, Vector3.ONE)
    _instance.scale = authored_scale * model_scale
    _instance.rotation_degrees = model_rotation_degrees
    _instance.position = model_offset
    add_child(_instance)
    _collect_wheels(_instance)
    if auto_align_forward:
        _align_model_forward_from_wheels()
    if auto_ground_model:
        _snap_model_to_collision_bottom()
    _capture_wheel_base_rotations()
    set_meta("rgsdev_model_id", model_id)
    set_meta("rgsdev_source_path", str(MODEL_PATHS.get(model_id, "")))
    set_meta("rgsdev_license", "CC0")

func _instantiate_model(requested_model_id: String) -> Node3D:
    var safe_model_id := requested_model_id if MODEL_PATHS.has(requested_model_id) else "sedan"
    if _scene_cache.has(safe_model_id):
        var cached := _scene_cache[safe_model_id] as PackedScene
        return cached.instantiate() as Node3D
    var path := str(MODEL_PATHS[safe_model_id])
    if not ResourceLoader.exists(path):
        push_error("RGSDEV model missing or not imported: %s" % path)
        return null
    var packed := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_REUSE) as PackedScene
    if packed == null:
        push_error("RGSDEV model could not be loaded as PackedScene: %s" % path)
        return null
    _scene_cache[safe_model_id] = packed
    return packed.instantiate() as Node3D

func _collect_wheels(node: Node) -> void:
    for child: Node in node.get_children():
        if child is Node3D:
            var spatial := child as Node3D
            var lowered := spatial.name.to_lower()
            if "wheel" in lowered:
                _wheel_nodes.append(spatial)
                if "front" in lowered:
                    _front_wheels.append(spatial)
                elif "rear" in lowered:
                    _rear_wheels.append(spatial)
        _collect_wheels(child)

func _capture_wheel_base_rotations() -> void:
    _wheel_base_rotation.clear()
    for wheel: Node3D in _wheel_nodes:
        if is_instance_valid(wheel):
            _wheel_base_rotation[wheel.get_instance_id()] = wheel.rotation

func _wheel_center_in_visual_space(wheels: Array[Node3D]) -> Vector3:
    if wheels.is_empty():
        return Vector3.ZERO
    var center := Vector3.ZERO
    var count := 0
    for wheel: Node3D in wheels:
        if not is_instance_valid(wheel):
            continue
        center += to_local(wheel.global_position)
        count += 1
    if count <= 0:
        return Vector3.ZERO
    return center / float(count)

func _align_model_forward_from_wheels() -> void:
    if _instance == null or _front_wheels.is_empty() or _rear_wheels.is_empty():
        return
    var front_center := _wheel_center_in_visual_space(_front_wheels)
    var rear_center := _wheel_center_in_visual_space(_rear_wheels)
    var current_forward := front_center - rear_center
    current_forward.y = 0.0
    if current_forward.length_squared() <= 0.0001:
        return
    current_forward = current_forward.normalized()
    var correction := Quaternion(current_forward, Vector3.FORWARD)
    _forward_yaw_correction_rad = correction.get_euler().y
    _instance.quaternion = correction * _instance.quaternion

func _target_ground_y() -> float:
    var parent := get_parent()
    if parent != null:
        var collision := parent.get_node_or_null("CollisionShape3D") as CollisionShape3D
        if collision != null and collision.shape is BoxShape3D:
            var box := collision.shape as BoxShape3D
            return collision.position.y - box.size.y * 0.5 + ground_clearance_m
    return ground_clearance_m

func _snap_model_to_collision_bottom() -> void:
    if _instance == null:
        return
    var bounds := _wheel_bounds_in_visual_space()
    if not bool(bounds.get("valid", false)):
        bounds = _mesh_bounds_in_visual_space()
    if not bool(bounds.get("valid", false)):
        return
    var min_y := float(bounds.get("min_y", 0.0))
    var target_y := _target_ground_y()
    _ground_offset_applied_m = target_y - min_y
    _instance.position.y += _ground_offset_applied_m

func _wheel_bounds_in_visual_space() -> Dictionary:
    var state := {"valid": false, "min_y": INF, "max_y": -INF}
    for wheel: Node3D in _wheel_nodes:
        if is_instance_valid(wheel):
            _accumulate_mesh_bounds(wheel, state)
    return state

func _mesh_bounds_in_visual_space() -> Dictionary:
    if _instance == null or not is_instance_valid(_instance):
        return {"valid": false}
    var state := {"valid": false, "min_y": INF, "max_y": -INF}
    _accumulate_mesh_bounds(_instance, state)
    return state

func _accumulate_mesh_bounds(node: Node, state: Dictionary) -> void:
    if node is MeshInstance3D:
        var mesh_node := node as MeshInstance3D
        if mesh_node.mesh != null:
            var aabb := mesh_node.get_aabb()
            for corner_index: int in range(8):
                var corner := aabb.position + Vector3(
                    aabb.size.x if (corner_index & 1) != 0 else 0.0,
                    aabb.size.y if (corner_index & 2) != 0 else 0.0,
                    aabb.size.z if (corner_index & 4) != 0 else 0.0
                )
                var visual_point := to_local(mesh_node.to_global(corner))
                state["min_y"] = minf(float(state["min_y"]), visual_point.y)
                state["max_y"] = maxf(float(state["max_y"]), visual_point.y)
                state["valid"] = true
    for child: Node in node.get_children():
        _accumulate_mesh_bounds(child, state)

func _process(delta: float) -> void:
    if not animate_wheels or _wheel_nodes.is_empty():
        return
    var vehicle := get_parent()
    var forward_speed := 0.0
    if vehicle is CharacterBody3D:
        var body := vehicle as CharacterBody3D
        var forward := -body.global_transform.basis.z
        forward.y = 0.0
        if forward.length_squared() > 0.001:
            forward_speed = body.velocity.dot(forward.normalized())
    elif vehicle is RigidBody3D:
        var rigid := vehicle as RigidBody3D
        var forward := -rigid.global_transform.basis.z
        forward.y = 0.0
        if forward.length_squared() > 0.001:
            forward_speed = rigid.linear_velocity.dot(forward.normalized())
    _spin_angle = fposmod(_spin_angle + forward_speed / maxf(0.05, wheel_radius_m) * delta, TAU)
    var steering := 0.0
    if vehicle != null and vehicle.has_method("get_visual_steering_angle"):
        steering = float(vehicle.call("get_visual_steering_angle"))
    for wheel: Node3D in _wheel_nodes:
        if not is_instance_valid(wheel):
            continue
        var base: Vector3 = _wheel_base_rotation.get(wheel.get_instance_id(), wheel.rotation)
        wheel.rotation = Vector3(base.x + _spin_angle, base.y, base.z)
    for wheel: Node3D in _front_wheels:
        if is_instance_valid(wheel):
            wheel.rotation.y += steering
