extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/sources/ixelles/stassart_131_identity_cue.json"
const EXPECTED_BUILDING_ID := "https://databrussels.be/id/building/1633062"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_STASSART131_IDENTITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    if not FileAccess.file_exists(SOURCE_PATH):
        _fail("provenance contract missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if not parsed is Dictionary:
        _fail("provenance contract invalid")
        return
    var source := parsed as Dictionary
    if str(source.get("source_building_id", "")) != EXPECTED_BUILDING_ID:
        _fail("source building id drifted")
        return
    if bool(source.get("runtime_approved", true)) or bool(source.get("promote_runtime", true)):
        _fail("cue must remain locally provisional")
        return
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing")
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=ixelles"]))
    for _frame: int in range(12):
        await process_frame
    var slice := main.get_node_or_null("IxellesDirectMicroSlice")
    if slice == null or not bool(slice.get("runtime_loaded")):
        _fail("Ixelles runtime unavailable")
        return
    if int(slice.get("building_count")) != 260 or int(slice.get("skipped_unapproved_height_buildings")) != 460:
        _fail("no-invention building invariants drifted")
        return
    if not bool(slice.get("stassart_131_street_facades_built")):
        _fail("Stassart 131 street-facing façade cue missing")
        return
    if int(slice.get("stassart_131_selected_edge_count")) != 2:
        _fail("expected exactly two distinct street-facing edges")
        return
    var cue := slice.get_node_or_null("Stassart131StreetFacingLightFacades")
    if cue == null:
        _fail("renderer overlay node missing")
        return
    if str(cue.get_meta("source_building_id", "")) != EXPECTED_BUILDING_ID:
        _fail("overlay provenance metadata drifted")
        return
    print("IXELLES_STASSART131_IDENTITY_OK: building=%s edges=2 buildings=260 skipped=460" % EXPECTED_BUILDING_ID)
    quit(0)
