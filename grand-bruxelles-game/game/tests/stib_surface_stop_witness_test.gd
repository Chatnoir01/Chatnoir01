extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const STOP_SCRIPT := preload("res://game/scripts/stib_surface_stop_visual.gd")
const OUTPUT_PATH := "res://artifacts/stib/stib_surface_stop_witness.png"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("STIB_SURFACE_STOP_WITNESS_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame
    await process_frame

    var visual := STOP_SCRIPT.new()
    visual.name = "StibSurfaceStopWitness"
    main.add_child(visual)
    # Presentation-only witness near the shipped Midi start. This does not claim
    # a surveyed stop anchor; production placement requires independent evidence.
    visual.global_position = Vector3(-650.0, 0.0, 621.0)
    visual.rotation_degrees.y = 90.0
    await process_frame

    if not bool(visual.get("visual_built")):
        _fail("surface-stop visual did not build inside main scene")
        return

    var player := main.get_node_or_null("Player") as Node3D
    if player == null:
        _fail("production player camera rig missing")
        return
    # Keep the shipped camera rig/FOV while moving the witness operator to a
    # clear oblique inspection pose. Hide only the player's body for evidence.
    var body_mesh := player.get_node_or_null("MeshInstance3D") as CanvasItem
    if body_mesh != null:
        body_mesh.visible = false
    var visual_upgrade := player.get_node_or_null("VisualUpgrade") as CanvasItem
    if visual_upgrade != null:
        visual_upgrade.visible = false
    player.global_position = Vector3(-639.0, 1.05, 632.0)
    player.look_at(Vector3(-650.0, 1.15, 621.0), Vector3.UP)
    var pivot := player.get_node_or_null("CameraPivot") as Node3D
    if pivot == null:
        _fail("production camera pivot missing")
        return
    pivot.rotation_degrees.x = -3.0

    for _frame: int in range(10):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("capture unavailable")
        return
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("unexpected capture size %dx%d" % [image.get_width(), image.get_height()])
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("capture save failed")
        return
    print("STIB_SURFACE_STOP_WITNESS_OK: production_camera=true presentation_only=true capture=%s size=%dx%d" % [OUTPUT_PATH, WIDTH, HEIGHT])
    quit(0)
