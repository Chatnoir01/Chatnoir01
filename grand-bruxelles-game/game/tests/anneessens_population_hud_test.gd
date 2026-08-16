extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const ACTIVE_RADIUS_M := 240.0
const OUTPUT_DIR := "res://artifacts/qa/anneessens_population_hud"
const REPORT_NOTE := "HUD VILLE VIVANTE affiche 0 civils actifs alors que les pietons Anneessens sont visibles"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_POPULATION_HUD_FAIL: %s" % message)
    quit(1)

func _capture(name: String) -> Image:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.save_png(OUTPUT_DIR.path_join("%s.png" % name)) != OK:
        return null
    return image

func _write_report(selector: Node, image: Image) -> bool:
    var context_variant: Variant = selector.call("current_report_context")
    if not context_variant is Dictionary:
        return false
    var context := context_variant as Dictionary
    var reporter: Node = selector.call("reporting_runtime")
    if reporter == null or not reporter.has_method("create_report_from_context"):
        return false
    var report_path := str(reporter.call("create_report_from_context", REPORT_NOTE, image, context, false))
    if report_path.is_empty() or not FileAccess.file_exists(report_path):
        return false
    var artifact_path := OUTPUT_DIR.path_join("anneessens_population_hud.gbreport.json")
    var artifact := FileAccess.open(artifact_path, FileAccess.WRITE)
    if artifact == null:
        return false
    artifact.store_string(FileAccess.get_file_as_string(report_path))
    artifact.close()
    print("ANNEESSENS_POPULATION_REPORT_OPEN: %s" % artifact_path)
    return true

func _local_ambient_count(player: Node3D) -> int:
    var count := 0
    for node: Node in get_nodes_in_group("ambient_pedestrian"):
        if not node is Node3D:
            continue
        var pedestrian := node as Node3D
        if not pedestrian.is_visible_in_tree():
            continue
        if pedestrian.global_position.distance_to(player.global_position) <= ACTIVE_RADIUS_M:
            count += 1
    return count

func _run() -> void:
    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    var visible_runtime := get_root().get_node_or_null("VisibleCityRuntime")
    if selector == null or visible_runtime == null:
        _fail("required autoload missing")
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
    if main == null or player == null:
        _fail("Anneessens player spawn unavailable")
        return

    for _frame: int in range(120):
        await process_frame

    player.rotation_degrees.y = 180.0
    for _frame: int in range(6):
        await process_frame

    var local_ambient := _local_ambient_count(player)
    var counts: Dictionary = visible_runtime.call("visible_population_counts")
    var reported := int(counts.get("civilians", -1))
    var hud_text := str(visible_runtime.call("status_text_for_test"))
    print("ANNEESSENS_POPULATION_HUD_METRIC: local_ambient=%d reported=%d hud=%s" % [local_ambient, reported, hud_text])

    if local_ambient < 1:
        _fail("Anneessens has no local ambient pedestrians to validate")
        return
    if reported < local_ambient:
        var image := _capture("anneessens_population_hud_report")
        if image == null or not _write_report(selector, image):
            _fail("population mismatch found but SIGNALER artifact could not be persisted")
            return
        _fail("HUD under-reports local civilians: ambient=%d reported=%d" % [local_ambient, reported])
        return
    if not hud_text.contains("%d civils actifs" % reported):
        _fail("HUD text does not expose computed civilian count")
        return

    var hud_label := main.get_node_or_null("VisibleCityHudLayer/VisibleCityStatus/StatusLabel") as Label
    if hud_label == null:
        _fail("VisibleCity HUD label missing")
        return
    var main_process_mode := main.process_mode
    var runtime_process_mode := visible_runtime.process_mode
    main.process_mode = Node.PROCESS_MODE_DISABLED
    visible_runtime.process_mode = Node.PROCESS_MODE_DISABLED

    hud_label.text = "VILLE VIVANTE · 0 civils actifs · 0 policiers"
    for _frame: int in range(3):
        await process_frame
    if _capture("anneessens_population_before_zero") == null:
        _fail("frozen BEFORE capture failed")
        return

    hud_label.text = hud_text
    for _frame: int in range(3):
        await process_frame
    if _capture("anneessens_population_after_local") == null:
        _fail("frozen AFTER capture failed")
        return

    main.process_mode = main_process_mode
    visible_runtime.process_mode = runtime_process_mode
    print("ANNEESSENS_POPULATION_HUD_OK: local_ambient=%d reported=%d frozen_ab=true" % [local_ambient, reported])
    quit(0)
