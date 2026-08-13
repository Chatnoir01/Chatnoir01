extends Node

const GameStateSaveCoordinator = preload("res://game/scripts/game_state_save_coordinator.gd")
const MissionSaveCoordinator = preload("res://game/scripts/mission_save_coordinator.gd")

@export var save_path: String = "user://grand_bruxelles_quicksave.json"
@export var feedback_duration_seconds: float = 2.5

@onready var mission: Node = get_node("../MissionDriveToCenter")
@onready var gameplay_state: Node = get_node("../RuntimeGameplayState")
@onready var status_label: Label = get_node("../SaveStatusLabel")

var _feedback_remaining: float = 0.0


func _ready() -> void:
    status_label.visible = false


func _process(delta: float) -> void:
    if _feedback_remaining <= 0.0:
        return
    _feedback_remaining = maxf(0.0, _feedback_remaining - delta)
    if _feedback_remaining <= 0.0:
        status_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
    if not event is InputEventKey or not event.pressed or event.echo:
        return
    if event.keycode == KEY_F5:
        quick_save()
    elif event.keycode == KEY_F9:
        quick_load()


func quick_save() -> bool:
    if not _valid_save_path():
        _show_feedback("SAUVEGARDE IMPOSSIBLE", true)
        return false
    var result: Dictionary = GameStateSaveCoordinator.save_domains(save_path, {"runtime": gameplay_state})
    if not bool(result.get("ok", false)):
        _show_feedback("SAUVEGARDE IMPOSSIBLE", true)
        return false
    _show_feedback("PARTIE SAUVEGARDÉE · F9 pour charger", false)
    return true


func quick_load() -> bool:
    if not _valid_save_path():
        _show_feedback("CHARGEMENT IMPOSSIBLE", true)
        return false
    var result: Dictionary = GameStateSaveCoordinator.load_domains(save_path, {"runtime": gameplay_state})
    if not bool(result.get("ok", false)) and str(result.get("error", "")) in ["missing_domains", "domain_not_found"]:
        result = MissionSaveCoordinator.load_mission(save_path, mission)
        if bool(result.get("ok", false)):
            _show_feedback("ANCIENNE MISSION CHARGÉE · position non restaurée", false)
            return true
    if not bool(result.get("ok", false)):
        var message := "AUCUNE SAUVEGARDE" if str(result.get("error", "")) == "not_found" else "CHARGEMENT IMPOSSIBLE"
        _show_feedback(message, true)
        return false
    _show_feedback("PARTIE CHARGÉE", false)
    return true


func _show_feedback(message: String, is_error: bool) -> void:
    status_label.visible = true
    status_label.text = message
    status_label.modulate = Color(1.0, 0.52, 0.42, 1.0) if is_error else Color(0.55, 1.0, 0.67, 1.0)
    _feedback_remaining = maxf(feedback_duration_seconds, 0.1)


func _valid_save_path() -> bool:
    return (
        save_path.begins_with("user://")
        and not save_path.contains("..")
        and save_path.get_extension().to_lower() == "json"
    )
