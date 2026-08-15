extends Node
class_name BrusselsPublicSpaceAmbience

## Original project-authored procedural public-space ambience.
## No third-party recording is embedded and no tone is claimed to reproduce an
## official STIB/MIVB signal, announcement, timetable, service or vehicle.

const profile_id := "brussels_public_space_authored_v1"
const authored_audio := true
const claims_official_stib_signal := false
const sample_rate := 22050
const loop_seconds := 12.0
const master_gain := 0.28

var player: AudioStreamPlayer

func _ready() -> void:
    player = AudioStreamPlayer.new()
    player.name = "BrusselsPublicSpaceAmbiencePlayer"
    player.stream = build_stream()
    player.volume_db = -7.0
    add_child(player)
    player.play()
    set_meta("profile_id", profile_id)
    set_meta("provenance", "project-authored deterministic PCM; no third-party audio")
    set_meta("semantic_claim", "generic Brussels public-space atmosphere only")

func build_stream() -> AudioStreamWAV:
    var stream := AudioStreamWAV.new()
    stream.format = AudioStreamWAV.FORMAT_16_BITS
    stream.mix_rate = sample_rate
    stream.stereo = true
    stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
    stream.loop_begin = 0
    stream.loop_end = int(round(loop_seconds * float(sample_rate)))
    stream.data = render_pcm(loop_seconds)
    return stream

func render_pcm(seconds: float) -> PackedByteArray:
    var frames := int(round(max(seconds, 0.1) * float(sample_rate)))
    var pcm := PackedByteArray()
    pcm.resize(frames * 4)
    var state_a: int = 0x13579BDF
    var state_b: int = 0x2468ACE1
    var traffic_noise := 0.0
    var crowd_noise := 0.0

    for i in range(frames):
        var t := float(i) / float(sample_rate)
        state_a = int((state_a * 1664525 + 1013904223) & 0x7fffffff)
        state_b = int((state_b * 1103515245 + 12345) & 0x7fffffff)
        var white_a := float(state_a) / 1073741824.0 - 1.0
        var white_b := float(state_b) / 1073741824.0 - 1.0
        traffic_noise = lerpf(traffic_noise, white_a, 0.0065)
        crowd_noise = lerpf(crowd_noise, white_b, 0.045)

        var slow_breath := 0.82 + 0.18 * sin(TAU * 0.073 * t + 0.8)
        var traffic := (
            0.22 * sin(TAU * 44.0 * t)
            + 0.11 * sin(TAU * 67.0 * t + 0.4)
            + 0.08 * sin(TAU * 91.0 * t + 1.1)
            + 0.24 * traffic_noise
        ) * slow_breath
        var crowd := crowd_noise * (0.18 + 0.04 * sin(TAU * 0.19 * t))
        crowd += 0.022 * sin(TAU * 238.0 * t + 0.3) * (0.6 + 0.4 * sin(TAU * 0.11 * t))

        var metal := _bell_event(t, 2.65) + 0.82 * _bell_event(t, 8.45)
        var rail := _rail_event(t, 5.10) + 0.68 * _rail_event(t, 10.15)
        var texture := 0.018 * sin(TAU * 173.0 * t + 0.7) + 0.014 * sin(TAU * 311.0 * t + 1.4)

        var center := (traffic + crowd + metal + rail + texture) * master_gain
        var side := (0.035 * sin(TAU * 0.17 * t) + 0.025 * crowd_noise) * master_gain
        var left := clampf(center + side, -0.94, 0.94)
        var right := clampf(center - side, -0.94, 0.94)
        _write_s16(pcm, i * 4, left)
        _write_s16(pcm, i * 4 + 2, right)
    return pcm

func measure_pcm(pcm: PackedByteArray) -> Dictionary:
    if pcm.size() < 4:
        return {"rms": 0.0, "peak": 0.0, "active_ratio": 0.0, "samples": 0}
    var sample_count := int(pcm.size() / 2)
    var energy := 0.0
    var peak := 0.0
    var active := 0
    for offset in range(0, pcm.size() - 1, 2):
        var raw := int(pcm[offset]) | (int(pcm[offset + 1]) << 8)
        if raw >= 32768:
            raw -= 65536
        var value := float(raw) / 32768.0
        energy += value * value
        peak = maxf(peak, absf(value))
        if absf(value) >= 0.010:
            active += 1
    return {
        "rms": sqrt(energy / float(sample_count)),
        "peak": peak,
        "active_ratio": float(active) / float(sample_count),
        "samples": sample_count,
    }

func _bell_event(t: float, start: float) -> float:
    var x := t - start
    if x < 0.0 or x > 1.35:
        return 0.0
    var envelope := exp(-3.15 * x) * minf(1.0, x * 28.0)
    return envelope * (
        0.16 * sin(TAU * 910.0 * x)
        + 0.10 * sin(TAU * 1375.0 * x + 0.2)
        + 0.06 * sin(TAU * 1830.0 * x + 0.6)
    )

func _rail_event(t: float, start: float) -> float:
    var x := t - start
    if x < 0.0 or x > 1.50:
        return 0.0
    var phase := TAU * (315.0 * x + 245.0 * x * x)
    var envelope := sin(PI * clampf(x / 1.50, 0.0, 1.0))
    return 0.085 * envelope * (sin(phase) + 0.34 * sin(phase * 1.51 + 0.4))

func _write_s16(buffer: PackedByteArray, offset: int, value: float) -> void:
    var sample := int(round(clampf(value, -1.0, 1.0) * 32767.0))
    if sample < 0:
        sample += 65536
    buffer[offset] = sample & 0xff
    buffer[offset + 1] = (sample >> 8) & 0xff
