extends Node3D

const OFFICER_SCENE: PackedScene = preload("res://game/police/police_officer.tscn")

@export var spawn_radius: float = 18.0
@export var spawn_height: float = 1.0

var _active_officers: Array[Node] = []


func _ready() -> void:
    call_deferred("_bind_wanted_system")


func _bind_wanted_system() -> void:
    var wanted: Node = _wanted_system()
    if wanted == null:
        return
    var callback: Callable = Callable(self, "_on_wanted_level_changed")
    if not wanted.is_connected("wanted_level_changed", callback):
        wanted.connect("wanted_level_changed", callback)
    _sync_units(int(wanted.call("get_wanted_level")))


func _on_wanted_level_changed(level: int, _heat: float) -> void:
    _sync_units(level)


func _sync_units(level: int) -> void:
    _cleanup_officers()
    var target_count: int = _target_count(level)

    while _active_officers.size() < target_count:
        _spawn_officer(_active_officers.size())

    while _active_officers.size() > target_count:
        var officer: Node = _active_officers.pop_back() as Node
        if is_instance_valid(officer):
            officer.queue_free()

    _set_police_vehicle_emergency(level > 0)
    _update_hud(level)


func _spawn_officer(index: int) -> void:
    var player: Node3D = _player()
    if player == null:
        return
    var officer: Node3D = OFFICER_SCENE.instantiate() as Node3D
    if officer == null:
        return
    add_child(officer)
    var divisor: float = maxf(1.0, float(_target_count(maxi(1, index + 1))))
    var angle: float = TAU * float(index) / divisor
    var radius: float = spawn_radius + float(index % 2) * 5.0
    var offset: Vector3 = Vector3(cos(angle) * radius, spawn_height, sin(angle) * radius)
    officer.global_position = _player_position(player) + offset
    _active_officers.append(officer)


func _cleanup_officers() -> void:
    var valid: Array[Node] = []
    for officer: Node in _active_officers:
        if is_instance_valid(officer) and not officer.is_queued_for_deletion():
            valid.append(officer)
    _active_officers = valid


func get_deployed_count() -> int:
    _cleanup_officers()
    return _active_officers.size()


func _target_count(level: int) -> int:
    match level:
        0:
            return 0
        1:
            return 1
        2:
            return 2
        3:
            return 3
        4:
            return 4
        _:
            return 6


func _set_police_vehicle_emergency(enabled: bool) -> void:
    for vehicle: Node in get_tree().get_nodes_in_group("police_vehicle"):
        var visuals: Node = vehicle.get_node_or_null("EmergencyVisuals")
        if visuals != null and visuals.has_method("set_emergency_lights"):
            visuals.call("set_emergency_lights", enabled)


func _update_hud(level: int) -> void:
    var label: Label = get_parent().get_node_or_null("WantedLabel") as Label
    if label == null:
        return
    if level <= 0:
        label.text = "POLICE · aucune recherche"
    else:
        label.text = "POLICE · RECHERCHE  " + "★".repeat(level)


func _player() -> Node3D:
    return get_tree().get_first_node_in_group("player") as Node3D


func _wanted_system() -> Node:
    return get_tree().get_first_node_in_group("wanted_system")


func _player_position(player: Node3D) -> Vector3:
    if player.has_method("get_gameplay_position"):
        return player.call("get_gameplay_position") as Vector3
    return player.global_position
