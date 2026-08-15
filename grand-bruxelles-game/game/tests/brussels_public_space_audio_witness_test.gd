extends SceneTree

const AUDIO_PATH := "res://game/scripts/brussels_public_space_ambience.gd"
const OUTPUT_DIR := "res://artifacts/audio"
const OUTPUT_WAV := OUTPUT_DIR + "/brussels_public_space_30s.wav"
const OUTPUT_JSON := OUTPUT_DIR + "/brussels_public_space_30s.json"
const WITNESS_SECONDS := 30

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_PUBLIC_SPACE_AUDIO_WITNESS_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var script: Script = load(AUDIO_PATH)
    if script == null:
        _fail("runtime script could not be loaded")
        return
    var ambience: Node = script.new()
    root.add_child(ambience)
    await process_frame

    var stream: AudioStreamWAV = ambience.call("build_stream")
    if stream == null or stream.data.is_empty():
        _fail("runtime loop is empty")
        return
    var frame_bytes := 4
    var witness_frames := int(stream.mix_rate * WITNESS_SECONDS)
    var witness := PackedByteArray()
    witness.resize(witness_frames * frame_bytes)
    var loop_frames := int(stream.data.size() / frame_bytes)
    if loop_frames <= 0:
        _fail("runtime loop has no stereo frames")
        return
    for frame in range(witness_frames):
        var src := (frame % loop_frames) * frame_bytes
        var dst := frame * frame_bytes
        witness[dst] = stream.data[src]
        witness[dst + 1] = stream.data[src + 1]
        witness[dst + 2] = stream.data[src + 2]
        witness[dst + 3] = stream.data[src + 3]

    if not _write_pcm16_stereo_wav(OUTPUT_WAV, witness, stream.mix_rate):
        _fail("could not write deterministic WAV witness")
        return
    var metrics: Dictionary = ambience.call("measure_pcm", witness)
    var digest := _sha256_hex(witness)
    var report := {
        "profile_id": str(ambience.get("profile_id")),
        "witness_seconds": WITNESS_SECONDS,
        "sample_rate": stream.mix_rate,
        "channels": 2,
        "pcm_format": "signed-16-le",
        "runtime_loop_seconds": float(ambience.get("loop_seconds")),
        "same_runtime_pcm": true,
        "third_party_audio": false,
        "claims_official_stib_signal": false,
        "rms": float(metrics.get("rms", 0.0)),
        "peak": float(metrics.get("peak", 0.0)),
        "active_ratio": float(metrics.get("active_ratio", 0.0)),
        "pcm_sha256": digest,
    }
    var json_file := FileAccess.open(OUTPUT_JSON, FileAccess.WRITE)
    if json_file == null:
        _fail("could not write witness manifest")
        return
    json_file.store_string(JSON.stringify(report, "  "))
    json_file.close()

    print("BRUSSELS_PUBLIC_SPACE_AUDIO_WITNESS_OK seconds=%d sample_rate=%d rms=%.6f peak=%.6f active_ratio=%.6f pcm_sha256=%s same_runtime_pcm=true" % [
        WITNESS_SECONDS,
        stream.mix_rate,
        float(report["rms"]),
        float(report["peak"]),
        float(report["active_ratio"]),
        digest,
    ])
    quit(0)

func _write_pcm16_stereo_wav(path: String, pcm: PackedByteArray, rate: int) -> bool:
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return false
    file.big_endian = false
    var data_size := pcm.size()
    file.store_buffer("RIFF".to_ascii_buffer())
    file.store_32(36 + data_size)
    file.store_buffer("WAVE".to_ascii_buffer())
    file.store_buffer("fmt ".to_ascii_buffer())
    file.store_32(16)
    file.store_16(1)
    file.store_16(2)
    file.store_32(rate)
    file.store_32(rate * 4)
    file.store_16(4)
    file.store_16(16)
    file.store_buffer("data".to_ascii_buffer())
    file.store_32(data_size)
    file.store_buffer(pcm)
    file.close()
    return true

func _sha256_hex(data: PackedByteArray) -> String:
    var context := HashingContext.new()
    context.start(HashingContext.HASH_SHA256)
    context.update(data)
    return context.finish().hex_encode()
