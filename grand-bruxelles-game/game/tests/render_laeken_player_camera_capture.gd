extends SceneTree

const SCENE_PATH := "res://game/zones/laeken_jette/laeken_playtest.tscn"
const OUTPUT_PATH := "res://laeken_player_camera_current.png"
const MAX_READY_FRAMES := 100


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("PLAYER_CAMERA_CAPTURE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    root.size = Vector2i(1280, 720)
    var packed := load(SCENE_PATH) as PackedScene
    if packed == null:
        _fail("Laeken playtest scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)

    var zone := scene.get_node_or_null("LaekenJetteZone")
    var player := scene.get_node_or_null("Player") as Node3D
    var player_camera := scene.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if zone == null or player == null or player_camera == null:
        _fail("zone, player or gameplay camera missing")
        return

    var terrain = zone.get_node_or_null("LaekenTerrain")
    var heights = zone.get_node_or_null("BuildingHeightPass")
    var bridge = zone.get_node_or_null("BuildingDSMMaterialBridge")
    var ortho = zone.get_node_or_null("OrthophotoPass")
    var trees = zone.get_node_or_null("OfficialTrees")
    if terrain == null or heights == null or bridge == null or ortho == null or trees == null:
        _fail("realism nodes missing")
        return

    var ready_frame := -1
    for frame_index in range(MAX_READY_FRAMES):
        if (
            bool(terrain.get("terrain_loaded"))
            and bool(heights.get("height_mesh_ready"))
            and bool(bridge.get("material_bridged"))
            and bool(ortho.get("orthophoto_active"))
            and bool(trees.get("trees_loaded"))
        ):
            ready_frame = frame_index
            break
        await process_frame
    if ready_frame < 0:
        _fail("full gameplay realism stack did not become ready")
        return

    # Do not replace or reposition the gameplay camera. This is deliberately the
    # same Camera3D used when the player controls the character in the Web build.
    player_camera.current = true
    for _i in range(8):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    await process_frame

    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("viewport image empty")
        return
    var error := image.save_png(OUTPUT_PATH)
    if error != OK:
        _fail("save_png error %s" % error)
        return

    print("PLAYER_CAMERA_CAPTURE_OK: %s %dx%d ready_frame=%d player=(%.2f,%.2f,%.2f) camera_fov=%.1f" % [
        OUTPUT_PATH,
        image.get_width(),
        image.get_height(),
        ready_frame,
        player.global_position.x,
        player.global_position.y,
        player.global_position.z,
        player_camera.fov,
    ])
    scene.queue_free()
    await process_frame
    quit(0)
