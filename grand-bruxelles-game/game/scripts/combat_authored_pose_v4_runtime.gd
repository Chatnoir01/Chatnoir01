extends "res://game/scripts/combat_authored_pose_runtime.gd"

# Local animation-only hit-stop. Never touches Engine.time_scale, physics, AI,
# traffic, audio, timers or any other world subsystem.
const LOCAL_HITSTOP_MIN_MS := 18
const LOCAL_HITSTOP_MAX_MS := 90

var _hitstop_player: WeakRef = null
var _hitstop_until_ms := 0
var _resume_speed_scale := 1.0
var _hitstop_active := false

func _process(delta: float) -> void:
    super._process(delta)
    if not _hitstop_active:
        return
    if _animation_player == null or not is_instance_valid(_animation_player):
        _clear_hitstop(false)
        return
    var now := Time.get_ticks_msec()
    if now < _hitstop_until_ms:
        if not is_zero_approx(_animation_player.speed_scale):
            _animation_player.speed_scale = 0.0
        return
    _animation_player.speed_scale = _resume_speed_scale
    var player := _hitstop_player.get_ref() as CharacterBody3D if _hitstop_player != null else null
    if player != null and is_instance_valid(player):
        player.set_meta("combat_hitstop_local_active", false)
        player.set_meta("combat_hitstop_until_ms", now)
    _clear_hitstop(true)

func request_hitstop(player: CharacterBody3D, duration_ms: int) -> bool:
    if player == null or not is_instance_valid(player):
        return false
    if not _ensure_bound(player) or _animation_player == null:
        return false
    var bounded_ms := clampi(duration_ms, LOCAL_HITSTOP_MIN_MS, LOCAL_HITSTOP_MAX_MS)
    var now := Time.get_ticks_msec()
    if not _hitstop_active:
        _resume_speed_scale = _animation_player.speed_scale
        if is_zero_approx(_resume_speed_scale):
            _resume_speed_scale = 1.0
    _hitstop_player = weakref(player)
    _hitstop_until_ms = maxi(_hitstop_until_ms, now + bounded_ms)
    _hitstop_active = true
    _animation_player.speed_scale = 0.0
    player.set_meta("combat_hitstop_local_active", true)
    player.set_meta("combat_hitstop_until_ms", _hitstop_until_ms)
    player.set_meta("combat_hitstop_local_duration_ms", bounded_ms)
    return true

func _clear_hitstop(restored: bool) -> void:
    if not restored and _animation_player != null and is_instance_valid(_animation_player) and _hitstop_active:
        _animation_player.speed_scale = _resume_speed_scale
    _hitstop_player = null
    _hitstop_until_ms = 0
    _resume_speed_scale = 1.0
    _hitstop_active = false
