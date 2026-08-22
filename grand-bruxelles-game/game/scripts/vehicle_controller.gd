extends "res://game/scripts/drivable_traffic_vehicle.gd"

# Compatibility wrapper for the historical PrototypeCar scene node.
# The actual driving/grounding implementation now lives in DrivableTrafficVehicle,
# so the starter car, traffic cars, parked cars and NPC-driven cars share one
# forward axis, one ground-snap rule and one steering model.

@export var max_forward_speed: float = 24.0
@export var max_reverse_speed: float = 8.0
@export var acceleration: float = 12.0
@export var braking: float = 20.0
@export var coast_drag: float = 7.5
@export var steering_speed: float = 1.55
@export var exit_distance: float = 2.7
@export var mouse_sensitivity: float = 0.0022

var speed: float:
    get:
        return _manual_speed_mps
    set(value):
        _manual_speed_mps = value

func _ready() -> void:
    manual_max_forward_speed_mps = max_forward_speed
    manual_max_reverse_speed_mps = max_reverse_speed
    manual_acceleration_mps2 = acceleration
    manual_braking_mps2 = braking
    manual_coast_drag_mps2 = coast_drag
    manual_steering_speed = steering_speed
    manual_exit_distance_m = exit_distance
    manual_mouse_sensitivity = mouse_sensitivity
    configure_archetype("car")
    super._ready()

func _ensure_camera_rig() -> void:
    # Reuse the camera rig already serialized in main.tscn instead of creating a
    # second hidden camera. This keeps the historical scene layout compatible
    # while delegating all movement to DrivableTrafficVehicle.
    var existing_pivot := get_node_or_null("CameraPivot") as Node3D
    if existing_pivot != null:
        var existing_arm := existing_pivot.get_node_or_null("SpringArm3D") as SpringArm3D
        var existing_camera: Camera3D = null
        if existing_arm != null:
            existing_camera = existing_arm.get_node_or_null("Camera3D") as Camera3D
        if existing_arm != null and existing_camera != null:
            _camera_pivot = existing_pivot
            _camera = existing_camera
            camera_spring_length_m = existing_arm.spring_length
            return
    super._ensure_camera_rig()
