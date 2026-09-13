extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 288509378
const OUTPUT_DIR := "res://artifacts/qa/midi_fonsny_288509378_corridor_masked_visual"
const OUTPUT_PNG := OUTPUT_DIR + "/road-288509378-corridor-masked.png"
const OUTPUT_JSON := OUTPUT_DIR + "/receipt.json"
const EXPECTED_SIZE := Vector2i(1280, 720)
const MASK_PATH := "VisualUpgrade"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_288509378_CORRIDOR_MASKED_VISUAL_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))

    var viewport := SubViewport.new()
    viewport.size = EXPECTED_SIZE
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var scene: Node = MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    for _frame: int in range(48):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("authoritative player unavailable")
        return
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null:
        _fail("authoritative player camera unavailable")
        return

    var resolver_fov_before := camera.fov
    var resolver_camera_transform_before := camera.transform
    var resolver: Node = RESOLVER_SCRIPT.new()
    scene.add_child(resolver)
    if not resolver.call("apply_to_player", player, ROAD_ID):
        _fail("generic road-%d direct-entry resolver rejected candidate" % ROAD_ID)
        return
    if not camera.transform.is_equal_approx(resolver_camera_transform_before):
        _fail("resolver directly changed camera transform")
        return
    if absf(camera.fov - resolver_fov_before) > 0.000001:
        _fail("resolver directly changed camera FOV")
        return

    for _frame: int in range(18):
        await process_frame
        await physics_frame

    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != ROAD_ID:
        _fail("exact requested OSM identity not preserved")
        return
    if str(player.get_meta("automatic_road_direct_lookup_mode", "")) != "deterministic_runtime_index":
        _fail("deterministic runtime-index lookup missing")
        return
    if str(player.get_meta("automatic_road_direct_source_path", "")) != "res://data/osm/vertical_slice_01.game.json":
        _fail("unexpected source path")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("source sightline not clear")
        return
    if not bool(player.get_meta("automatic_road_direct_same_requested_osm_way_only", false)):
        _fail("same-requested-way proof missing")
        return
    if int(player.get_meta("automatic_road_direct_source_arc_segment_hops", 0)) < 1:
        _fail("same-way multi-segment path not exercised")
        return

    var axis_lookahead := float(player.get_meta("automatic_road_direct_axis_lookahead_m", 0.0))
    var axis_alignment := float(player.get_meta("automatic_road_direct_axis_alignment", 0.0))
    if axis_lookahead <= 0.0 or axis_lookahead > 22.000001:
        _fail("lookahead outside frozen bound")
        return
    if axis_alignment < 0.90:
        _fail("axis alignment below frozen contract")
        return
    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("authorized ground hit missing")
        return

    # QA-only masking isolates corridor pixels from the known Character-owned
    # arms-out animation defect. It does not alter Player physics, camera,
    # resolver state, source geometry, collision, exports, or canonical runtime.
    # The mask must be restored after capture before this probe can call itself
    # ephemeral; otherwise a future in-process consumer could inherit hidden state.
    var visual_upgrade := player.get_node_or_null(MASK_PATH) as Node3D
    if visual_upgrade == null:
        _fail("expected Player/%s visual node unavailable" % MASK_PATH)
        return
    var visual_was_visible := visual_upgrade.visible
    visual_upgrade.visible = false
    if visual_upgrade.visible:
        _fail("QA visual mask did not apply")
        return

    if absf(camera.fov - resolver_fov_before) > 0.000001:
        _fail("QA mask changed camera FOV")
        return
    camera.current = true
    for _frame: int in range(8):
        await process_frame

    var image := viewport.get_texture().get_image()
    if image == null or image.get_size() != EXPECTED_SIZE:
        _fail("masked corridor witness is not exact 1280x720")
        return
    if image.save_png(OUTPUT_PNG) != OK:
        _fail("could not persist masked corridor PNG")
        return

    visual_upgrade.visible = visual_was_visible
    await process_frame
    if visual_upgrade.visible != visual_was_visible:
        _fail("QA visual mask did not restore original visibility")
        return
    if absf(camera.fov - resolver_fov_before) > 0.000001:
        _fail("QA mask restoration changed camera FOV")
        return

    var spawn_raw: Variant = player.get_meta("automatic_road_direct_spawn_xz", null)
    var target_raw: Variant = player.get_meta("automatic_road_direct_target_xz", null)
    if not spawn_raw is Vector2 or not target_raw is Vector2:
        _fail("source-backed spawn/target metadata missing")
        return
    var spawn_xz := spawn_raw as Vector2
    var target_xz := target_raw as Vector2

    var receipt := {
        "schema": "grand-bruxelles-midi-fonsny-288509378-corridor-masked-visual-v2",
        "road_osm_id": ROAD_ID,
        "request": "road-%d" % ROAD_ID,
        "resolution": [EXPECTED_SIZE.x, EXPECTED_SIZE.y],
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "source_name": str(player.get_meta("automatic_road_direct_source_name", "")),
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "spawn_xz": [spawn_xz.x, spawn_xz.y],
        "target_xz": [target_xz.x, target_xz.y],
        "ground_y": ground_y,
        "camera_fov": camera.fov,
        "same_requested_osm_way_only": true,
        "source_arc_segment_hops": int(player.get_meta("automatic_road_direct_source_arc_segment_hops", 0)),
        "axis_lookahead_m": axis_lookahead,
        "axis_alignment": axis_alignment,
        "source_sightline_clear": true,
        "qa_mask_applied": true,
        "qa_mask_node": "Player/%s" % MASK_PATH,
        "qa_mask_originally_visible": visual_was_visible,
        "qa_mask_restored": visual_upgrade.visible == visual_was_visible,
        "qa_mask_final_visibility": visual_upgrade.visible,
        "qa_mask_ephemeral": true,
        "character_runtime_changed": false,
        "player_physics_changed": false,
        "camera_changed": false,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "resolver_thresholds_lowered": false,
        "cross_way_traversal_used": false,
        "human_visual_review_required": true,
        "masked_frame_cannot_promote_destination": true,
        "visual_acceptance": false,
        "destination_advertisable": false,
        "jouable_authorized": false,
    }
    var file := FileAccess.open(OUTPUT_JSON, FileAccess.WRITE)
    if file == null:
        _fail("could not persist masked corridor receipt")
        return
    file.store_string(JSON.stringify(receipt, "  ") + "\n")
    file.close()

    print("MIDI_FONSNY_288509378_CORRIDOR_MASKED_VISUAL_OK: road-%d lookahead=%.6f alignment=%.6f hops=%d mask_restored=%s png=%s" % [ROAD_ID, axis_lookahead, axis_alignment, int(receipt["source_arc_segment_hops"]), str(receipt["qa_mask_restored"]), OUTPUT_PNG])
    quit(0)
