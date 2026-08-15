extends SceneTree

const AUDIO_PATH := "res://game/scripts/brussels_public_space_ambience.gd"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_PUBLIC_SPACE_AUDIO_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not ResourceLoader.exists(AUDIO_PATH):
        _fail("shared public-space ambience runtime is missing")
        return
    var script: Script = load(AUDIO_PATH)
    var ambience: Node = script.new()
    root.add_child(ambience)
    await process_frame

    if str(ambience.get("profile_id")) != "brussels_public_space_authored_v1":
        _fail("profile identity drifted")
        return
    if not bool(ambience.get("authored_audio")):
        _fail("authored-audio provenance flag missing")
        return
    if bool(ambience.get("claims_official_stib_signal")):
        _fail("runtime must not claim an official STIB signal or recording")
        return
    if int(ambience.get("sample_rate")) != 22050:
        _fail("sample-rate contract drifted")
        return
    if float(ambience.get("loop_seconds")) < 10.0:
        _fail("loop is too short for a 30-second ambience witness")
        return

    var stream: AudioStreamWAV = ambience.call("build_stream")
    if stream == null or stream.data.is_empty():
        _fail("runtime did not synthesize playable PCM")
        return
    if not stream.stereo or stream.mix_rate != 22050:
        _fail("runtime stream format drifted")
        return

    var metrics: Dictionary = ambience.call("measure_pcm", stream.data)
    if float(metrics.get("rms", 0.0)) < 0.025:
        _fail("ambience is effectively inaudible")
        return
    if float(metrics.get("rms", 1.0)) > 0.24:
        _fail("ambience is too loud for a background layer")
        return
    if float(metrics.get("peak", 1.0)) > 0.96:
        _fail("ambience risks clipping")
        return
    if float(metrics.get("active_ratio", 0.0)) < 0.80:
        _fail("ambience is too sparse to support 30-second immersion")
        return

    print("BRUSSELS_PUBLIC_SPACE_AUDIO_OK rms=%.6f peak=%.6f active_ratio=%.6f" % [metrics.rms, metrics.peak, metrics.active_ratio])
    quit(0)
