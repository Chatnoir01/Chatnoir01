extends Node

signal wanted_level_changed(level: int, heat: float)
signal pursuit_started
signal pursuit_ended
signal player_arrested
signal arrest_released

@export var heat_decay_delay: float = 18.0
@export var heat_decay_per_second: float = 2.5
@export var arrest_hold_seconds: float = 3.5

const HEAT_THRESHOLDS := [0.0, 12.0, 28.0, 48.0, 72.0, 96.0]

var heat: float = 0.0
var wanted_level: int = 0
var _time_since_offence: float = 999.0
var _arrest_timer: float = 0.0
var _arrested_player: Node = null


func _process(delta: float) -> void:
    if _arrested_player != null:
        _arrest_timer -= delta
        if _arrest_timer <= 0.0:
            release_arrest()
        return

    if wanted_level <= 0:
        return

    _time_since_offence += delta
    if _time_since_offence >= heat_decay_delay:
        set_heat(maxf(0.0, heat - heat_decay_per_second * delta))


func report_offence(severity: float, source: String = "") -> void:
    if severity <= 0.0 or _arrested_player != null:
        return
    _time_since_offence = 0.0
    set_heat(minf(120.0, heat + severity))
    if not source.is_empty():
        print("Grand Bruxelles police offence: %s (+%.1f heat)" % [source, severity])


func set_heat(value: float) -> void:
    var previous_level := wanted_level
    heat = clampf(value, 0.0, 120.0)
    wanted_level = _level_for_heat(heat)

    if wanted_level != previous_level:
        wanted_level_changed.emit(wanted_level, heat)
        if previous_level == 0 and wanted_level > 0:
            pursuit_started.emit()
        elif previous_level > 0 and wanted_level == 0:
            pursuit_ended.emit()


func clear_wanted() -> void:
    _time_since_offence = 999.0
    set_heat(0.0)


func get_wanted_level() -> int:
    return wanted_level


func is_wanted() -> bool:
    return wanted_level > 0


func arrest_player(player: Node) -> void:
    if player == null or _arrested_player != null:
        return
    _arrested_player = player
    _arrest_timer = arrest_hold_seconds
    if player.has_method("set_arrested"):
        player.call("set_arrested", true)
    clear_wanted()
    player_arrested.emit()


func release_arrest() -> void:
    if _arrested_player == null:
        return
    var player := _arrested_player
    _arrested_player = null
    _arrest_timer = 0.0
    if player.has_method("set_arrested"):
        player.call("set_arrested", false)
    if player.has_method("reset_after_arrest"):
        player.call("reset_after_arrest")
    arrest_released.emit()


func is_player_arrested() -> bool:
    return _arrested_player != null


func _level_for_heat(value: float) -> int:
    var level := 0
    for index in range(1, HEAT_THRESHOLDS.size()):
        if value >= float(HEAT_THRESHOLDS[index]):
            level = index
    return level
