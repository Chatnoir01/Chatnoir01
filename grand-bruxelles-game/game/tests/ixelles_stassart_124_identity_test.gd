extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/sources/ixelles/stassart_124_identity_cue.json"
const EXPECTED_BUILDING_ID := "https://databrussels.be/id/building/1737877"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_STASSART124_IDENTITY_FAIL: %s" % message)
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
        _fail("identity cue must remain locally provisional")
        return
    var address: Variant = source.get("official_address", {})
    if not address is Dictionary or str(address.get("police_number", "")) != "124" or str(address.get("street_fr", "")) != "Rue de Stassart":
        _fail("official address linkage drifted")
        return
    var runtime_interpretation: Variant = source.get("runtime_interpretation", {})
    if not runtime_interpretation is Dictionary or bool(runtime_interpretation.get("vertical_method_is_measured", true)):
        _fail("presentation-only vertical method must not be presented as measured")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing")
        return
    player.call("_apply_direct_spawn_from_user_args", PackedStringArray(["spawn=ixelles"]))
    for _frame: int in range(10):
        await process_frame

    var slice := main.get_node_or_null("IxellesDirectMicroSlice")
    if slice == null or not bool(slice.get("runtime_loaded")):
        _fail("shipped Ixelles runtime unavailable")
        return
    if int(slice.get("building_count")) != 260 or int(slice.get("skipped_unapproved_height_buildings")) != 460:
        _fail("building/no-invention invariants drifted")
        return
    if int(slice.get("terrain_sample_count")) != 63001 or int(slice.get("terrain_triangle_count")) != 125000:
        _fail("terrain invariants drifted")
        return
    if int(slice.get("street_surface_count")) != 309 or int(slice.get("street_segment_count")) != 277:
        _fail("street invariants drifted")
        return
    if not bool(slice.get("stassart_124_blue_stone_cue_built")):
        _fail("source-backed blue-stone cue was not built")
        return
    var cue := slice.get_node_or_null("Stassart124BlueStoneGroundFloor") as MeshInstance3D
    if cue == null or cue.mesh == null:
        _fail("blue-stone cue mesh missing")
        return
    if str(cue.get_meta("source_building_id", "")) != EXPECTED_BUILDING_ID:
        _fail("cue building provenance drifted")
        return
    if str(cue.get_meta("source_address", "")) != "Rue de Stassart 124":
        _fail("cue address provenance drifted")
        return
    if str(cue.get_meta("vertical_method", "")) != "semantic_height_divided_by_4_source_described_levels_presentation_only":
        _fail("cue vertical interpretation drifted")
        return

    print("IXELLES_STASSART124_IDENTITY_OK: building=%s address=Rue_de_Stassart_124 terrain_samples=63001 terrain_triangles=125000 streets=309 axes=277 buildings=260 skipped=460 runtime_approved=false promote_runtime=false" % EXPECTED_BUILDING_ID)
    quit(0)
