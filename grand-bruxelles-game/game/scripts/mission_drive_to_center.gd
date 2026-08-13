extends Node

@export var checkpoint_radius: float = 22.0
@export var time_limit_seconds: float = 240.0

@onready var player: CharacterBody3D = get_node("../Player")
@onready var car: CharacterBody3D = get_node("../PrototypeCar")
@onready var mission_label: Label = get_node("../MissionLabel")

var _stage: int = 0
var _time_remaining: float = 0.0
var _failed: bool = false
var _marker: CSGCylinder3D
var _marker_material: StandardMaterial3D
var _player_spawn_transform: Transform3D
var _car_spawn_transform: Transform3D

const MISSION_ID: String = "midi_to_centre_01"
const STATE_SCHEMA_VERSION: int = 1

const CHECKPOINTS: Array[Dictionary] = [
    {
        "name": "Place Anneessens",
        "position": Vector3(-272.04, 0.08, -217.07),
    },
    {
        "name": "Bourse / Beurs",
        "position": Vector3(81.54, 0.08, -664.58),
    },
    {
        "name": "Grand-Place",
        "position": Vector3(319.01, 0.08, -535.20),
    },
]


func _ready() -> void:
    _player_spawn_transform = player.global_transform
    _car_spawn_transform = car.global_transform
    _time_remaining = maxf(time_limit_seconds, 1.0)
    _marker_material = StandardMaterial3D.new()
    _marker_material.albedo_color = Color(1.0, 0.78, 0.08, 0.72)
    _marker_material.emission_enabled = true
    _marker_material.emission = Color(1.0, 0.52, 0.04, 1.0)
    _marker_material.emission_energy_multiplier = 1.5
    _marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

    _marker = CSGCylinder3D.new()
    _marker.name = "MissionCheckpoint"
    _marker.radius = 5.5
    _marker.height = 0.12
    _marker.sides = 32
    _marker.material = _marker_material
    _marker.use_collision = false
    _marker.visible = false
    add_child(_marker)
    _update_ui()


func _physics_process(delta: float) -> void:
    if _failed:
        return

    if _stage == 0:
        if bool(car.call("has_driver")):
            _stage = 1
            _time_remaining = maxf(time_limit_seconds, 1.0)
            _update_ui()
        return

    if _stage > CHECKPOINTS.size():
        return

    _time_remaining = maxf(0.0, _time_remaining - delta)
    if _time_remaining <= 0.0:
        _fail_mission()
        return

    if not bool(car.call("has_driver")):
        mission_label.text = (
            "MISSION 01 · MIDI → CENTRE · %s\nRemonte dans la voiture · E" %
            _format_time(_time_remaining)
        )
        return

    var target: Dictionary = CHECKPOINTS[_stage - 1]
    var target_position: Vector3 = target["position"]
    var distance: float = car.global_position.distance_to(target_position)
    mission_label.text = (
        "MISSION 01 · MIDI → CENTRE · %s\n%s · %.0f m" %
        [_format_time(_time_remaining), str(target["name"]), distance]
    )

    if distance <= checkpoint_radius:
        _stage += 1
        _update_ui()


func _update_ui() -> void:
    if _failed:
        mission_label.text = "MISSION ÉCHOUÉE · TEMPS ÉCOULÉ\nR · Recommencer depuis Bruxelles-Midi"
        _marker.visible = false
        return

    if _stage == 0:
        mission_label.text = (
            "MISSION 01 · MIDI → CENTRE · %s\nMonte dans la voiture · E" %
            _format_time(time_limit_seconds)
        )
        _marker.visible = false
        return

    if _stage > CHECKPOINTS.size():
        mission_label.text = (
            "MISSION TERMINÉE · BIENVENUE À GRAND-PLACE\nTemps restant · %s" %
            _format_time(_time_remaining)
        )
        _marker.visible = false
        return

    var target: Dictionary = CHECKPOINTS[_stage - 1]
    _marker.global_position = target["position"]
    _marker.visible = true
    mission_label.text = (
        "MISSION 01 · MIDI → CENTRE · %s\nRejoins %s" %
        [_format_time(_time_remaining), str(target["name"])]
    )


func _unhandled_input(event: InputEvent) -> void:
    if not _failed:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_R:
        restart_mission()


func _fail_mission() -> void:
    _time_remaining = 0.0
    _failed = true
    _update_ui()


func restart_mission() -> void:
    if bool(car.call("has_driver")):
        car.call("exit_driver")
    player.global_transform = _player_spawn_transform
    player.velocity = Vector3.ZERO
    car.global_transform = _car_spawn_transform
    car.velocity = Vector3.ZERO
    car.set("speed", 0.0)
    _stage = 0
    _failed = false
    _time_remaining = maxf(time_limit_seconds, 1.0)
    _update_ui()


func _format_time(seconds_value: float) -> String:
    var total_seconds: int = maxi(0, int(ceilf(seconds_value)))
    return "%02d:%02d" % [total_seconds / 60, total_seconds % 60]


func export_state() -> Dictionary:
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "mission_id": MISSION_ID,
        "stage": _stage,
        "stage_count": get_stage_count(),
        "time_remaining": _time_remaining,
        "failed": _failed,
    }


func can_restore_state(state: Dictionary) -> bool:
    if int(state.get("schema_version", -1)) != STATE_SCHEMA_VERSION:
        return false
    if str(state.get("mission_id", "")) != MISSION_ID:
        return false
    if not state.has("stage"):
        return false

    var restored_stage: int = int(state["stage"])
    if restored_stage < 0 or restored_stage > get_stage_count():
        return false

    var restored_time: float = maxf(time_limit_seconds, 1.0)
    if state.has("time_remaining"):
        var time_value: Variant = state["time_remaining"]
        if not (time_value is float or time_value is int):
            return false
        restored_time = float(time_value)
        if not is_finite(restored_time) or restored_time < 0.0 or restored_time > maxf(time_limit_seconds, 1.0):
            return false

    var restored_failed: bool = false
    if state.has("failed"):
        if not state["failed"] is bool:
            return false
        restored_failed = bool(state["failed"])
    if restored_failed and (restored_stage == 0 or restored_stage > CHECKPOINTS.size()):
        return false

    return true


func restore_state(state: Dictionary) -> bool:
    if not can_restore_state(state):
        return false

    _stage = int(state["stage"])
    _time_remaining = float(state.get("time_remaining", maxf(time_limit_seconds, 1.0)))
    _failed = bool(state.get("failed", false))
    if is_instance_valid(_marker) and is_instance_valid(mission_label):
        _update_ui()
    return true


func get_mission_id() -> String:
    return MISSION_ID


func get_stage() -> int:
    return _stage


func get_stage_count() -> int:
    return CHECKPOINTS.size() + 1


func get_time_remaining() -> float:
    return _time_remaining


func is_failed() -> bool:
    return _failed
