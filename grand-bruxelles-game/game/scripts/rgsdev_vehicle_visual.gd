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
}

static var _scene_cache: Dictionary = {}

@export var model_id: String = "sedan"
@export var model_scale: Vector3 = Vector3.ONE
@export var model_rotation_degrees: Vector3 = Vector3.ZERO
@export var model_offset: Vector3 = Vector3.ZERO
@export var wheel_radius_m: float = 0.34
@export var animate_wheels: bool = true

var _instance: Node3D = null
var _wheel_nodes: Array[Node3D] = []
var _front_wheels: Array[Node3D] = []
var _wheel_base_rotation: Dictionary = {}
var _spin_angle: float = 0.0

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
    }

func instantiate_model_for_test(test_model_id: String) -> Node3D:
    return _instantiate_model(test_model_id)

func _load_model() -> void:
    if _instance != null and is_instance_valid(_instance):
        _instance.queue_free()
    _wheel_nodes.clear()
    _front_wheels.clear()
    _wheel_base_rotation.clear()
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
                _wheel_base_rotation[spatial.get_instance_id()] = spatial.rotation
                if "front" in lowered:
                    _front_wheels.append(spatial)
        _collect_wheels(child)

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
