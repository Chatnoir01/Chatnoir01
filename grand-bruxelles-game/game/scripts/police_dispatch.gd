extends Node3D

const OFFICER_SCENE: PackedScene = preload("res://game/police/police_officer.tscn")
const PATROL_SCENE: PackedScene = preload("res://game/vehicles/police_patrol.tscn")
const CIVIL_SCENE: PackedScene = preload("res://game/vehicles/police_civil.tscn")
const BAB_SCENE: PackedScene = preload("res://game/vehicles/police_bab_van.tscn")
const ROADBLOCK_SCENE: PackedScene = preload("res://game/police/police_roadblock.tscn")

@export var spawn_radius: float = 18.0
@export var spawn_height: float = 1.0
@export var pursuit_vehicle_spawn_distance: float = 34.0
@export var pursuit_lateral_spacing: float = 7.0
@export var roadblock_ahead_distance: float = 52.0

var _active_officers: Array[Node] = []
var _active_pursuit_vehicles: Array[Node3D] = []
var _active_blockades: Array[Node3D] = []


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
    _sync_officers(level)
    _sync_pursuit_vehicles(level)
    _sync_blockades(level)
    _set_police_vehicle_emergency(level > 0)
    _update_hud(level)


func _sync_officers(level: int) -> void:
    _cleanup_officers()
    var target_count: int = _officer_target_count(level)

    while _active_officers.size() < target_count:
        _spawn_officer(_active_officers.size())

    while _active_officers.size() > target_count:
        var officer: Node = _active_officers.pop_back() as Node
        if is_instance_valid(officer):
            officer.queue_free()


func _sync_pursuit_vehicles(level: int) -> void:
    _cleanup_pursuit_vehicles()
    var target_count: int = _vehicle_target_count(level)

    while _active_pursuit_vehicles.size() < target_count:
        _spawn_pursuit_vehicle(_active_pursuit_vehicles.size(), level)

    while _active_pursuit_vehicles.size() > target_count:
        var vehicle: Node3D = _active_pursuit_vehicles.pop_back() as Node3D
        if is_instance_valid(vehicle):
            if vehicle.has_method("clear_ai_control"):
                vehicle.call("clear_ai_control")
            vehicle.queue_free()


func _sync_blockades(level: int) -> void:
    _cleanup_blockades()
    var target_count: int = _roadblock_target_count(level)

    while _active_blockades.size() < target_count:
        _spawn_roadblock(_active_blockades.size())

    while _active_blockades.size() > target_count:
        var blockade: Node3D = _active_blockades.pop_back() as Node3D
        if is_instance_valid(blockade):
            blockade.queue_free()


func _spawn_officer(index: int) -> void:
    var player: Node3D = _player()
    if player == null:
        return
    var officer: Node3D = OFFICER_SCENE.instantiate() as Node3D
    if officer == null:
        return
    add_child(officer)
    var divisor: float = maxf(1.0, float(_officer_target_count(maxi(1, index + 1))))
    var angle: float = TAU * float(index) / divisor
    var radius: float = spawn_radius + float(index % 2) * 5.0
    var offset: Vector3 = Vector3(cos(angle) * radius, spawn_height, sin(angle) * radius)
    officer.global_position = _player_position(player) + offset
    _active_officers.append(officer)


func _spawn_pursuit_vehicle(index: int, level: int) -> void:
    var player: Node3D = _player()
    if player == null:
        return
    var scene: PackedScene = _vehicle_scene_for(index, level)
    var vehicle: Node3D = scene.instantiate() as Node3D
    if vehicle == null:
        return

    var world: Node = get_parent()
    world.add_child(vehicle)
    vehicle.name = "PolicePursuit_%d" % index
    vehicle.add_to_group("police_pursuit_unit")

    var player_position: Vector3 = _player_position(player)
    var player_forward: Vector3 = _player_forward(player)
    var player_velocity: Vector3 = _player_velocity(player)
    var approach: Vector3 = player_velocity
    approach.y = 0.0
    if approach.length_squared() < 4.0:
        approach = player_forward
    if approach.length_squared() < 0.001:
        approach = Vector3(0.0, 0.0, -1.0)
    approach = approach.normalized()
    var lateral: Vector3 = Vector3(-approach.z, 0.0, approach.x)
    var side_sign: float = -1.0 if index % 2 == 0 else 1.0
    var desired_spawn: Vector3 = (
        player_position
        - approach * (pursuit_vehicle_spawn_distance + float(index) * 10.0)
        + lateral * pursuit_lateral_spacing * side_sign
    )

    var router: Node = _road_router()
    if router != null and router.has_method("nearest_road_point"):
        desired_spawn = router.call("nearest_road_point", desired_spawn) as Vector3
    vehicle.global_position = desired_spawn + Vector3.UP * 0.42

    var tangent: Vector3 = approach
    if router != null and router.has_method("road_tangent_near"):
        tangent = router.call("road_tangent_near", desired_spawn) as Vector3
    if tangent.dot(player_position - desired_spawn) < 0.0:
        tangent = -tangent
    if tangent.length_squared() > 0.001:
        vehicle.rotation.y = atan2(-tangent.x, -tangent.z)

    if vehicle.has_method("set_ai_pursuit"):
        vehicle.call("set_ai_pursuit", player, router)
    var visuals: Node = vehicle.get_node_or_null("EmergencyVisuals")
    if visuals != null and visuals.has_method("set_emergency_lights"):
        visuals.call("set_emergency_lights", true)
    _active_pursuit_vehicles.append(vehicle)


func _spawn_roadblock(index: int) -> void:
    var player: Node3D = _player()
    if player == null:
        return
    var blockade: Node3D = ROADBLOCK_SCENE.instantiate() as Node3D
    if blockade == null:
        return

    var world: Node = get_parent()
    world.add_child(blockade)
    blockade.name = "PoliceRoadblock_%d" % index

    var forward: Vector3 = _player_velocity(player)
    forward.y = 0.0
    if forward.length_squared() < 4.0:
        forward = _player_forward(player)
    if forward.length_squared() < 0.001:
        forward = Vector3(0.0, 0.0, -1.0)
    forward = forward.normalized()

    var desired: Vector3 = _player_position(player) + forward * (roadblock_ahead_distance + float(index) * 34.0)
    var router: Node = _road_router()
    if router != null and router.has_method("nearest_road_point"):
        desired = router.call("nearest_road_point", desired) as Vector3

    blockade.global_position = desired + Vector3.UP * 0.12
    var tangent: Vector3 = forward
    if router != null and router.has_method("road_tangent_near"):
        tangent = router.call("road_tangent_near", desired) as Vector3
    if tangent.length_squared() > 0.001:
        blockade.rotation.y = atan2(tangent.x, tangent.z)

    _active_blockades.append(blockade)


func _cleanup_officers() -> void:
    var valid: Array[Node] = []
    for officer: Node in _active_officers:
        if is_instance_valid(officer) and not officer.is_queued_for_deletion():
            valid.append(officer)
    _active_officers = valid


func _cleanup_pursuit_vehicles() -> void:
    var valid: Array[Node3D] = []
    for vehicle: Node3D in _active_pursuit_vehicles:
        if is_instance_valid(vehicle) and not vehicle.is_queued_for_deletion():
            valid.append(vehicle)
    _active_pursuit_vehicles = valid


func _cleanup_blockades() -> void:
    var valid: Array[Node3D] = []
    for blockade: Node3D in _active_blockades:
        if is_instance_valid(blockade) and not blockade.is_queued_for_deletion():
            valid.append(blockade)
    _active_blockades = valid


func get_deployed_count() -> int:
    _cleanup_officers()
    return _active_officers.size()


func get_deployed_vehicle_count() -> int:
    _cleanup_pursuit_vehicles()
    return _active_pursuit_vehicles.size()


func get_blockade_count() -> int:
    _cleanup_blockades()
    return _active_blockades.size()


func _officer_target_count(level: int) -> int:
    match level:
        0:
            return 0
        1:
            return 1
        2:
            return 2
        3:
            return 2
        4:
            return 3
        _:
            return 4


func _vehicle_target_count(level: int) -> int:
    match level:
        0, 1:
            return 0
        2:
            return 1
        3, 4:
            return 2
        _:
            return 3


func _roadblock_target_count(level: int) -> int:
    if level >= 5:
        return 2
    if level >= 4:
        return 1
    return 0


func _vehicle_scene_for(index: int, _level: int) -> PackedScene:
    if index <= 0:
        return PATROL_SCENE
    if index == 1:
        return CIVIL_SCENE
    return BAB_SCENE


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


func _road_router() -> Node:
    return get_tree().get_first_node_in_group("police_road_router")


func _player_position(player: Node3D) -> Vector3:
    if player.has_method("get_gameplay_position"):
        return player.call("get_gameplay_position") as Vector3
    return player.global_position


func _player_velocity(player: Node3D) -> Vector3:
    if player.has_method("get_gameplay_velocity"):
        return player.call("get_gameplay_velocity") as Vector3
    if player is CharacterBody3D:
        return (player as CharacterBody3D).velocity
    return Vector3.ZERO


func _player_forward(player: Node3D) -> Vector3:
    if player.has_method("get_gameplay_forward"):
        return player.call("get_gameplay_forward") as Vector3
    return -player.global_transform.basis.z.normalized()
