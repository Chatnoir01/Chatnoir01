extends SceneTree

const SCRIPT := preload("res://game/scripts/grand_place_roi_espagne_facade_rhythm_runtime.gd")
const CONTRACT_PATH := "res://data/qa/grand_place_roi_espagne_facade_rhythm.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ROI_ESPAGNE_FACADE_RHYTHM_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(CONTRACT_PATH):
        _fail("source contract missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("source contract invalid")
        return
    var contract := parsed as Dictionary
    if str(contract.get("schema", "")) != "grand-bruxelles-roi-espagne-facade-rhythm-v1":
        _fail("schema drifted")
        return
    if str(contract.get("building_id", "")) != "1645616":
        _fail("official building identity drifted")
        return
    if str(contract.get("official_front_wall_face_id", "")) != "10878705":
        _fail("official front wall identity drifted")
        return
    if int(contract.get("heritage_bay_count", 0)) != 7:
        _fail("seven-bay heritage identity missing")
        return
    if int(contract.get("heritage_register_count", 0)) != 3:
        _fail("three-register heritage identity missing")
        return
    if not bool(contract.get("central_bay_wider", false)) or not bool(contract.get("central_bay_projecting", false)):
        _fail("central-axis heritage semantics missing")
        return
    if not bool(contract.get("roof_dome_documented", false)):
        _fail("documented roof dome missing")
        return
    if bool(contract.get("exact_dimensions_are_source", true)):
        _fail("visualization dimensions must not claim survey provenance")
        return

    var runtime := SCRIPT.new()
    runtime.name = "RoiEspagneFacadeRhythmTest"
    root.add_child(runtime)
    await process_frame
    await process_frame

    if runtime.diagnostic_register_count() != 3:
        _fail("expected three facade registers")
        return
    if runtime.diagnostic_pilaster_count() != 24:
        _fail("expected 8 pilaster delimiters per register")
        return
    if runtime.diagnostic_band_count() != 2:
        _fail("expected two horizontal register separators")
        return
    if runtime.diagnostic_central_projection_count() != 1:
        _fail("expected one central projecting bay cue")
        return
    if runtime.diagnostic_dome_count() != 1:
        _fail("expected one axial dome cue")
        return
    if bool(runtime.get_meta("runtime_approved", true)) or bool(runtime.get_meta("realism_complete", true)):
        _fail("candidate must remain explicitly provisional")
        return
    if str(runtime.get_meta("source_building_id", "")) != "1645616":
        _fail("runtime source building metadata drifted")
        return
    if str(runtime.get_meta("source_wall_face_id", "")) != "10878705":
        _fail("runtime source wall metadata drifted")
        return

    print("ROI_ESPAGNE_FACADE_RHYTHM_OK: bays=7 registers=3 pilasters=24 bands=2 central_projection=1 dome=1 runtime_approved=false")
    runtime.queue_free()
    quit(0)
