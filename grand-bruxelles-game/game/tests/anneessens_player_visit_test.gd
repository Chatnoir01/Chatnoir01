extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const OUTPUT_DIR := "res://artifacts/qa/anneessens_visit"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_VISIT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    if selector == null or not selector.has_method("_on_zone_pressed"):
        _fail("zone selector unavailable")
        return

    selector.call("_on_zone_pressed", "anneessens")
    var main: Node = null
    var player: CharacterBody3D = null
    for _frame: int in range(360):
        await process_frame
        main = current_scene
        if main == null or main.scene_file_path != MAIN_SCENE:
            continue
        player = main.get_node_or_null("Player") as CharacterBody3D
        if player != null and player.global_position.distance_to(ANNEESSENS_SPAWN) < 0.75:
            break
    if main == null or player == null or player.global_position.distance_to(ANNEESSENS_SPAWN) >= 0.75:
        _fail("Anneessens spawn did not become ready")
        return

    for _frame: int in range(120):
        await process_frame

    var context: Variant = selector.call("current_report_context")
    if not context is Dictionary or str((context as Dictionary).get("id", "")) != "anneessens":
        _fail("report context is not Anneessens: %s" % str(context))
        return

    var query := PhysicsRayQueryParameters3D.create(
        player.global_position + Vector3.UP * 2.0,
        player.global_position + Vector3.DOWN * 8.0
    )
    query.exclude = [player.get_rid()]
    var floor_hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
    print("ANNEESSENS_VISIT_CONTEXT: pos=%s floor_hit=%s" % [str(player.global_position), str(floor_hit)])

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var yaws: Array[float] = [0.0, 90.0, 180.0, 270.0]
    for yaw: float in yaws:
        player.rotation_degrees.y = yaw
        for _frame: int in range(4):
            await process_frame
        var image := get_root().get_viewport().get_texture().get_image()
        if image == null or image.is_empty():
            _fail("capture failed at yaw %.0f" % yaw)
            return
        var path := "%s/anneessens_yaw_%03d.png" % [OUTPUT_DIR, int(yaw)]
        if image.save_png(path) != OK:
            _fail("could not save %s" % path)
            return
        print("ANNEESSENS_VISIT_CAPTURE: yaw=%.0f path=%s" % [yaw, path])

    print("ANNEESSENS_VISIT_OK: zone=anneessens views=4")
    quit(0)
