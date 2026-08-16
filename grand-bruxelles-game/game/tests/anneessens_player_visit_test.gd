extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const OUTPUT_DIR := "res://artifacts/qa/anneessens_visit"
const REPORT_NOTE := "toits flottants"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_VISIT_FAIL: %s" % message)
    quit(1)

func _capture(name: String) -> Image:
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var path := "%s/%s.png" % [OUTPUT_DIR, name]
    if image.save_png(path) != OK:
        return null
    print("ANNEESSENS_VISIT_CAPTURE: %s" % path)
    return image

func _write_report_artifact(selector: Node, context: Dictionary, image: Image) -> bool:
    if not selector.has_method("reporting_runtime"):
        return false
    var reporter: Node = selector.call("reporting_runtime")
    if reporter == null or not reporter.has_method("create_report_from_context"):
        return false
    var report_path := str(reporter.call("create_report_from_context", REPORT_NOTE, image, context, false))
    if report_path.is_empty() or not FileAccess.file_exists(report_path):
        return false
    var artifact_path := OUTPUT_DIR.path_join("anneessens_toits_flottants.gbreport.json")
    var artifact := FileAccess.open(artifact_path, FileAccess.WRITE)
    if artifact == null:
        return false
    artifact.store_string(FileAccess.get_file_as_string(report_path))
    artifact.close()
    print("ANNEESSENS_PLAYER_REPORT_OPEN: note=%s artifact=%s" % [REPORT_NOTE, artifact_path])
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

    var context_variant: Variant = selector.call("current_report_context")
    if not context_variant is Dictionary or str((context_variant as Dictionary).get("id", "")) != "anneessens":
        _fail("report context is not Anneessens: %s" % str(context_variant))
        return
    var context := context_variant as Dictionary

    var query := PhysicsRayQueryParameters3D.create(
        player.global_position + Vector3.UP * 2.0,
        player.global_position + Vector3.DOWN * 8.0
    )
    query.exclude = [player.get_rid()]
    var floor_hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(query)
    print("ANNEESSENS_VISIT_CONTEXT: pos=%s floor_hit=%s" % [str(player.global_position), str(floor_hit)])

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var generated_buildings := main.get_node_or_null("BrusselsOSM/GeneratedBuildings") as Node3D
    if generated_buildings == null:
        _fail("GeneratedBuildings missing")
        return

    var roofs: Array[CSGPolygon3D] = []
    var nearby_roofs := 0
    var vertical_mismatch_count := 0
    var max_vertical_gap := 0.0
    for child: Node in generated_buildings.get_children():
        if not child is CSGPolygon3D or not child.name.begins_with("Roof_"):
            continue
        var roof := child as CSGPolygon3D
        roofs.append(roof)
        if Vector2(roof.global_position.x, roof.global_position.z).distance_to(Vector2(ANNEESSENS_SPAWN.x, ANNEESSENS_SPAWN.z)) > 100.0:
            continue
        nearby_roofs += 1
        var building_name := str(roof.name).replace("Roof_", "Building_")
        var building := generated_buildings.get_node_or_null(building_name) as CSGPolygon3D
        if building == null:
            _fail("matching building missing for %s" % roof.name)
            return
        var roof_bottom := roof.position.y - roof.depth
        var building_top := building.position.y
        var gap := absf(roof_bottom - building_top)
        max_vertical_gap = maxf(max_vertical_gap, gap)
        if gap > 0.25:
            vertical_mismatch_count += 1
        print("ANNEESSENS_ROOF_PARITY: roof=%s building_top=%.2f roof_bottom=%.2f gap=%.2f" % [roof.name, building_top, roof_bottom, gap])

    var yaws: Array[float] = [0.0, 90.0, 180.0, 270.0]
    var before_image: Image = null
    for yaw: float in yaws:
        player.rotation_degrees.y = yaw
        for _frame: int in range(4):
            await process_frame
        var image := _capture("anneessens_yaw_%03d" % int(yaw))
        if image == null:
            _fail("capture failed at yaw %.0f" % yaw)
            return
        if is_equal_approx(yaw, 180.0):
            before_image = image

    if vertical_mismatch_count > 0:
        if before_image == null or not _write_report_artifact(selector, context, before_image):
            _fail("could not persist SIGNALER ticket")
            return
        if bool(selector.call("can_promote_zone", "anneessens")):
            _fail("OPEN player report did not block Anneessens promotion")
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
    if _capture("anneessens_yaw_180_no_facade_details") == null:
        _fail("facade isolation capture failed")
        return
    facade_details.visible = true

    for roof: CSGPolygon3D in roofs:
        roof.visible = false
    for _frame: int in range(3):
        await process_frame
    if _capture("anneessens_yaw_180_no_roofs") == null:
        _fail("roof isolation capture failed")
        return
    for roof: CSGPolygon3D in roofs:
        roof.visible = true

    print("ANNEESSENS_ROOF_PARITY_SUMMARY: nearby=%d mismatched=%d max_gap=%.2f" % [nearby_roofs, vertical_mismatch_count, max_vertical_gap])
    if nearby_roofs <= 0:
        _fail("no nearby OSM roofs to validate")
        return
    if vertical_mismatch_count > 0:
        _fail("floating OSM roofs: %d/%d nearby building tops detached, max gap %.2fm" % [vertical_mismatch_count, nearby_roofs, max_vertical_gap])
        return

    print("ANNEESSENS_VISIT_OK: zone=anneessens roofs=%d nearby_roofs=%d parity=true" % [roofs.size(), nearby_roofs])
    quit(0)
