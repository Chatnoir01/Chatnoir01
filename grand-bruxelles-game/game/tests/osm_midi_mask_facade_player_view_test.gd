extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 35903015
const OUTPUT_DIR := "res://artifacts/qa/osm_midi_mask_facade_player_view"
const OUTPUT_PNG := OUTPUT_DIR + "/player-view.png"
const OUTPUT_JSON := OUTPUT_DIR + "/receipt.json"
const EXPECTED_SIZE := Vector2i(1280, 720)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("OSM_MIDI_MASK_FACADE_PLAYER_VIEW_FAIL: %s" % message)
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

    var frozen_fov := camera.fov
    var frozen_local_transform := camera.transform
    var resolver: Node = RESOLVER_SCRIPT.new()
    scene.add_child(resolver)
    if not resolver.call("apply_to_player", player, ROAD_ID):
        _fail("generic road-%d direct-entry resolver rejected source-backed Midi witness" % ROAD_ID)
        return
    var resolver_preserved_fov := absf(camera.fov - frozen_fov) <= 0.000001
    var resolver_preserved_camera_transform := camera.transform.is_equal_approx(frozen_local_transform)
    if not resolver_preserved_fov or not resolver_preserved_camera_transform:
        _fail("resolver mutated player camera/FOV at call boundary")
        return

    for _frame: int in range(18):
        await process_frame
        await physics_frame

    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != ROAD_ID:
        _fail("resolver metadata did not preserve exact road identity")
        return
    if str(player.get_meta("automatic_road_direct_lookup_mode", "")) != "deterministic_runtime_index":
        _fail("resolver did not use deterministic runtime index")
        return
    if str(player.get_meta("automatic_road_direct_source_path", "")) != "res://data/osm/vertical_slice_01.game.json":
        _fail("unexpected road source path")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("source-backed sightline is not clear")
        return
    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("authorized ground hit missing")
        return
    if absf(camera.fov - frozen_fov) > 0.000001:
        _fail("runtime changed player camera FOV after direct entry")
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
        _fail("could not persist player-view PNG")
        return

    var spawn_xz: Vector2 = player.get_meta("automatic_road_direct_spawn_xz") as Vector2
    var target_xz: Vector2 = player.get_meta("automatic_road_direct_target_xz") as Vector2
    var receipt := {
        "schema": "grand-bruxelles-osm-midi-mask-facade-player-view-v1",
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
        "resolver_camera_local_transform_preserved": resolver_preserved_camera_transform,
        "resolver_camera_fov_preserved": resolver_preserved_fov,
        "runtime_camera_local_transform_may_evolve": true,
        "source_sightline_clear": true,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_contract_changed": false,
        "threshold_changed": false,
        "osm_to_urbis_crosswalk_claimed": false,
        "human_full_frame_review_required": true,
        "visual_acceptance": false,
        "jouable_authorized": false
    }
    var file := FileAccess.open(OUTPUT_JSON, FileAccess.WRITE)
    if file == null:
        _fail("could not persist player-view receipt")
        return
    file.store_string(JSON.stringify(receipt, "  ") + "\n")
    file.close()

    print("OSM_MIDI_MASK_FACADE_PLAYER_VIEW_OK: road-%d source=%s ground_y=%.6f fov=%.3f png=%s" % [ROAD_ID, receipt["source_name"], ground_y, camera.fov, OUTPUT_PNG])
    quit(0)
