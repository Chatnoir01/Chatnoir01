extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/sources/ixelles/stephanie_8_identity_cue.json"
const EXPECTED_BUILDING_ID := "https://databrussels.be/id/building/1737880"
const EXPECTED_AXIS_ID := "https://databrussels.be/id/streetaxe/71306:2"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("IXELLES_STEPHANIE8_IDENTITY_FAIL: %s" % message)
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
    if absf(float(source.get("strong_source_semantic_height_m", 0.0)) - 19.884) > 0.001:
        _fail("strong-source height evidence drifted")
        return
    if bool(source.get("runtime_approved", true)) or bool(source.get("promote_runtime", true)):
        _fail("local cue must not claim global runtime approval")
        return
    var frontage: Variant = source.get("frontage_selection", {})
    if not frontage is Dictionary or str(frontage.get("source_axis_id", "")) != EXPECTED_AXIS_ID or bool(frontage.get("whole_building_recolor", true)):
        _fail("source-bounded frontage selection drifted")
        return
    var interpretation: Variant = source.get("runtime_interpretation", {})
    if not interpretation is Dictionary:
        _fail("runtime interpretation missing")
        return
    if bool(interpretation.get("geometry_changes", true)) or bool(interpretation.get("collision_changes", true)) or bool(interpretation.get("camera_changes", true)) or bool(interpretation.get("terrain_changes", true)) or bool(interpretation.get("street_changes", true)):
        _fail("identity cue must remain renderer-only")
        return
    if int(interpretation.get("unresolved_buildings_added", -1)) != 0:
        _fail("unresolved buildings must remain absent")
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
    if not bool(slice.get("stephanie_8_white_stone_cue_built")):
        _fail("source-backed Place Stephanie 8 cue was not built")
        return
    var cue := slice.get_node_or_null("Stephanie8WhiteStoneFrontage") as MeshInstance3D
    if cue == null or cue.mesh == null:
        _fail("Place Stephanie 8 frontage mesh missing")
        return
    if str(cue.get_meta("source_building_id", "")) != EXPECTED_BUILDING_ID:
        _fail("cue building provenance drifted")
        return
    if str(cue.get_meta("source_axis_id", "")) != EXPECTED_AXIS_ID:
        _fail("cue axis provenance drifted")
        return
    var edge_index := int(cue.get_meta("selected_edge_index", -1))
    var axis_distance := float(cue.get_meta("frontage_axis_distance_m", INF))
    var edge_length := float(cue.get_meta("frontage_edge_length_m", 0.0))
    if edge_index < 0 or not is_finite(axis_distance) or axis_distance > 30.0:
        _fail("selected frontage is not plausibly attached to Place Stephanie: edge=%d distance=%.3f" % [edge_index, axis_distance])
        return
    if edge_length < 2.0:
        _fail("selected frontage edge is implausibly short: %.3f" % edge_length)
        return
    print("IXELLES_STEPHANIE8_IDENTITY_OK: building=%s axis=%s edge=%d axis_distance=%.3f edge_length=%.3f terrain_samples=63001 terrain_triangles=125000 streets=309 axes=277 buildings=260 skipped=460 runtime_approved=false promote_runtime=false" % [EXPECTED_BUILDING_ID, EXPECTED_AXIS_ID, edge_index, axis_distance, edge_length])
    quit(0)
