extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_3 := 0.0040
const MIN_CHANGED_8 := 0.0015
const MIN_BBOX_W := 320
const MIN_BBOX_H := 160
const OUT_DIR := "res://artifacts/visual"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("CORRIDOR_GENERIC_GLAZING_VISUAL_FAIL: %s" % message)
    quit(1)

func _walk(node: Node, visitor: Callable) -> void:
    visitor.call(node)
    for child: Node in node.get_children():
        _walk(child, visitor)

func _find_owner(scene: Node) -> Node:
    var found: Array[Node] = []
    _walk(scene, func(node: Node) -> void:
        if found.is_empty() and node.has_method("set_generic_glazing_enabled") and node.has_method("generic_glazing_target_count"):
            found.append(node)
    )
    return null if found.is_empty() else found[0]

func _mask_ui(scene: Node) -> void:
    _walk(scene, func(node: Node) -> void:
        if node is CanvasItem:
            (node as CanvasItem).visible = false
    )

func _freeze_dynamic_visibility(scene: Node, player: CharacterBody3D) -> void:
    _walk(scene, func(node: Node) -> void:
        if node is CharacterBody3D and node != player:
            (node as CharacterBody3D).visible = false
        if node is Node3D and (node.is_in_group("vehicle") or node.is_in_group("npc") or node.is_in_group("pedestrian") or node.is_in_group("traffic") or node.is_in_group("ambient") or node.is_in_group("police")):
            (node as Node3D).visible = false
    )

func _nearest_glass(details: Node3D, from: Vector3) -> Vector3:
    var best := INF
    var nearest := Vector3.INF
    for child: Node in details.get_children():
        if not (child is MultiMeshInstance3D):
            continue
        if not (child.name.begins_with("CorridorWindowGlass") or child.name.begins_with("CorridorShopfrontGlass")):
            continue
        var instance := child as MultiMeshInstance3D
        if instance.multimesh == null:
            continue
        for index: int in range(instance.multimesh.instance_count):
            var world_transform := instance.global_transform * instance.multimesh.get_instance_transform(index)
            var distance := from.distance_to(world_transform.origin)
            if distance < best:
                best = distance
                nearest = world_transform.origin
    return nearest

func _capture(path: String) -> Image:
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_viewport().get_texture().get_image()
    image.save_png(path)
    return image

func _compare(before: Image, after: Image) -> Dictionary:
    if before.get_width() != WIDTH or before.get_height() != HEIGHT or after.get_width() != WIDTH or after.get_height() != HEIGHT:
        return {"error": "unexpected capture dimensions"}
    var changed3 := 0
    var changed8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                changed3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                changed8 += 1
    var total := float(WIDTH * HEIGHT)
    return {
        "ratio3": float(changed3) / total,
        "ratio8": float(changed8) / total,
        "bbox_w": 0 if max_x < 0 else max_x - min_x + 1,
        "bbox_h": 0 if max_y < 0 else max_y - min_y + 1,
    }

func _run() -> void:
    DisplayServer.window_set_size(Vector2i(WIDTH, HEIGHT))
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate()
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
    root.add_child(scene)
    for _frame: int in range(16):
        await process_frame

    var owner := _find_owner(scene)
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    var camera := scene.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    var details := scene.get_node_or_null("BrusselsOSM/GeneratedFacadeDetails") as Node3D
    if owner == null or player == null or camera == null or details == null:
        _fail("production corridor glazing/player context missing")
        return
    if int(owner.call("generic_glazing_target_count")) < 1000:
        _fail("generic glazing target coverage unexpectedly low")
        return
    if int(owner.call("generic_glazing_material_group_count")) != 9:
        _fail("five window + four shop batching groups not preserved")
        return

    var nearest := _nearest_glass(details, player.global_position)
    if not nearest.is_finite():
        _fail("no generic corridor glazing target found")
        return

    _mask_ui(scene)
    _freeze_dynamic_visibility(scene, player)
    player.look_at(Vector3(nearest.x, player.global_position.y, nearest.z), Vector3.UP)
    camera.current = true
    for _frame: int in range(4):
        _mask_ui(scene)
        await process_frame
    scene.process_mode = Node.PROCESS_MODE_DISABLED
    _mask_ui(scene)

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    owner.call("set_generic_glazing_enabled", false)
    var before := await _capture(ProjectSettings.globalize_path(OUT_DIR + "/corridor_generic_glazing_before.png"))
    owner.call("set_generic_glazing_enabled", true)
    var after := await _capture(ProjectSettings.globalize_path(OUT_DIR + "/corridor_generic_glazing_after.png"))
    var metrics := _compare(before, after)
    if metrics.has("error"):
        _fail(str(metrics.error))
        return

    var ratio3 := float(metrics.ratio3)
    var ratio8 := float(metrics.ratio8)
    var bbox_w := int(metrics.bbox_w)
    var bbox_h := int(metrics.bbox_h)
    print("CORRIDOR_GENERIC_GLAZING_VISUAL_METRICS: ratio3=%.6f ratio8=%.6f bbox=%dx%d nearest_m=%.2f targets=%d groups=%d" % [ratio3, ratio8, bbox_w, bbox_h, player.global_position.distance_to(nearest), owner.call("generic_glazing_target_count"), owner.call("generic_glazing_material_group_count")])
    if ratio3 < MIN_CHANGED_3:
        _fail("full-frame >3 RGB impact below fixed 0.40% gate")
        return
    if ratio8 < MIN_CHANGED_8:
        _fail("full-frame >8 RGB impact below fixed 0.15% gate")
        return
    if bbox_w < MIN_BBOX_W or bbox_h < MIN_BBOX_H:
        _fail("changed-pixel bbox below fixed 320x160 gate")
        return
    print("CORRIDOR_GENERIC_GLAZING_VISUAL_OK")
    quit(0)
