extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const BEFORE_PATH := "res://artifacts/visual/brussels_bilingual_police_vest_before.png"
const AFTER_PATH := "res://artifacts/visual/brussels_bilingual_police_vest_after.png"
const MIN_GT3_PERCENT := 0.35
const MIN_GT8_PERCENT := 0.20

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BILINGUAL_POLICE_VEST_WITNESS_FAIL: %s" % message)
    quit(1)

func _save(image: Image, path: String) -> void:
    var absolute_output := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("could not save %s" % path)

func _capture(viewport: Viewport) -> Image:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid: expected %dx%d got %dx%d" % [WIDTH, HEIGHT, image.get_width() if image != null else -1, image.get_height() if image != null else -1])
        return Image.new()
    return image

func _set_rear_identity_visible(value: bool) -> int:
    var toggled := 0
    for node: Node in get_nodes_in_group("police_officer"):
        if not node is NpcAgent:
            continue
        var visual := node.get_node_or_null("VisibleHumanoid")
        if visual == null:
            continue
        var panel := visual.get_node_or_null("PoliceRearHiVis") as VisualInstance3D
        var label := visual.get_node_or_null("UniformPoliceRearLabel") as Label3D
        if panel != null:
            panel.visible = value
            toggled += 1
        if label != null:
            label.visible = value
    return toggled

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene

    for _frame: int in range(12):
        await process_frame
        await physics_frame

    var visible_runtime := root.get_node_or_null("VisibleCityRuntime")
    var showcase := root.get_node_or_null("LivingCityShowcaseRuntime")
    if visible_runtime == null or showcase == null:
        _fail("living-city autoloads missing")
        return
    visible_runtime.call("ensure_zone_for_test", "midi")
    for _frame: int in range(8):
        await process_frame
        await physics_frame

    if not bool(showcase.call("trigger_showcase_for_test", "midi")):
        _fail("normal production Midi showcase could not trigger")
        return
    for _frame: int in range(16):
        await process_frame
        await physics_frame

    var state: Dictionary = showcase.call("showcase_state_for_test")
    if int(state.get("responding_police", 0)) < 1:
        _fail("no naturally responding police officer in production showcase")
        return

    # Freeze the exact post-trigger production state. Traffic, civilians, police,
    # physics and showcase orchestration no longer advance between A/B. The only
    # mutation after this line is visibility of the newly authored rear vest cue.
    scene.process_mode = Node.PROCESS_MODE_DISABLED
    visible_runtime.process_mode = Node.PROCESS_MODE_DISABLED
    showcase.process_mode = Node.PROCESS_MODE_DISABLED

    var toggled := _set_rear_identity_visible(false)
    if toggled < 2:
        _fail("expected at least two production police vest surfaces")
        return
    var before := await _capture(root)
    if before.is_empty():
        return
    _save(before, BEFORE_PATH)

    _set_rear_identity_visible(true)
    var after := await _capture(root)
    if after.is_empty():
        return
    _save(after, AFTER_PATH)

    var gt3 := 0
    var gt8 := 0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                gt3 += 1
            if delta > 8.0:
                gt8 += 1

    var total := WIDTH * HEIGHT
    var gt3_percent := float(gt3) * 100.0 / float(total)
    var gt8_percent := float(gt8) * 100.0 / float(total)
    if gt3_percent < MIN_GT3_PERCENT or gt8_percent < MIN_GT8_PERCENT:
        _fail("natural player-frame cue too small: gt3=%.4f%% gt8=%.4f%%" % [gt3_percent, gt8_percent])
        return

    print("BRUSSELS_BILINGUAL_POLICE_VEST_WITNESS_OK: gt3=%d pct_gt3=%.4f gt8=%d pct_gt8=%.4f officers=%d dynamic_state=frozen exposure=production_midi_showcase visual_mount=VisibleHumanoid viewport=root" % [gt3, gt3_percent, gt8, gt8_percent, toggled])
    quit(0)
