extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const RESOLVER_SOURCE_PATH := "res://game/scripts/automatic_road_direct_spawn.gd"
const BOURSE_ORTS_ID := 411724192
const OWNER_PATHS := [
    "UrbISBourseGeotaggedFrontage",
    "UrbISBourseAxisContext",
    "UrbISBourseSurfaceContext",
    "UrbISHeroGeometry",
    "BoursePorticoArticulation",
]
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_SOURCE_BACKED_PLAYER_VISIBILITY_FAIL: %s" % message)
    quit(1)

func _collect_visuals(node: Node, out: Array[VisualInstance3D]) -> void:
    if node is VisualInstance3D:
        out.append(node as VisualInstance3D)
    for child in node.get_children():
        _collect_visuals(child, out)

func _visual_center(visual: VisualInstance3D) -> Vector3:
    return visual.global_transform * visual.get_aabb().get_center()

func _center_is_in_player_frame(camera: Camera3D, world_center: Vector3) -> bool:
    if camera.is_position_behind(world_center):
        return false
    if camera.global_position.distance_to(world_center) > camera.far:
        return false
    var pixel := camera.unproject_position(world_center)
    return pixel.x >= 0.0 and pixel.x < float(WIDTH) and pixel.y >= 0.0 and pixel.y < float(HEIGHT)

func _measure_source_backed_visibility(scene: Node, camera: Camera3D) -> Dictionary:
    var visible_owner_count := 0
    var visible_visual_count := 0
    var total_visual_count := 0
    var owner_metrics: Array[String] = []
    for owner_path in OWNER_PATHS:
        var owner := scene.get_node_or_null(owner_path)
        if owner == null:
            return {"error": "source-backed Bourse owner missing from production scene: %s" % owner_path}
        var visuals: Array[VisualInstance3D] = []
        _collect_visuals(owner, visuals)
        total_visual_count += visuals.size()
        var owner_visible := 0
        for visual in visuals:
            if visual.is_visible_in_tree() and _center_is_in_player_frame(camera, _visual_center(visual)):
                owner_visible += 1
                visible_visual_count += 1
        if owner_visible > 0:
            visible_owner_count += 1
        owner_metrics.append("%s=%d/%d" % [owner_path, owner_visible, visuals.size()])
    return {
        "visible_owner_count": visible_owner_count,
        "visible_visual_count": visible_visual_count,
        "total_visual_count": total_visual_count,
        "owner_metrics": owner_metrics,
    }

func _resolver_preserves_authored_camera_contract() -> bool:
    var source := FileAccess.get_file_as_string(RESOLVER_SOURCE_PATH)
    if source.is_empty():
        return false
    for forbidden in [
        "camera.transform =",
        "camera.global_transform =",
        "camera.position =",
        "camera.rotation =",
        "camera.rotation_degrees =",
        "camera.fov =",
        "camera.near =",
        "camera.far =",
        "camera.cull_mask =",
        "spring_arm.spring_length =",
    ]:
        if source.contains(forbidden):
            return false
    return true

func _orient_body_to_target(body: CharacterBody3D, spawn_xz: Vector2, target_xz: Vector2) -> void:
    var to_target := target_xz - spawn_xz
    body.rotation_degrees.y = rad_to_deg(atan2(-to_target.x, -to_target.y))

func _run() -> void:
    if not _resolver_preserves_authored_camera_contract():
        _fail("resolver contains a forbidden authored camera/SpringArm mutation")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    for _frame in range(36):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player missing")
        return
    var spring_arm := player.get_node_or_null("CameraPivot/SpringArm3D") as SpringArm3D
    if spring_arm == null:
        _fail("production player SpringArm3D missing")
        return
    var camera := spring_arm.get_node_or_null("Camera3D") as Camera3D
    if camera == null:
        _fail("production player camera missing")
        return

    var camera_fov_before := camera.fov
    var camera_near_before := camera.near
    var camera_far_before := camera.far
    var camera_cull_mask_before := camera.cull_mask
    var spring_length_before := spring_arm.spring_length

    var resolver := RESOLVER_SCRIPT.new()
    viewport.add_child(resolver)
    if not resolver.apply_to_player(player, BOURSE_ORTS_ID):
        _fail("road-411724192 did not resolve through the shared automatic destination resolver")
        return
    for _frame in range(12):
        await process_frame
        await physics_frame

    if not is_equal_approx(spring_arm.spring_length, spring_length_before):
        _fail("production SpringArm3D configured length changed")
        return
    if not is_equal_approx(camera.fov, camera_fov_before) or not is_equal_approx(camera.near, camera_near_before) or not is_equal_approx(camera.far, camera_far_before):
        _fail("production camera optics changed")
        return
    if camera.cull_mask != camera_cull_mask_before:
        _fail("production camera cull mask changed")
        return

    camera.current = true
    await process_frame

    var production_metrics := _measure_source_backed_visibility(scene, camera)
    if production_metrics.has("error"):
        _fail(str(production_metrics["error"]))
        return
    var visible_owner_count := int(production_metrics["visible_owner_count"])
    var visible_visual_count := int(production_metrics["visible_visual_count"])
    var total_visual_count := int(production_metrics["total_visual_count"])
    var owner_metrics: Array = production_metrics["owner_metrics"]
    print("BOURSE_SOURCE_BACKED_PLAYER_VISIBILITY_METRICS: owners_visible=%d/%d visuals_visible=%d/%d %s" % [visible_owner_count, OWNER_PATHS.size(), visible_visual_count, total_visual_count, ", ".join(owner_metrics)])

    if total_visual_count <= 0:
        _fail("source-backed Bourse owners produced no VisualInstance3D geometry")
        return

    if visible_owner_count <= 0 or visible_visual_count <= 0:
        var bundle: Dictionary = resolver._source_bundle_by_id(BOURSE_ORTS_ID)
        if bundle.is_empty():
            _fail("diagnostic could not reopen exact road source bundle")
            return
        var document: Dictionary = bundle["document"]
        var road: Dictionary = bundle["road"]
        var viewpoint: Dictionary = resolver._safe_viewpoint(document, road)
        if viewpoint.is_empty():
            _fail("diagnostic could not reproduce safe viewpoint")
            return
        var spawn_xz: Vector2 = viewpoint["spawn"]
        var production_target_xz: Vector2 = viewpoint["target"]
        var opposite_target_xz := spawn_xz * 2.0 - production_target_xz
        var opposite_clear := resolver._segment_clear_of_source_buildings(document, spawn_xz, opposite_target_xz)
        var opposite_clearance := resolver._source_view_corridor_clearance(document, spawn_xz, opposite_target_xz) if opposite_clear else 0.0
        var production_rotation_y := player.rotation_degrees.y
        _orient_body_to_target(player, spawn_xz, opposite_target_xz)
        for _frame in range(3):
            await process_frame
        var opposite_metrics := _measure_source_backed_visibility(scene, camera)
        player.rotation_degrees.y = production_rotation_y
        await process_frame
        if opposite_metrics.has("error"):
            _fail(str(opposite_metrics["error"]))
            return
        print("BOURSE_SOURCE_BACKED_OPPOSITE_HEADING_DIAGNOSTIC: production_target=(%.3f,%.3f) opposite_target=(%.3f,%.3f) opposite_source_sightline_clear=%s opposite_source_view_corridor_clearance_m=%.6f owners_visible=%d/%d visuals_visible=%d/%d" % [production_target_xz.x, production_target_xz.y, opposite_target_xz.x, opposite_target_xz.y, str(opposite_clear), opposite_clearance, int(opposite_metrics["visible_owner_count"]), OWNER_PATHS.size(), int(opposite_metrics["visible_visual_count"]), int(opposite_metrics["total_visual_count"])])
        _fail("road-411724192 production heading contains no source-backed Bourse owner geometry; opposite-heading diagnostic emitted without production mutation")
        return

    print("BOURSE_SOURCE_BACKED_PLAYER_VISIBILITY_GREEN: road=411724192 owners_visible=%d visuals_visible=%d authored_camera_contract_unchanged=true springarm_runtime_response_allowed=true destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [visible_owner_count, visible_visual_count])
    quit(0)
