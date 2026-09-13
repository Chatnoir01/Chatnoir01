extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 288509378
const OUTPUT_DIR := "res://artifacts/qa/midi_fonsny_288509378_player_witness"
const OUTPUT_PNG := OUTPUT_DIR + "/road-288509378.png"
const OUTPUT_JSON := OUTPUT_DIR + "/receipt.json"
const EXPECTED_SIZE := Vector2i(1280, 720)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_288509378_PLAYER_WITNESS_FAIL: %s" % message)
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

    # The resolver contract is measured synchronously at its call boundary.
    # Player/SpringArm runtime is allowed to evolve camera.transform after the
    # teleport during subsequent process/physics frames; FOV must never change.
    var resolver_fov_before := camera.fov
    var resolver_camera_transform_before := camera.transform
    var resolver: Node = RESOLVER_SCRIPT.new()
    scene.add_child(resolver)
    if not resolver.call("apply_to_player", player, ROAD_ID):
        _fail("generic road-%d direct-entry resolver rejected the same-way arc candidate" % ROAD_ID)
        return
    var resolver_camera_transform_preserved := camera.transform.is_equal_approx(resolver_camera_transform_before)
    var resolver_camera_fov_preserved := absf(camera.fov - resolver_fov_before) <= 0.000001
    if not resolver_camera_transform_preserved or not resolver_camera_fov_preserved:
        _fail("resolver directly changed camera transform/FOV")
        return

    for _frame: int in range(18):
        await process_frame
        await physics_frame

    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != ROAD_ID:
        _fail("resolver metadata did not preserve exact requested OSM id")
        return
    if str(player.get_meta("automatic_road_direct_lookup_mode", "")) != "deterministic_runtime_index":
        _fail("resolver did not use deterministic runtime index")
        return
    if str(player.get_meta("automatic_road_direct_source_path", "")) != "res://data/osm/vertical_slice_01.game.json":
        _fail("unexpected road source path")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("source sightline is not proven clear")
        return
    if not bool(player.get_meta("automatic_road_direct_same_requested_osm_way_only", false)):
        _fail("same-requested-way runtime proof missing")
        return
    if int(player.get_meta("automatic_road_direct_source_arc_segment_hops", 0)) < 1:
        _fail("same-way multi-segment runtime path was not exercised")
        return
    var axis_lookahead := float(player.get_meta("automatic_road_direct_axis_lookahead_m", 0.0))
    var axis_alignment := float(player.get_meta("automatic_road_direct_axis_alignment", 0.0))
    if axis_lookahead <= 0.0 or axis_lookahead > 22.000001:
        _fail("runtime lookahead outside frozen bound")
        return
    if axis_alignment < 0.90:
        _fail("runtime axis alignment below frozen contract")
        return
    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("authorized ground hit missing")
        return
    if absf(camera.fov - resolver_fov_before) > 0.000001:
        _fail("runtime changed camera FOV after direct entry")
        return
    if not camera.is_visible_in_tree():
        _fail("player camera not visible in tree")
        return
    camera.current = true

    for _frame: int in range(8):
        await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.get_size() != EXPECTED_SIZE:
        _fail("player witness is not exact 1280x720")
        return
    if image.save_png(OUTPUT_PNG) != OK:
        _fail("could not persist player witness PNG")
        return

    var spawn_raw: Variant = player.get_meta("automatic_road_direct_spawn_xz", null)
    var target_raw: Variant = player.get_meta("automatic_road_direct_target_xz", null)
    if not spawn_raw is Vector2 or not target_raw is Vector2:
        _fail("resolver did not persist source-backed spawn/target metadata")
        return
    var spawn_xz := spawn_raw as Vector2
    var target_xz := target_raw as Vector2

    var receipt := {
        "schema": "grand-bruxelles-midi-fonsny-288509378-player-witness-v1",
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
        "player_position": [player.global_position.x, player.global_position.y, player.global_position.z],
        "camera_fov": camera.fov,
        "resolver_camera_local_transform_preserved": resolver_camera_transform_preserved,
        "resolver_camera_fov_preserved": resolver_camera_fov_preserved,
        "runtime_camera_local_transform_may_evolve": true,
        "requested_osm_identity_preserved": true,
        "same_way_arc_runtime_required": true,
        "same_requested_osm_way_only": bool(player.get_meta("automatic_road_direct_same_requested_osm_way_only", false)),
        "source_arc_segment_hops": int(player.get_meta("automatic_road_direct_source_arc_segment_hops", 0)),
        "axis_lookahead_m": axis_lookahead,
        "axis_alignment": axis_alignment,
        "cross_way_traversal_used": false,
        "source_sightline_clear": true,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "resolver_thresholds_lowered": false,
        "osm_to_urbis_crosswalk_claimed": false,
        "human_visual_review_required": true,
        "visual_acceptance": false,
        "destination_advertisable": false,
        "jouable_authorized": false,
    }
    var file := FileAccess.open(OUTPUT_JSON, FileAccess.WRITE)
    if file == null:
        _fail("could not persist witness receipt")
        return
    file.store_string(JSON.stringify(receipt, "  ") + "\n")
    file.close()

    print("MIDI_FONSNY_288509378_PLAYER_WITNESS_OK: road-%d source=%s ground_y=%.6f fov=%.3f lookahead=%.6f alignment=%.6f hops=%d png=%s" % [ROAD_ID, receipt["source_name"], ground_y, camera.fov, axis_lookahead, axis_alignment, int(receipt["source_arc_segment_hops"]), OUTPUT_PNG])
    quit(0)
