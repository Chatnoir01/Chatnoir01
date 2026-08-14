extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const BIN_SCRIPT := preload("res://game/scripts/bourse_smart_bins_visual.gd")
const OUTPUT_PATH := "res://artifacts/bourse/bourse_smart_bins_witness.png"
const WIDTH := 1280
const HEIGHT := 720
const CAMERA_POSITION := Vector3(154.0, 1.05, -726.0)
const CAMERA_TARGET := Vector3(128.0, 0.8, -700.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_SMART_BINS_WITNESS_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame

    var bins := BIN_SCRIPT.new()
    bins.name = "BourseSmartBinsWitness"
    main.add_child(bins)
    await process_frame
    if int(bins.rendered_bin_count) != 7:
        _fail("source-backed bins did not render")
        return

    var player := main.get_node_or_null("Player") as Node3D
    if player == null:
        _fail("production player camera rig missing")
        return
    player.global_position = CAMERA_POSITION
    var to_target := CAMERA_TARGET - player.global_position
    player.rotation_degrees.y = rad_to_deg(atan2(-to_target.x, -to_target.z))
    var pivot := player.get_node_or_null("CameraPivot") as Node3D
    if pivot == null:
        _fail("production camera pivot missing")
        return
    pivot.rotation_degrees.x = -4.0
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null:
        _fail("production Camera3D missing")
        return
    camera.current = true

    for path: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap", "MobileControls"]:
        var hud := main.get_node_or_null(path)
        if hud is CanvasItem:
            (hud as CanvasItem).visible = false

    for _frame: int in range(24):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid")
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("capture save failed")
        return
    print("BOURSE_SMART_BINS_WITNESS_OK: capture=%s size=%dx%d camera=(%.1f,%.1f,%.1f)" % [OUTPUT_PATH, WIDTH, HEIGHT, CAMERA_POSITION.x, CAMERA_POSITION.y, CAMERA_POSITION.z])
    quit(0)
