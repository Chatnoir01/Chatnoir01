extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT := "res://artifacts/visual"
const BEFORE := OUT + "/midi_fonsny_exact_forecourt_before.png"
const AFTER := OUT + "/midi_fonsny_exact_forecourt_after.png"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(-652.0, 1.72, 621.0)
const ENTRANCE := Vector3(-672.2905, 0.0, 615.8035)
const MIN_OVER3 := 0.0300
const MIN_OVER8 := 0.0150
const MIN_BBOX_W := 700
const MIN_BBOX_H := 160

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_FONSNY_EXACT_FORECOURT_FAIL: " + message)
    quit(1)

func _mask_dynamic(node: Node) -> void:
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    if node is Node3D:
        var lower := node.name.to_lower()
        for token: String in ["player", "npc", "pedestrian", "traffic", "vehicle", "ambient", "police"]:
            if token in lower:
                (node as Node3D).visible = false
                break
    for child: Node in node.get_children():
        _mask_dynamic(child)

func _capture(path: String) -> Image:
    await process_frame
    await process_frame
    await RenderingServer.frame_post_draw
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty() or image.save_png(path) != OK:
        return null
    return image

func _run() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var world := packed.instantiate()
    get_root().add_child(world)
    var runtime: Node = null
    for _frame: int in range(240):
        runtime = get_root().get_node_or_null("MidiFonsnyExactForecourtRuntime")
        if runtime != null and bool(runtime.call("ready_complete")):
            break
        await process_frame
    if runtime == null or bool(runtime.call("failed")):
        _fail("registry runtime failed")
        return
    if int(runtime.call("exact_surface_count")) < 3 or int(runtime.call("collision_count_added")) != 0:
        _fail("exact-surface contract failed")
        return
    var legacy := runtime.call("legacy_forecourt") as MeshInstance3D
    if legacy == null:
        _fail("legacy slab missing")
        return
    var legacy_box := legacy.mesh as BoxMesh
    if legacy_box == null or not legacy_box.size.is_equal_approx(Vector3(18.0, 0.10, 174.0)):
        _fail("legacy 18x174 slab contract changed")
        return
    for exact_name: String in ["ExactRoadCarriageways", "ExactSidewalks"]:
        if world.find_child(exact_name, true, false) == null:
            _fail("official surface missing: " + exact_name)
            return
    _mask_dynamic(world)
    var camera := Camera3D.new()
    camera.position = CAMERA_POSITION
    camera.fov = 69.0
    world.add_child(camera)
    camera.look_at(ENTRANCE + Vector3(0.0, 5.2, 0.0), Vector3.UP)
    camera.current = true

    runtime.call("set_exact_enabled", false)
    var before := await _capture(BEFORE)
    runtime.call("set_exact_enabled", true)
    var after := await _capture(AFTER)
    if before == null or after == null:
        _fail("A/B capture missing")
        return

    var over3 := 0
    var over8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r-b.r)*255.0, maxf(absf(a.g-b.g)*255.0, absf(a.b-b.b)*255.0))
            if delta > 3.0:
                over3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                over8 += 1
    var ratio3 := float(over3) / float(WIDTH * HEIGHT)
    var ratio8 := float(over8) / float(WIDTH * HEIGHT)
    var bbox_w := 0 if max_x < min_x else max_x-min_x+1
    var bbox_h := 0 if max_y < min_y else max_y-min_y+1
    print("MIDI_FONSNY_EXACT_FORECOURT_METRICS: ratio3=%.6f ratio8=%.6f bbox=%dx%d exact_surfaces=%d" % [ratio3, ratio8, bbox_w, bbox_h, int(runtime.call("exact_surface_count"))])
    if ratio3 < MIN_OVER3 or ratio8 < MIN_OVER8 or bbox_w < MIN_BBOX_W or bbox_h < MIN_BBOX_H:
        _fail("locked player-eye impact gate failed")
        return
    print("MIDI_FONSNY_EXACT_FORECOURT_OK")
    quit(0)
