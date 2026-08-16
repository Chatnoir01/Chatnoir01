extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const OUTPUT_DIR := "res://artifacts/qa/anneessens_visit"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_VISIT_FAIL: %s" % message)
    quit(1)

func _capture(name: String) -> bool:
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return false
    var path := "%s/%s.png" % [OUTPUT_DIR, name]
    if image.save_png(path) != OK:
        return false
    print("ANNEESSENS_VISIT_CAPTURE: %s" % path)
    return true

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
        if not _capture("anneessens_yaw_%03d" % int(yaw)):
            _fail("capture failed at yaw %.0f" % yaw)
            return

    player.rotation_degrees.y = 180.0
    for _frame: int in range(4):
        await process_frame

    var facade_details := main.get_node_or_null("BrusselsOSM/GeneratedFacadeDetails") as Node3D
    if facade_details == null:
        _fail("GeneratedFacadeDetails missing")
        return
    facade_details.visible = false
    for _frame: int in range(3):
        await process_frame
    if not _capture("anneessens_yaw_180_no_facade_details"):
        _fail("facade isolation capture failed")
        return
    facade_details.visible = true

    var generated_buildings := main.get_node_or_null("BrusselsOSM/GeneratedBuildings") as Node3D
    if generated_buildings == null:
        _fail("GeneratedBuildings missing")
        return
    var roofs: Array[Node3D] = []
    var nearby_roofs := 0
    for child: Node in generated_buildings.get_children():
        if child is Node3D and child.name.begins_with("Roof_"):
            var roof := child as Node3D
            roofs.append(roof)
            if Vector2(roof.global_position.x, roof.global_position.z).distance_to(Vector2(ANNEESSENS_SPAWN.x, ANNEESSENS_SPAWN.z)) <= 100.0:
                nearby_roofs += 1
                print("ANNEESSENS_NEAR_ROOF: name=%s pos=%s" % [roof.name, str(roof.global_position)])
            roof.visible = false
    for _frame: int in range(3):
        await process_frame
    if not _capture("anneessens_yaw_180_no_roofs"):
        _fail("roof isolation capture failed")
        return
    for roof: Node3D in roofs:
        roof.visible = true

    print("ANNEESSENS_VISIT_OK: zone=anneessens views=4 roofs=%d nearby_roofs=%d" % [roofs.size(), nearby_roofs])
    quit(0)
