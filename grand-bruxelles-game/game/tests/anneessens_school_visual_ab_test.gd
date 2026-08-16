extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const SCHOOL_TARGET := Vector3(-326.4, 6.0, -258.4)
const OUTPUT_DIR := "res://artifacts/qa/anneessens_school"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    print("ANNEESSENS_SCHOOL_AB_FAIL: %s" % message)
    quit(1)


func _capture(name: String) -> bool:
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return false
    var path := "%s/%s.png" % [OUTPUT_DIR, name]
    if image.save_png(path) != OK:
        return false
    print("ANNEESSENS_SCHOOL_AB_CAPTURE: %s" % path)
    return true


func _hide_dynamic_world(main: Node) -> void:
    var traffic := main.get_node_or_null("TrafficManager") as Node3D
    if traffic != null:
        traffic.visible = false
    for vehicle: Node in get_nodes_in_group("vehicle"):
        if vehicle is Node3D:
            (vehicle as Node3D).visible = false
    for child: Node in main.get_children():
        var lower := child.name.to_lower()
        if child is Node3D and ("civilian" in lower or "npc" in lower):
            (child as Node3D).visible = false


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
    if main == null or player == null:
        _fail("Anneessens player spawn unavailable")
        return

    var hero := get_root().get_node_or_null("AnneessensSchoolHero") as Node3D
    if hero == null or int(hero.get_meta("source_osm_id", 0)) != 256375327:
        _fail("source-backed school hero unavailable")
        return
    if str(hero.get_meta("plan_geometry", "")) != "exact_osm_way":
        _fail("school plan geometry is not exact OSM")
        return
    if str(hero.get_meta("vertical_geometry", "")) != "explicit_visualization_convention_not_source":
        _fail("vertical provenance is not explicit")
        return

    _hide_dynamic_world(main)
    player.global_position = ANNEESSENS_SPAWN
    player.look_at(Vector3(SCHOOL_TARGET.x, player.global_position.y, SCHOOL_TARGET.z), Vector3.UP)
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null:
        _fail("player camera unavailable")
        return
    camera.current = true

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
    paused = true
    hero.visible = false
    for _frame: int in range(4):
        await process_frame
    if not _capture("before_missing_school"):
        paused = false
        _fail("BEFORE capture failed")
        return

    hero.visible = true
    for _frame: int in range(4):
        await process_frame
    if not _capture("after_school_restored"):
        paused = false
        _fail("AFTER capture failed")
        return
    paused = false

    print("ANNEESSENS_SCHOOL_AB_OK: frozen=true dynamic_masked=true player_eye=true osm_id=256375327")
    quit(0)
