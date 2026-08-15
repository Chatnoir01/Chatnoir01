extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const EXPECTED_PLAYER_ASSET := "res://assets/characters/player_character.glb"
const OUTPUT := "res://artifacts/player/production_authored_player.png"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("PRODUCTION_PLAYER_CAPTURE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("could not load production main scene")
        return
    var main := packed.instantiate()
    root.add_child(main)

    for _frame in range(12):
        await process_frame

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player missing")
        return
    var visual := player.get_node_or_null("VisualUpgrade")
    if visual == null or not visual.is_using_authored_character():
        _fail("production Player did not select authored character")
        return
    if visual.resolved_authored_scene_path() != EXPECTED_PLAYER_ASSET:
        _fail("unexpected selected path: %s" % visual.resolved_authored_scene_path())
        return

    # Keep the production controller/camera and world intact. Freeze moving systems only
    # after the authored player has initialized so the witness is reproducible.
    for node_name in ["TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "LivingCityShowcaseRuntime"]:
        var dynamic := main.get_node_or_null(node_name)
        if dynamic != null:
            dynamic.process_mode = Node.PROCESS_MODE_DISABLED
    player.velocity = Vector3.ZERO

    for _frame in range(4):
        await process_frame

    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        _fail("viewport capture is empty")
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/player"))
    var error := image.save_png(ProjectSettings.globalize_path(OUTPUT))
    if error != OK:
        _fail("could not save PNG: %s" % error)
        return

    print("PRODUCTION_PLAYER_CAPTURE_OK: path=%s output=%s size=%dx%d" % [
        visual.resolved_authored_scene_path(), OUTPUT, image.get_width(), image.get_height()
    ])
    main.queue_free()
    await process_frame
    quit(0)
