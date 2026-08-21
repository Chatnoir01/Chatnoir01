extends "res://game/scripts/drivable_traffic_vehicle.gd"
class_name AmbulanceVehicle

signal emergency_mode_changed(enabled: bool)

@export var emergency_mode: bool = false
@export var emergency_max_forward_speed_mps: float = 30.0
@export var emergency_acceleration_mps2: float = 15.5
@export var normal_max_forward_speed_mps: float = 22.0
@export var normal_acceleration_mps2: float = 11.0
@export var emergency_yield_radius_m: float = 24.0
@export var emergency_flash_hz: float = 5.5
@export_range(0.0, 1.0, 0.05) var yielded_speed_factor: float = 0.15

var _left_beacon: OmniLight3D = null
var _right_beacon: OmniLight3D = null
var _flash_elapsed: float = 0.0
var _yielded_vehicles: Dictionary = {}

func _ready() -> void:
    super._ready()
    add_to_group("ambulance")
    add_to_group("emergency_vehicle")
    traffic_archetype = "car"
    _ensure_emergency_lights()
    _apply_emergency_tuning()

func set_emergency_mode(enabled: bool) -> void:
    if emergency_mode == enabled:
        return
    emergency_mode = enabled
    _apply_emergency_tuning()
    if not emergency_mode:
        _release_all_yielding_traffic()
        _set_beacons(false, false)
    emergency_mode_changed.emit(emergency_mode)

func toggle_emergency_mode() -> void:
    set_emergency_mode(not emergency_mode)

func is_emergency_mode() -> bool:
    return emergency_mode

func _apply_emergency_tuning() -> void:
    if emergency_mode:
        manual_max_forward_speed_mps = emergency_max_forward_speed_mps
        manual_acceleration_mps2 = emergency_acceleration_mps2
    else:
        manual_max_forward_speed_mps = normal_max_forward_speed_mps
        manual_acceleration_mps2 = normal_acceleration_mps2

func _process(delta: float) -> void:
    if not emergency_mode:
        return
    _flash_elapsed += delta
    var phase := int(floor(_flash_elapsed * emergency_flash_hz)) % 2
    _set_beacons(phase == 0, phase == 1)
    _update_yielding_traffic()

func _unhandled_input(event: InputEvent) -> void:
    super._unhandled_input(event)
    if driver == null:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_H:
        toggle_emergency_mode()

func _ensure_emergency_lights() -> void:
    var light_root := get_node_or_null("EmergencyLightRoot") as Node3D
    if light_root == null:
        light_root = Node3D.new()
        light_root.name = "EmergencyLightRoot"
        light_root.position = Vector3(0.0, 1.65, -0.25)
        add_child(light_root)
    _left_beacon = light_root.get_node_or_null("BlueLeft") as OmniLight3D
    if _left_beacon == null:
        _left_beacon = OmniLight3D.new()
        _left_beacon.name = "BlueLeft"
        _left_beacon.position = Vector3(-0.52, 0.0, 0.0)
        _left_beacon.light_color = Color(0.08, 0.28, 1.0)
        _left_beacon.light_energy = 4.0
        _left_beacon.omni_range = 10.0
        _left_beacon.shadow_enabled = false
        light_root.add_child(_left_beacon)
    _right_beacon = light_root.get_node_or_null("BlueRight") as OmniLight3D
    if _right_beacon == null:
        _right_beacon = OmniLight3D.new()
        _right_beacon.name = "BlueRight"
        _right_beacon.position = Vector3(0.52, 0.0, 0.0)
        _right_beacon.light_color = Color(0.08, 0.28, 1.0)
        _right_beacon.light_energy = 4.0
        _right_beacon.omni_range = 10.0
        _right_beacon.shadow_enabled = false
        light_root.add_child(_right_beacon)
    _set_beacons(false, false)

func _set_beacons(left_enabled: bool, right_enabled: bool) -> void:
    if _left_beacon != null:
        _left_beacon.visible = left_enabled
    if _right_beacon != null:
        _right_beacon.visible = right_enabled

func _update_yielding_traffic() -> void:
    var current: Dictionary = {}
    for node: Node in get_tree().get_nodes_in_group("traffic_vehicle"):
        if node == self or not node is Node3D or node.is_queued_for_deletion():
            continue
        var body := node as Node3D
        var distance := global_position.distance_to(body.global_position)
        if distance > emergency_yield_radius_m:
            continue
        var instance_id := node.get_instance_id()
        current[instance_id] = node
        if not _yielded_vehicles.has(instance_id):
            var original_speed_factor: Variant = node.get("speed_factor")
            _yielded_vehicles[instance_id] = {
                "node": node,
                "speed_factor": float(original_speed_factor) if original_speed_factor != null else 0.90,
            }
        node.set_meta("yield_to_ambulance", true)
        node.set("speed_factor", minf(float(node.get("speed_factor")), yielded_speed_factor))
    for instance_id: Variant in _yielded_vehicles.keys():
        if current.has(instance_id):
            continue
        _restore_yielded_vehicle(instance_id)

func _restore_yielded_vehicle(instance_id: Variant) -> void:
    var state: Dictionary = _yielded_vehicles.get(instance_id, {})
    var node: Variant = state.get("node")
    if node is Node and is_instance_valid(node):
        (node as Node).set_meta("yield_to_ambulance", false)
        (node as Node).set("speed_factor", float(state.get("speed_factor", 0.90)))
    _yielded_vehicles.erase(instance_id)

func _release_all_yielding_traffic() -> void:
    for instance_id: Variant in _yielded_vehicles.keys():
        _restore_yielded_vehicle(instance_id)
    _yielded_vehicles.clear()

func get_ambulance_contract() -> Dictionary:
    return {
        "vehicle": "ambulance",
        "drivable": true,
        "player_emergency_toggle": "H",
        "emergency_mode": emergency_mode,
        "blue_beacons": true,
        "traffic_priority_radius_m": emergency_yield_radius_m,
        "yielded_speed_factor": yielded_speed_factor,
        "external_driver_supported": true,
        "other_special_vehicles_auto_spawned": false,
    }
