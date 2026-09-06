extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
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
    var local_center := visual.get_aabb().get_center()
    return visual.global_transform * local_center

func _center_is_in_player_frame(camera: Camera3D, world_center: Vector3) -> bool:
    if camera.is_position_behind(world_center):
        return false
    if camera.global_position.distance_to(world_center) > camera.far:
        return false
    var pixel := camera.unproject_position(world_center)
    return pixel.x >= 0.0 and pixel.x < float(WIDTH) and pixel.y >= 0.0 and pixel.y < float(HEIGHT)

func _run() -> void:
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
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null:
        _fail("production player camera missing")
        return

    var camera_transform_before := camera.transform
    var camera_fov_before := camera.fov
    var camera_near_before := camera.near
    var camera_far_before := camera.far
    var camera_cull_mask_before := camera.cull_mask

    var resolver := RESOLVER_SCRIPT.new()
    viewport.add_child(resolver)
    if not resolver.apply_to_player(player, BOURSE_ORTS_ID):
        _fail("road-411724192 did not resolve through the shared automatic destination resolver")
        return
    for _frame in range(12):
        await process_frame
        await physics_frame

    if not camera.transform.is_equal_approx(camera_transform_before):
        _fail("resolver mutated production camera transform")
        return
    if not is_equal_approx(camera.fov, camera_fov_before) or not is_equal_approx(camera.near, camera_near_before) or not is_equal_approx(camera.far, camera_far_before):
        _fail("resolver mutated production camera optics")
        return
    if camera.cull_mask != camera_cull_mask_before:
        _fail("resolver mutated production camera cull mask")
        return

    camera.current = true
    await process_frame

    var visible_owner_count := 0
    var visible_visual_count := 0
    var total_visual_count := 0
    var owner_metrics: Array[String] = []

    for owner_path in OWNER_PATHS:
        var owner := scene.get_node_or_null(owner_path)
        if owner == null:
            _fail("source-backed Bourse owner missing from production scene: %s" % owner_path)
            return
        var visuals: Array[VisualInstance3D] = []
        _collect_visuals(owner, visuals)
        total_visual_count += visuals.size()
        var owner_visible := 0
        for visual in visuals:
            if not visual.is_visible_in_tree():
                continue
            var center := _visual_center(visual)
            if _center_is_in_player_frame(camera, center):
                owner_visible += 1
                visible_visual_count += 1
        if owner_visible > 0:
            visible_owner_count += 1
        owner_metrics.append("%s=%d/%d" % [owner_path, owner_visible, visuals.size()])

    print("BOURSE_SOURCE_BACKED_PLAYER_VISIBILITY_METRICS: owners_visible=%d/%d visuals_visible=%d/%d %s" % [visible_owner_count, OWNER_PATHS.size(), visible_visual_count, total_visual_count, ", ".join(owner_metrics)])

    if total_visual_count <= 0:
        _fail("source-backed Bourse owners produced no VisualInstance3D geometry")
        return
    if visible_owner_count <= 0 or visible_visual_count <= 0:
        _fail("road-411724192 player frame contains no source-backed Bourse owner geometry; keep visual acceptance fail-closed")
        return

    print("BOURSE_SOURCE_BACKED_PLAYER_VISIBILITY_GREEN: road=411724192 owners_visible=%d visuals_visible=%d camera_unchanged=true destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [visible_owner_count, visible_visual_count])
    quit(0)
