extends CharacterBody3D

@export var move_speed: float = 7.2
@export var acceleration: float = 19.0
@export var arrest_range: float = 2.1
@export var arrest_hold_seconds: float = 1.1
@export var disengage_distance: float = 140.0

var gravity: float = float(ProjectSettings.get_setting("physics/3d/default_gravity"))
var _arrest_progress: float = 0.0
var state: StringName = &"idle"


func _physics_process(delta: float) -> void:
    if not is_on_floor():
        velocity.y -= gravity * delta
    else:
        velocity.y = -0.1

    var player := _player()
    var wanted := _wanted_system()
    if player == null or wanted == null or not bool(wanted.call("is_wanted")):
        state = &"idle"
        _arrest_progress = 0.0
        velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
        velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
        move_and_slide()
        return

    state = &"pursuit"
    var target_position: Vector3 = player.global_position
    if player.has_method("get_gameplay_position"):
        target_position = player.call("get_gameplay_position") as Vector3

    var flat_offset := target_position - global_position
    flat_offset.y = 0.0
    var distance := flat_offset.length()

    if distance > disengage_distance:
        velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
        velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
        move_and_slide()
        return

    if distance > 0.05:
        var direction := flat_offset.normalized()
        velocity.x = move_toward(velocity.x, direction.x * move_speed, acceleration * delta)
        velocity.z = move_toward(velocity.z, direction.z * move_speed, acceleration * delta)
        look_at(Vector3(target_position.x, global_position.y, target_position.z), Vector3.UP)
    else:
        velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
        velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)

    move_and_slide()

    var player_in_vehicle := player.has_method("is_in_vehicle") and bool(player.call("is_in_vehicle"))
    var player_arrested := player.has_method("is_arrested") and bool(player.call("is_arrested"))
    if distance <= arrest_range and not player_in_vehicle and not player_arrested:
        _arrest_progress += delta
        if _arrest_progress >= arrest_hold_seconds:
            wanted.call("arrest_player", player)
            _arrest_progress = 0.0
    else:
        _arrest_progress = 0.0


func get_state() -> StringName:
    return state


func _player() -> Node3D:
    return get_tree().get_first_node_in_group("player") as Node3D


func _wanted_system() -> Node:
    return get_tree().get_first_node_in_group("wanted_system")
