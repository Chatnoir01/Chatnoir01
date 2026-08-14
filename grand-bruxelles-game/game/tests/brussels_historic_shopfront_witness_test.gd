extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SHOPFRONT_SCRIPT := preload("res://game/scripts/brussels_historic_shopfront.gd")
const WIDTH := 1280
const HEIGHT := 720
const OUTPUT_PATH := "res://artifacts/visual/brussels_historic_shopfront_witness.png"
const SOURCE_ADDRESS_WORLD := Vector3(193.6649, 0.0, -714.4507)
const STREET_AXIS_YAW_DEGREES := 23.9784

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_HISTORIC_SHOPFRONT_WITNESS_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    await process_frame
    await process_frame

    var shopfront := SHOPFRONT_SCRIPT.new()
    shopfront.name = "HistoricShopfrontSourceAddressWitness"
    shopfront.position = SOURCE_ADDRESS_WORLD
    shopfront.rotation_degrees.y = STREET_AXIS_YAW_DEGREES
    main.add_child(shopfront)
    await process_frame
    if not bool(shopfront.get("visual_built")):
        _fail("shopfront did not build")
        return

    var player_camera := main.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player_camera != null:
        player_camera.current = false

    # The family faces local +Z. View it from that side using a fixed production
    # scene camera; this does not turn the address witness into a surveyed mount.
    var yaw := deg_to_rad(STREET_AXIS_YAW_DEGREES)
    var front_normal := Vector3(sin(yaw), 0.0, cos(yaw)).normalized()
    var camera := Camera3D.new()
    camera.name = "ShopfrontWitnessCamera"
    camera.position = SOURCE_ADDRESS_WORLD + front_normal * 12.5 + Vector3(0.0, 2.35, 0.0)
    camera.fov = 53.0
    camera.current = true
    main.add_child(camera)
    camera.look_at(SOURCE_ADDRESS_WORLD + Vector3(0.0, 1.72, 0.0), Vector3.UP)

    for label_name: String in ["LocationLabel", "MissionLabel", "SaveStatusLabel", "WalletLabel", "MiniMap"]:
        var item := main.get_node_or_null(label_name)
        if item is CanvasItem:
            (item as CanvasItem).visible = false

    for _frame: int in range(60):
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

    print("BRUSSELS_HISTORIC_SHOPFRONT_WITNESS_OK: source_address_world=(%.4f, %.4f) yaw=%.4f capture=%s" % [SOURCE_ADDRESS_WORLD.x, SOURCE_ADDRESS_WORLD.z, STREET_AXIS_YAW_DEGREES, OUTPUT_PATH])
    quit(0)
