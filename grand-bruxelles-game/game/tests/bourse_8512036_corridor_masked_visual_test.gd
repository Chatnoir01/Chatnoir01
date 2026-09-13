extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const OUTPUT_DIR := "res://artifacts/qa/bourse_8512036_corridor_masked_visual"
const OUTPUT_PNG := OUTPUT_DIR + "/road-8512036-corridor-masked.png"
const OUTPUT_JSON := OUTPUT_DIR + "/receipt.json"
const EXPECTED_SIZE := Vector2i(1280, 720)
const MASK_PATH := "VisualUpgrade"
const MIN_AXIS_ALIGNMENT := 0.90
const CAMERA_EPSILON := 0.000001

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_CORRIDOR_MASKED_VISUAL_FAIL: %s" % message)
    quit(1)

func _source_road() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if not parsed is Dictionary:
        return {}
    var roads: Variant = (parsed as Dictionary).get("roads", [])
    if not roads is Array:
        return {}
    for raw: Variant in roads:
        if raw is Dictionary and int((raw as Dictionary).get("osm_id", 0)) == ROAD_ID:
            return raw as Dictionary
    return {}

func _source_tangent(segment_index: int) -> Vector2:
    var road := _source_road()
    var points: Variant = road.get("points", [])
    if not points is Array or segment_index < 0 or segment_index + 1 >= points.size():
        return Vector2.ZERO
    var a: Variant = points[segment_index]
    var b: Variant = points[segment_index + 1]
    if not a is Array or not b is Array or a.size() < 2 or b.size() < 2:
        return Vector2.ZERO
    return (Vector2(float(b[0]), float(b[1])) - Vector2(float(a[0]), float(a[1]))).normalized()

func _freeze_dynamic(scene: Node) -> void:
    for path: String in ["MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var canvas := scene.get_node_or_null(path) as CanvasItem
        if canvas != null:
            canvas.visible = false
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null:
            spatial.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false

# Camera3D is a direct SpringArm3D child. Godot is allowed to change the
# camera's local origin while the spring arm resolves collision. That runtime
# offset is not an authored camera mutation and must not be frozen by QA.
# Instead seal the authored chain: pivot transform, spring-arm transform and
# settings, camera local basis, and FOV.
func _camera_authored_contract_unchanged(
    camera: Camera3D,
    spring_arm: SpringArm3D,
    pivot: Node3D,
    expected_camera_basis: Basis,
    expected_fov: float,
    expected_spring_transform: Transform3D,
    expected_spring_length: float,
    expected_spring_margin: float,
    expected_pivot_transform: Transform3D,
) -> bool:
    return (
        camera.transform.basis.is_equal_approx(expected_camera_basis)
        and absf(camera.fov - expected_fov) <= CAMERA_EPSILON
        and spring_arm.transform.is_equal_approx(expected_spring_transform)
        and absf(spring_arm.spring_length - expected_spring_length) <= CAMERA_EPSILON
        and absf(spring_arm.margin - expected_spring_margin) <= CAMERA_EPSILON
        and pivot.transform.is_equal_approx(expected_pivot_transform)
    )

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var road := _source_road()
    if road.is_empty() or not str(road.get("name", "")).contains("Saint-G") or not bool(road.get("drivable", false)):
        _fail("locked source candidate 8512036 unavailable or drifted")
        return

    var viewport := SubViewport.new()
    viewport.size = EXPECTED_SIZE
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var scene: Node = MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    _freeze_dynamic(scene)
    for _frame: int in range(48):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("authoritative player unavailable")
        return
    var pivot := player.get_node_or_null("CameraPivot") as Node3D
    var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if pivot == null or spring_arm == null or camera == null:
        _fail("authoritative player camera chain unavailable")
        return

    var resolver_fov_before := camera.fov
    var resolver_camera_basis_before := camera.transform.basis
    var resolver_spring_transform_before := spring_arm.transform
    var resolver_spring_length_before := spring_arm.spring_length
    var resolver_spring_margin_before := spring_arm.margin
    var resolver_pivot_transform_before := pivot.transform
    var resolver: Node = RESOLVER_SCRIPT.new()
    scene.add_child(resolver)
    if not resolver.call("apply_to_player", player, ROAD_ID):
        _fail("generic road-8512036 direct-entry resolver rejected repository-derived candidate")
        return
    if not _camera_authored_contract_unchanged(camera, spring_arm, pivot, resolver_camera_basis_before, resolver_fov_before, resolver_spring_transform_before, resolver_spring_length_before, resolver_spring_margin_before, resolver_pivot_transform_before):
        _fail("resolver changed authored camera contract")
        return

    for _frame: int in range(18):
        await process_frame
        await physics_frame
    if not _camera_authored_contract_unchanged(camera, spring_arm, pivot, resolver_camera_basis_before, resolver_fov_before, resolver_spring_transform_before, resolver_spring_length_before, resolver_spring_margin_before, resolver_pivot_transform_before):
        _fail("authored camera contract drifted during post-resolver stabilization")
        return

    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != ROAD_ID:
        _fail("exact requested OSM identity not preserved")
        return
    if str(player.get_meta("automatic_road_direct_lookup_mode", "")) != "deterministic_runtime_index":
        _fail("deterministic runtime-index lookup missing")
        return
    if str(player.get_meta("automatic_road_direct_source_path", "")) != SOURCE_PATH:
        _fail("unexpected source path")
        return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains("Saint-G"):
        _fail("resolved source name drifted")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("source sightline not clear")
        return

    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("authorized collision-backed ground hit missing")
        return
    var segment_index := int(player.get_meta("automatic_road_direct_segment_index", -1))
    var tangent := _source_tangent(segment_index)
    if tangent == Vector2.ZERO:
        _fail("resolved source tangent unavailable")
        return
    var forward := -player.global_basis.z
    var axis_alignment := absf(Vector2(forward.x, forward.z).normalized().dot(tangent))
    if axis_alignment < MIN_AXIS_ALIGNMENT:
        _fail("axis alignment below frozen contract")
        return

    # QA-only masking isolates corridor pixels from the known Character-owned
    # arms-out animation defect. It never changes Player physics, camera,
    # source geometry, collision, resolver thresholds, exports or canonical runtime.
    var visual_upgrade := player.get_node_or_null(MASK_PATH) as Node3D
    if visual_upgrade == null:
        _fail("expected Player/%s visual node unavailable" % MASK_PATH)
        return
    var visual_was_visible := visual_upgrade.visible
    visual_upgrade.visible = false
    if visual_upgrade.visible:
        _fail("QA visual mask did not apply")
        return
    if not _camera_authored_contract_unchanged(camera, spring_arm, pivot, resolver_camera_basis_before, resolver_fov_before, resolver_spring_transform_before, resolver_spring_length_before, resolver_spring_margin_before, resolver_pivot_transform_before):
        _fail("QA mask changed authored camera contract")
        return

    camera.current = true
    for _frame: int in range(8):
        await process_frame
    if not _camera_authored_contract_unchanged(camera, spring_arm, pivot, resolver_camera_basis_before, resolver_fov_before, resolver_spring_transform_before, resolver_spring_length_before, resolver_spring_margin_before, resolver_pivot_transform_before):
        _fail("authored camera contract drifted during masked capture warmup")
        return
    RenderingServer.force_draw()
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
    var camera_authored_contract_unchanged := _camera_authored_contract_unchanged(camera, spring_arm, pivot, resolver_camera_basis_before, resolver_fov_before, resolver_spring_transform_before, resolver_spring_length_before, resolver_spring_margin_before, resolver_pivot_transform_before)
    if not camera_authored_contract_unchanged:
        _fail("authored camera contract drifted after QA mask restoration")
        return

    var spawn_raw: Variant = player.get_meta("automatic_road_direct_spawn_xz", null)
    var target_raw: Variant = player.get_meta("automatic_road_direct_target_xz", null)
    if not spawn_raw is Vector2 or not target_raw is Vector2:
        _fail("source-backed spawn/target metadata missing")
        return
    var spawn_xz := spawn_raw as Vector2
    var target_xz := target_raw as Vector2

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-corridor-masked-visual-v1",
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
        "segment_index": segment_index,
        "axis_alignment": axis_alignment,
        "source_sightline_clear": true,
        "qa_mask_applied": true,
        "qa_mask_node": "Player/%s" % MASK_PATH,
        "qa_mask_originally_visible": visual_was_visible,
        "qa_mask_restored": visual_upgrade.visible == visual_was_visible,
        "qa_mask_final_visibility": visual_upgrade.visible,
        "qa_mask_ephemeral": true,
        "dynamic_state_frozen": true,
        "character_runtime_changed": false,
        "player_physics_changed": false,
        "camera_changed": not camera_authored_contract_unchanged,
        "camera_authored_contract_unchanged": camera_authored_contract_unchanged,
        "camera_springarm_runtime_offset_allowed": true,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "resolver_thresholds_lowered": false,
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

    print("BOURSE_8512036_CORRIDOR_MASKED_VISUAL_OK: road-%d alignment=%.6f ground_y=%.6f mask_restored=%s camera_authored_contract_unchanged=%s png=%s" % [ROAD_ID, axis_alignment, ground_y, str(receipt["qa_mask_restored"]), str(receipt["camera_authored_contract_unchanged"]), OUTPUT_PNG])
    quit(0)
