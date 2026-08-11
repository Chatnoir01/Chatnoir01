extends Node3D

signal crossing_finished(agent: Node)

@export var walk_speed_mps: float = 1.35

var crossing_id: int = 0
var pedestrian_id: int = 0
var _crossing_system: RefCounted = null
var _start := Vector3.ZERO
var _finish := Vector3.ZERO
var _wait_until_s: float = 0.0
var _started := false
var _finishing := false


func configure(
    descriptor: Dictionary,
    crossing_system: RefCounted,
    new_pedestrian_id: int,
    reverse_direction: bool,
    wait_seconds: float
) -> void:
    crossing_id = int(descriptor.get("id", 0))
    pedestrian_id = new_pedestrian_id
    _crossing_system = crossing_system
    _start = descriptor.get("start", Vector3.ZERO)
    _finish = descriptor.get("finish", Vector3.ZERO)
    if reverse_direction:
        var swap := _start
        _start = _finish
        _finish = swap

    global_position = _start
    var direction := _finish - _start
    direction.y = 0.0
    if direction.length_squared() > 0.001:
        direction = direction.normalized()
        rotation.y = atan2(-direction.x, -direction.z)

    _wait_until_s = float(Time.get_ticks_msec()) / 1000.0 + maxf(0.0, wait_seconds)
    if _crossing_system != null:
        _crossing_system.call("register_waiting", crossing_id, pedestrian_id)
    set_process(true)


func _process(delta: float) -> void:
    if _finishing:
        return

    var now_seconds := float(Time.get_ticks_msec()) / 1000.0
    if not _started:
        if now_seconds < _wait_until_s:
            return
        _started = true
        if _crossing_system != null:
            _crossing_system.call("begin_crossing", crossing_id, pedestrian_id)

    var to_finish := _finish - global_position
    to_finish.y = 0.0
    if to_finish.length() <= 0.25:
        _finish_crossing()
        return

    var step := minf(to_finish.length(), walk_speed_mps * delta)
    global_position += to_finish.normalized() * step


func _finish_crossing() -> void:
    if _finishing:
        return
    _finishing = true
    if _crossing_system != null:
        _crossing_system.call("clear_pedestrian", crossing_id, pedestrian_id)
    crossing_finished.emit(self)


func _exit_tree() -> void:
    if _crossing_system != null and crossing_id > 0 and pedestrian_id > 0:
        _crossing_system.call("clear_pedestrian", crossing_id, pedestrian_id)


func get_crossing_id() -> int:
    return crossing_id


func has_started_crossing() -> bool:
    return _started
