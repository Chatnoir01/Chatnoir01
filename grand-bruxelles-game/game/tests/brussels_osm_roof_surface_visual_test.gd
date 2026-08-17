extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const OUTPUT_DIR := "res://artifacts/visual"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ROOF_SURFACE_VISUAL_FAIL: %s" % message)
    quit(1)


func _capture(name: String) -> bool:
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return false
    var path := "%s/%s.png" % [OUTPUT_DIR, name]
    if image.save_png(path) != OK:
        return false
    print("BRUSSELS_OSM_ROOF_SURFACE_CAPTURE: %s" % path)
    return true


func _run() -> void:
    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    var runtime := get_root().get_node_or_null("BrusselsOsmRoofSurfaceRuntime")
    if selector == null or not selector.has_method("_on_zone_pressed"):
        _fail("zone selector unavailable")
        return
    if runtime == null or not runtime.has_method("set_enhanced_enabled"):
        _fail("roof surface runtime unavailable")
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
        _fail("Anneessens player spawn did not become ready")
        return

    for _frame: int in range(120):
        await process_frame
    if int(runtime.call("roof_count")) <= 0:
        _fail("no generic OSM roofs registered")
        return

    # Same production player pose used by the proven Anneessens player-visit witness.
    player.rotation_degrees.y = 180.0
    for _frame: int in range(4):
        await process_frame

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    paused = true
    runtime.call("set_enhanced_enabled", false)
    for _frame: int in range(3):
        await process_frame
    if not _capture("brussels_osm_roof_surface_before"):
        paused = false
        _fail("BEFORE capture failed")
        return

    runtime.call("set_enhanced_enabled", true)
    for _frame: int in range(3):
        await process_frame
    if not _capture("brussels_osm_roof_surface_after"):
        paused = false
        _fail("AFTER capture failed")
        return
    paused = false

    print(
        "BRUSSELS_OSM_ROOF_SURFACE_VISUAL_OK: zone=anneessens player_eye=true frozen_ab=true roofs=%d" %
        int(runtime.call("roof_count"))
    )
    quit(0)
