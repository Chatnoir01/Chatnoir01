extends Node

# Asset-independent combat audio feedback. The project currently ships no
# combat audio files, so short deterministic PCM one-shots provide readable
# switch/fire/reload/impact cues without adding an external licensing burden.

const SIGNATURE := "combat_audio_feedback_v1"
const MIX_RATE := 22050
const PLAYER_POOL_SIZE := 5

var _players: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _last_player_id := 0
var _last_switch_serial := -1
var _last_weapon_state: StringName = &""
var _last_shot_count := -1
var _last_reload := false
var _last_melee_attack_count := -1
var _last_impact_count := -1

func _ready() -> void:
    process_priority = 180
    _build_streams()
    for index: int in range(PLAYER_POOL_SIZE):
        var player := AudioStreamPlayer.new()
        player.name = "CombatAudioVoice_%d" % index
        player.bus = &"Master"
        add_child(player)
        _players.append(player)
    set_meta("combat_audio_signature", SIGNATURE)
    set_meta("combat_audio_stream_count", _streams.size())
    set_process(true)

func _process(_delta: float) -> void:
    var player := _current_player()
    if player == null:
        return
    if _last_player_id != player.get_instance_id():
        _bind_player(player)

    var switch_serial := int(player.get_meta("combat_weapon_switch_serial", 0))
    var weapon_state := StringName(player.get_meta("combat_weapon_state", &"stowed"))
    if switch_serial != _last_switch_serial or weapon_state != _last_weapon_state:
        if weapon_state == &"holstering":
            _play(&"holster", -9.0, 0.98)
        elif weapon_state == &"equipping":
            _play(&"equip", -8.0, 1.03)
        _last_switch_serial = switch_serial
        _last_weapon_state = weapon_state

    var shot_count := int(player.get_meta("combat_weapon_shot_count", 0))
    if shot_count != _last_shot_count:
        if shot_count > _last_shot_count and _last_shot_count >= 0:
            var weapon_id := StringName(player.get_meta("combat_weapon_id", &""))
            if weapon_id == &"crossbow":
                _play(&"crossbow", -5.5, 1.0)
            elif weapon_id == &"bx9":
                _play(&"gun_light", -6.5, 1.04)
            elif weapon_id == &"cbr4":
                _play(&"gun_heavy", -6.0, 1.0)
            elif weapon_id == &"sct8":
                _play(&"gun_heavy", -5.0, 0.92)
            else:
                _play(&"gun_light", -7.0, 1.0)
        _last_shot_count = shot_count

    var reload := bool(player.get_meta("combat_weapon_reloading", false))
    if reload and not _last_reload:
        _play(&"reload", -9.0, 1.0)
    _last_reload = reload

    var melee_attack_count := int(player.get_meta("combat_attack_count", 0))
    if melee_attack_count != _last_melee_attack_count:
        if melee_attack_count > _last_melee_attack_count and _last_melee_attack_count >= 0:
            _play(&"melee_swing", -10.0, 1.0)
        _last_melee_attack_count = melee_attack_count

    var impact_runtime := get_node_or_null("/root/CombatSurfaceImpactRuntime")
    if impact_runtime != null:
        var impact_count := int(impact_runtime.get_meta("combat_impact_count", 0))
        if impact_count != _last_impact_count:
            if impact_count > _last_impact_count and _last_impact_count >= 0:
                var surface := StringName(impact_runtime.get_meta("combat_last_impact_surface", &"wall"))
                match surface:
                    &"metal": _play(&"impact_metal", -8.0, 1.02)
                    &"wood": _play(&"impact_wood", -9.0, 0.98)
                    &"body": _play(&"impact_body", -10.0, 0.94)
                    _: _play(&"impact_stone", -10.0, 1.0)
            _last_impact_count = impact_count

func _bind_player(player: CharacterBody3D) -> void:
    _last_player_id = player.get_instance_id()
    _last_switch_serial = int(player.get_meta("combat_weapon_switch_serial", 0))
    _last_weapon_state = StringName(player.get_meta("combat_weapon_state", &"stowed"))
    _last_shot_count = int(player.get_meta("combat_weapon_shot_count", 0))
    _last_reload = bool(player.get_meta("combat_weapon_reloading", false))
    _last_melee_attack_count = int(player.get_meta("combat_attack_count", 0))
    var impact_runtime := get_node_or_null("/root/CombatSurfaceImpactRuntime")
    _last_impact_count = int(impact_runtime.get_meta("combat_impact_count", 0)) if impact_runtime != null else 0
    player.set_meta("combat_audio_feedback_signature", SIGNATURE)

func _play(stream_id: StringName, volume_db: float, pitch: float) -> void:
    var stream := _streams.get(stream_id) as AudioStreamWAV
    if stream == null or _players.is_empty():
        return
    var voice: AudioStreamPlayer = _players[0]
    for candidate: AudioStreamPlayer in _players:
        if not candidate.playing:
            voice = candidate
            break
    voice.stop()
    voice.stream = stream
    voice.volume_db = volume_db
    voice.pitch_scale = clampf(pitch, 0.72, 1.35)
    voice.play()
    set_meta("combat_audio_last_event", stream_id)
    set_meta("combat_audio_event_count", int(get_meta("combat_audio_event_count", 0)) + 1)

func _build_streams() -> void:
    _streams[&"holster"] = _synth_click(95, 128.0, 0.38)
    _streams[&"equip"] = _synth_click(115, 176.0, 0.44)
    _streams[&"reload"] = _synth_click(155, 220.0, 0.36)
    _streams[&"gun_light"] = _synth_burst(115, 86.0, 0.84, 0xA91)
    _streams[&"gun_heavy"] = _synth_burst(150, 64.0, 0.94, 0xC43)
    _streams[&"crossbow"] = _synth_twang(175, 185.0, 0.62)
    _streams[&"melee_swing"] = _synth_sweep(135, 330.0, 115.0, 0.22)
    _streams[&"impact_metal"] = _synth_twang(115, 740.0, 0.30)
    _streams[&"impact_wood"] = _synth_burst(85, 118.0, 0.28, 0x551)
    _streams[&"impact_body"] = _synth_burst(82, 72.0, 0.24, 0x71B)
    _streams[&"impact_stone"] = _synth_burst(92, 96.0, 0.25, 0x31D)

func _synth_click(duration_ms: int, frequency_hz: float, gain: float) -> AudioStreamWAV:
    return _pcm_stream(duration_ms, func(t: float, progress: float, _index: int) -> float:
        var env := pow(maxf(0.0, 1.0 - progress), 7.0)
        return sin(TAU * frequency_hz * t) * env * gain
    )

func _synth_twang(duration_ms: int, frequency_hz: float, gain: float) -> AudioStreamWAV:
    return _pcm_stream(duration_ms, func(t: float, progress: float, _index: int) -> float:
        var env := pow(maxf(0.0, 1.0 - progress), 3.2)
        var fundamental := sin(TAU * frequency_hz * t)
        var harmonic := sin(TAU * frequency_hz * 2.03 * t) * 0.36
        return (fundamental + harmonic) * env * gain
    )

func _synth_sweep(duration_ms: int, start_hz: float, end_hz: float, gain: float) -> AudioStreamWAV:
    return _pcm_stream(duration_ms, func(t: float, progress: float, _index: int) -> float:
        var frequency := lerpf(start_hz, end_hz, progress)
        var env := sin(PI * clampf(progress, 0.0, 1.0))
        return sin(TAU * frequency * t) * env * gain
    )

func _synth_burst(duration_ms: int, frequency_hz: float, gain: float, seed: int) -> AudioStreamWAV:
    return _pcm_stream(duration_ms, func(t: float, progress: float, index: int) -> float:
        var env := pow(maxf(0.0, 1.0 - progress), 4.5)
        var tone := sin(TAU * frequency_hz * t) * 0.72
        var x := int(seed) ^ (index * 1103515245 + 12345)
        x = x ^ (x << 13)
        x = x ^ (x >> 17)
        x = x ^ (x << 5)
        var noise := (float(x & 0xFFFF) / 32767.5) - 1.0
        return (tone + noise * 0.42) * env * gain
    )

func _pcm_stream(duration_ms: int, sampler: Callable) -> AudioStreamWAV:
    var sample_count := maxi(1, int(round(float(MIX_RATE) * float(duration_ms) / 1000.0)))
    var bytes := PackedByteArray()
    bytes.resize(sample_count * 2)
    for index: int in range(sample_count):
        var t := float(index) / float(MIX_RATE)
        var progress := float(index) / maxf(float(sample_count - 1), 1.0)
        var sample := clampf(float(sampler.call(t, progress, index)), -0.98, 0.98)
        var pcm := int(round(sample * 32767.0))
        if pcm < 0:
            pcm += 65536
        bytes[index * 2] = pcm & 0xFF
        bytes[index * 2 + 1] = (pcm >> 8) & 0xFF
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = MIX_RATE
    stream.stereo = false
    stream.data = bytes
    return stream

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D
