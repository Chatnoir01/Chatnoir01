extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/bourse_metro_identity_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_METRO_IDENTITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := RUNTIME_SCRIPT.new()
    root.add_child(runtime)
    await process_frame

    if int(runtime.get("entrance_count")) != 7:
        _fail("expected seven official Bourse/Beurs entrance anchors")
        return
    if int(runtime.get("identity_count")) != 7:
        _fail("expected one identity treatment per official entrance")
        return
    if str(runtime.get("station_fr")) != "Bourse" or str(runtime.get("station_nl")) != "Beurs":
        _fail("bilingual station identity drifted")
        return
    if not bool(runtime.get("published_points_only")):
        _fail("published-point placement contract missing")
        return
    if bool(runtime.get("claims_surveyed_sign_geometry")):
        _fail("runtime must not claim surveyed sign geometry")
        return
    if bool(runtime.get("claims_timetable_or_service")):
        _fail("runtime must not invent timetable/service semantics")
        return

    var ids: Array = runtime.get("source_stop_ids") as Array
    var expected := ["0600565", "0600765", "0600365", "0600965", "0601165", "0600165", "0601265"]
    if ids != expected:
        _fail("official entrance identifiers drifted: %s" % [ids])
        return

    print("BOURSE_METRO_IDENTITY_OK: entrances=7 bilingual=Bourse/Beurs source_points_only=true")
    quit(0)
