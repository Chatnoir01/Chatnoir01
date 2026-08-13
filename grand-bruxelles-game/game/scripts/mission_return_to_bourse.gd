extends Node

signal mission_completed(reward_cents: int)
signal state_changed(checkpoint_name: String)

const STATE_SCHEMA_VERSION := 1
const LOCKED := 0
const AVAILABLE := 1
const ACTIVE := 2
const COMPLETED := 3
const GRAND_PLACE := Vector3(319.01, 0.08, -535.20)
const BOURSE := Vector3(81.54, 0.08, -664.58)

@export var start_radius := 28.0
@export var destination_radius := 22.0
@export var completion_reward_cents := 12000

@onready var primary_mission: Node = get_node("../MissionDriveToCenter")
@onready var player: CharacterBody3D = get_node("../Player")
@onready var car: CharacterBody3D = get_node("../PrototypeCar")
@onready var mission_label: Label = get_node("../MissionLabel")

var _state := LOCKED
var _reward_claimed := false
var _offer_delay_remaining := 0.0
var _marker: CSGCylinder3D
var _marker_material: StandardMaterial3D


func _ready() -> void:
    primary_mission.mission_completed.connect(_on_primary_mission_completed)
    _build_marker()


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode == KEY_F and _state == AVAILABLE and _can_start_here():
        _state = ACTIVE
        _marker.visible = true
        _update_ui()
        state_changed.emit("Retour Express démarré")
        get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
    if _state == LOCKED and _primary_is_completed():
        _state = AVAILABLE
        _offer_delay_remaining = 0.0
        _update_ui()
    if _state == AVAILABLE:
        if _offer_delay_remaining > 0.0:
            _offer_delay_remaining = maxf(0.0, _offer_delay_remaining - delta)
        if _offer_delay_remaining <= 0.0:
            _update_ui()
    if _state != ACTIVE:
        return
    if _actor_position().distance_to(BOURSE) > destination_radius:
        return
    _state = COMPLETED
    _marker.visible = false
    _update_ui()
    state_changed.emit("Retour Express terminé")
    if not _reward_claimed:
        _reward_claimed = true
        mission_completed.emit(maxi(completion_reward_cents, 0))


func restart_campaign() -> void:
    _state = LOCKED
    _reward_claimed = false
    _offer_delay_remaining = 0.0
    if is_instance_valid(_marker):
        _marker.visible = false


func get_state() -> int:
    return _state


func export_state() -> Dictionary:
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "state": _state,
        "reward_claimed": _reward_claimed,
    }


func can_restore_state(state: Dictionary) -> bool:
    if int(state.get("schema_version", -1)) != STATE_SCHEMA_VERSION:
        return false
    var state_value: Variant = state.get("state", null)
    if not (state_value is int or state_value is float):
        return false
    var state_float := float(state_value)
    if not is_finite(state_float) or state_float != floorf(state_float):
        return false
    var restored_state := int(state_float)
    if restored_state < LOCKED or restored_state > COMPLETED:
        return false
    var claimed_value: Variant = state.get("reward_claimed", false)
    if not claimed_value is bool:
        return false
    return not bool(claimed_value) or restored_state == COMPLETED


func restore_state(state: Dictionary) -> bool:
    if not can_restore_state(state):
        return false
    _state = int(state["state"])
    _reward_claimed = _state == COMPLETED or bool(state.get("reward_claimed", false))
    _offer_delay_remaining = 0.0
    if is_instance_valid(_marker):
        _marker.visible = _state == ACTIVE
        _update_ui()
    return true


func restore_legacy_state(primary_completed: bool) -> void:
    _state = AVAILABLE if primary_completed else LOCKED
    _reward_claimed = false
    _offer_delay_remaining = 0.0
    if is_instance_valid(_marker):
        _marker.visible = false
        _update_ui()


func _on_primary_mission_completed(_reward_cents: int) -> void:
    if _state != LOCKED:
        return
    _state = AVAILABLE
    _offer_delay_remaining = 3.0


func _primary_is_completed() -> bool:
    return int(primary_mission.call("get_stage")) == int(primary_mission.call("get_stage_count"))


func _can_start_here() -> bool:
    return not bool(car.call("has_driver")) and player.global_position.distance_to(GRAND_PLACE) <= start_radius


func _actor_position() -> Vector3:
    return car.global_position if bool(car.call("has_driver")) else player.global_position


func _update_ui() -> void:
    match _state:
        AVAILABLE:
            if _can_start_here():
                mission_label.text = "NOUVELLE MISSION · RETOUR EXPRESS\nF · Accepter le trajet Grand-Place → Bourse"
            else:
                mission_label.text = "NOUVELLE MISSION · RETOUR EXPRESS\nDescends à Grand-Place pour accepter le trajet"
        ACTIVE:
            mission_label.text = "RETOUR EXPRESS · PLACE DE LA BOURSE\nRejoins le marqueur · Récompense 120 €"
        COMPLETED:
            mission_label.text = "MISSION TERMINÉE · RETOUR EXPRESS\nBourse atteinte · Récompense 120 €"


func _build_marker() -> void:
    _marker_material = StandardMaterial3D.new()
    _marker_material.albedo_color = Color(0.30, 0.78, 1.0, 0.60)
    _marker_material.emission_enabled = true
    _marker_material.emission = Color(0.12, 0.48, 0.9)
    _marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    _marker = CSGCylinder3D.new()
    _marker.name = "ReturnToBourseMarker"
    _marker.radius = 6.5
    _marker.height = 0.24
    _marker.position = BOURSE + Vector3.UP * 0.12
    _marker.material = _marker_material
    _marker.use_collision = false
    _marker.visible = _state == ACTIVE
    get_parent().call_deferred("add_child", _marker)
