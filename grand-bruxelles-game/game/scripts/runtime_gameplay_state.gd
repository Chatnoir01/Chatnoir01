extends Node

const STATE_SCHEMA_VERSION := 1
const MAX_WORLD_COORDINATE := 10000.0
const MAX_LINEAR_VELOCITY := 250.0

@onready var mission: Node = get_node("../MissionDriveToCenter")
@onready var return_mission: Node = get_node("../MissionReturnToBourse")
@onready var player: CharacterBody3D = get_node("../Player")
@onready var vehicle: CharacterBody3D = get_node("../PrototypeCar")
@onready var wallet: Node = get_node("../Wallet")


func export_state() -> Dictionary:
    return {
        "schema_version": STATE_SCHEMA_VERSION,
        "mission": mission.call("export_state"),
        "player": {
            "position": _vector_to_array(player.global_position),
            "rotation": _vector_to_array(player.rotation),
            "velocity": _vector_to_array(player.velocity),
        },
        "vehicle": {
            "position": _vector_to_array(vehicle.global_position),
            "rotation": _vector_to_array(vehicle.rotation),
            "velocity": _vector_to_array(vehicle.velocity),
            "speed": float(vehicle.get("speed")),
            "driver_active": bool(vehicle.call("has_driver")),
        },
        "wallet": wallet.call("export_state"),
        "return_mission": return_mission.call("export_state"),
    }


func can_restore_state(state: Dictionary) -> bool:
    if int(state.get("schema_version", -1)) != STATE_SCHEMA_VERSION:
        return false

    var mission_state: Variant = state.get("mission", null)
    var player_state: Variant = state.get("player", null)
    var vehicle_state: Variant = state.get("vehicle", null)
    if not mission_state is Dictionary or not player_state is Dictionary or not vehicle_state is Dictionary:
        return false
    if not mission.has_method("can_restore_state") or not bool(mission.call("can_restore_state", mission_state)):
        return false
    if state.has("wallet"):
        var wallet_state: Variant = state["wallet"]
        if not wallet_state is Dictionary or not bool(wallet.call("can_restore_state", wallet_state)):
            return false
    if state.has("return_mission"):
        var return_state: Variant = state["return_mission"]
        if not return_state is Dictionary or not bool(return_mission.call("can_restore_state", return_state)):
            return false
        var return_data: Dictionary = return_state
        if (
            int(return_data.get("state", 0)) > 0
            and int(mission_state.get("stage", -1)) != int(mission_state.get("stage_count", -2))
        ):
            return false

    var player_data: Dictionary = player_state
    var vehicle_data: Dictionary = vehicle_state
    if not _valid_vector(player_data.get("position"), MAX_WORLD_COORDINATE):
        return false
    if not _valid_vector(player_data.get("rotation"), TAU * 8.0):
        return false
    if not _valid_vector(player_data.get("velocity"), MAX_LINEAR_VELOCITY):
        return false
    if not _valid_vector(vehicle_data.get("position"), MAX_WORLD_COORDINATE):
        return false
    if not _valid_vector(vehicle_data.get("rotation"), TAU * 8.0):
        return false
    if not _valid_vector(vehicle_data.get("velocity"), MAX_LINEAR_VELOCITY):
        return false
    if not vehicle_data.get("driver_active") is bool:
        return false

    var speed_value: Variant = vehicle_data.get("speed", null)
    if not _valid_number(speed_value):
        return false
    var speed := float(speed_value)
    if absf(speed) > maxf(float(vehicle.get("max_forward_speed")), float(vehicle.get("max_reverse_speed"))) + 1.0:
        return false
    return true


func restore_state(state: Dictionary) -> bool:
    if not can_restore_state(state):
        return false
    var backup := export_state()
    if _apply_state(state):
        return true
    _apply_state(backup)
    return false


func _apply_state(state: Dictionary) -> bool:
    var mission_state: Dictionary = state["mission"]
    var player_state: Dictionary = state["player"]
    var vehicle_state: Dictionary = state["vehicle"]

    if bool(vehicle.call("has_driver")):
        vehicle.call("exit_driver")

    vehicle.global_position = _array_to_vector(vehicle_state["position"])
    vehicle.rotation = _array_to_vector(vehicle_state["rotation"])
    vehicle.velocity = _array_to_vector(vehicle_state["velocity"])
    vehicle.set("speed", float(vehicle_state["speed"]))

    player.global_position = _array_to_vector(player_state["position"])
    player.rotation = _array_to_vector(player_state["rotation"])
    player.velocity = _array_to_vector(player_state["velocity"])

    var driver_active: bool = bool(vehicle_state["driver_active"])
    if driver_active:
        vehicle.call("enter_driver", player)
        vehicle.velocity = _array_to_vector(vehicle_state["velocity"])
        vehicle.set("speed", float(vehicle_state["speed"]))
    else:
        player.call("set_vehicle_mode", false)

    var wallet_restored := true
    if state.has("wallet"):
        wallet_restored = bool(wallet.call("restore_state", state["wallet"]))
    var mission_restored := bool(mission.call("restore_state", mission_state))
    var return_restored := true
    if state.has("return_mission"):
        return_restored = bool(return_mission.call("restore_state", state["return_mission"]))
    else:
        return_mission.call("restore_legacy_state", int(mission_state["stage"]) == int(mission_state["stage_count"]))
    return wallet_restored and mission_restored and return_restored


func _valid_vector(value: Variant, absolute_limit: float) -> bool:
    if not value is Array or value.size() != 3:
        return false
    for component: Variant in value:
        if not _valid_number(component) or absf(float(component)) > absolute_limit:
            return false
    return true


func _valid_number(value: Variant) -> bool:
    return (value is float or value is int) and is_finite(float(value))


func _vector_to_array(value: Vector3) -> Array[float]:
    return [value.x, value.y, value.z]


func _array_to_vector(value: Array) -> Vector3:
    return Vector3(float(value[0]), float(value[1]), float(value[2]))
