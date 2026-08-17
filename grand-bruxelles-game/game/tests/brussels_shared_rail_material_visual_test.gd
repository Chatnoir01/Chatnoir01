extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const MIN_CHANGED_3 := 0.0030
const MIN_CHANGED_8 := 0.0010
const MIN_BBOX_W := 320
const MIN_BBOX_H := 70
const OUT_DIR := "res://artifacts/visual"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_SHARED_RAIL_VISUAL_FAIL: %s" % message)
    quit(1)

func _walk(node: Node, visitor: Callable) -> void:
    visitor.call(node)
    for child: Node in node.get_children():
        _walk(child, visitor)

func _hide_ui_and_dynamics(scene: Node) -> void:
    _walk(scene, func(node: Node) -> void:
        if node is CanvasLayer or node is Control:
            if node is CanvasItem:
                (node as CanvasItem).visible = false
        if node.is_in_group("vehicle") and node is Node3D:
            (node as Node3D).visible = false
            node.set_process(false)
            node.set_physics_process(false)
    )

func _find_nearest_rail(rails_root: Node, from: Vector3) -> CSGBox3D:
    var nearest: CSGBox3D = null
    var best := INF
    for child: Node in rails_root.get_children():
        if child is CSGBox3D and child.name.begins_with("Rail_"):
            var rail := child as CSGBox3D
            var distance := from.distance_to(rail.global_position)
            if distance < best:
                best = distance
                nearest = rail
    return nearest

func _capture(path: String) -> Image:
    await process_frame
    await process_frame
    var image := root.get_viewport().get_texture().get_image()
    image.save_png(path)
    return image

func _compare(before: Image, after: Image) -> Dictionary:
    if before.get_width() != WIDTH or before.get_height() != HEIGHT:
        return {"error": "unexpected BEFORE dimensions"}
    if after.get_width() != WIDTH or after.get_height() != HEIGHT:
        return {"error": "unexpected AFTER dimensions"}
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
    var bbox_w := 0 if max_x < 0 else max_x - min_x + 1
    var bbox_h := 0 if max_y < 0 else max_y - min_y + 1
    return {
        "ratio3": float(changed3) / total,
        "ratio8": float(changed8) / total,
        "bbox_w": bbox_w,
        "bbox_h": bbox_h,
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
    for _frame: int in range(12):
        await process_frame

    var runtime = root.get_node_or_null("BrusselsSharedRailSurfaceRuntime")
    if runtime == null or not runtime.ready_applied():
        _fail("shared rail runtime did not reach ready state")
        return
    if runtime.target_count() <= 0:
        _fail("shared rail runtime has no targets")
        return

    var rails_root := scene.get_node_or_null("BrusselsOSM/GeneratedRails")
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    var camera := scene.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if rails_root == null or player == null or camera == null:
        _fail("production player/rail camera context missing")
        return
    var nearest := _find_nearest_rail(rails_root, player.global_position)
    if nearest == null:
        _fail("no production rail visible candidate")
        return

    _hide_ui_and_dynamics(scene)
    player.look_at(Vector3(nearest.global_position.x, player.global_position.y, nearest.global_position.z), Vector3.UP)
    camera.current = true
    for _frame: int in range(4):
        await process_frame

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
    runtime.set_material_enabled(false)
    var before := await _capture(ProjectSettings.globalize_path(OUT_DIR + "/brussels_shared_rail_before.png"))
    runtime.set_material_enabled(true)
    var after := await _capture(ProjectSettings.globalize_path(OUT_DIR + "/brussels_shared_rail_after.png"))
    var metrics := _compare(before, after)
    if metrics.has("error"):
        _fail(str(metrics.error))
        return

    var ratio3 := float(metrics.ratio3)
    var ratio8 := float(metrics.ratio8)
    var bbox_w := int(metrics.bbox_w)
    var bbox_h := int(metrics.bbox_h)
    print("BRUSSELS_SHARED_RAIL_VISUAL_METRICS: ratio3=%.6f ratio8=%.6f bbox=%dx%d nearest_m=%.2f targets=%d" % [ratio3, ratio8, bbox_w, bbox_h, player.global_position.distance_to(nearest.global_position), runtime.target_count()])
    if ratio3 < MIN_CHANGED_3:
        _fail("full-frame >3 RGB impact below fixed 0.30% gate")
        return
    if ratio8 < MIN_CHANGED_8:
        _fail("full-frame >8 RGB impact below fixed 0.10% gate")
        return
    if bbox_w < MIN_BBOX_W or bbox_h < MIN_BBOX_H:
        _fail("changed-pixel bbox below fixed 320x70 gate")
        return
    print("BRUSSELS_SHARED_RAIL_VISUAL_OK")
    scene.queue_free()
    quit(0)
