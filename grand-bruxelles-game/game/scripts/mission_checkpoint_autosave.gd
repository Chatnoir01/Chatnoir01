extends Node

const GameStateSaveCoordinator = preload("res://game/scripts/game_state_save_coordinator.gd")

@export var autosave_path := "user://grand_bruxelles_checkpoint_autosave.json"
@export var feedback_duration_seconds := 3.0

@onready var mission: Node = get_node("../MissionDriveToCenter")
@onready var gameplay_state: Node = get_node("../RuntimeGameplayState")
@onready var status_label: Label = get_node("../SaveStatusLabel")

var _feedback_remaining := 0.0
var _feedback_text := ""
var _resume_attempted := false
var _resumed_from_autosave := false


func _ready() -> void:
    mission.checkpoint_reached.connect(_on_checkpoint_reached)
    if not _running_from_test_script():
        call_deferred("resume_autosave")


func _process(delta: float) -> void:
    if _feedback_remaining <= 0.0:
        return
    _feedback_remaining = maxf(0.0, _feedback_remaining - delta)
    if _feedback_remaining <= 0.0 and status_label.text == _feedback_text:
        status_label.visible = false


func _unhandled_input(event: InputEvent) -> void:
    if not _resumed_from_autosave:
        return
    if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
        if clear_autosave():
            _resumed_from_autosave = false
            mission.call("restart_mission")
            _show_feedback("NOUVELLE PARTIE · Bruxelles-Midi", false)
        else:
            _show_feedback("NOUVELLE PARTIE IMPOSSIBLE", true)


func resume_autosave() -> bool:
    if _resume_attempted:
        return false
    _resume_attempted = true
    if not _valid_autosave_path() or not FileAccess.file_exists(autosave_path):
        return false

    var result: Dictionary = GameStateSaveCoordinator.load_domains(
        autosave_path,
        {"runtime": gameplay_state}
    )
    if not bool(result.get("ok", false)):
        _show_feedback("REPRISE AUTO IMPOSSIBLE", true)
        return false
    _resumed_from_autosave = true
    _show_feedback("REPRISE AUTO · N nouvelle partie", false)
    return true


func clear_autosave() -> bool:
    if not _valid_autosave_path():
        return false
    var absolute := ProjectSettings.globalize_path(autosave_path)
    for suffix: String in ["", ".tmp", ".bak"]:
        var candidate := absolute + suffix
        if FileAccess.file_exists(candidate):
            if DirAccess.remove_absolute(candidate) != OK:
                return false
    return true


func _on_checkpoint_reached(_completed_stage: int, checkpoint_name: String) -> void:
    call_deferred("_save_checkpoint", checkpoint_name)


func _save_checkpoint(checkpoint_name: String) -> void:
    if not _valid_autosave_path():
        _show_feedback("SAUVEGARDE AUTO IMPOSSIBLE", true)
        return
    var result: Dictionary = GameStateSaveCoordinator.save_domains(
        autosave_path,
        {"runtime": gameplay_state}
    )
    if not bool(result.get("ok", false)):
        _show_feedback("SAUVEGARDE AUTO IMPOSSIBLE", true)
        return
    _show_feedback("SAUVEGARDE AUTO · %s" % checkpoint_name, false)


func _show_feedback(message: String, is_error: bool) -> void:
    status_label.visible = true
    status_label.text = message
    _feedback_text = message
    status_label.modulate = (
        Color(1.0, 0.52, 0.42, 1.0)
        if is_error
        else Color(0.55, 1.0, 0.67, 1.0)
    )
    _feedback_remaining = maxf(feedback_duration_seconds, 0.1)


func _valid_autosave_path() -> bool:
    return (
        autosave_path.begins_with("user://")
        and not autosave_path.contains("..")
        and autosave_path.get_extension().to_lower() == "json"
    )


func _running_from_test_script() -> bool:
    for argument: String in OS.get_cmdline_args():
        if argument == "--script" or argument.begins_with("--script="):
            return true
    return false
