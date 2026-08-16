extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const SCHOOL_TARGET := Vector3(-326.4, 6.0, -258.4)
const OUTPUT_DIR := "res://artifacts/qa/anneessens_school"
const MIN_PERCENT_GT3 := 0.50
const MIN_PERCENT_GT8 := 0.20


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    print("ANNEESSENS_SCHOOL_AB_FAIL: %s" % message)
    quit(1)


func _capture(name: String) -> Image:
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    var path := "%s/%s.png" % [OUTPUT_DIR, name]
    if image.save_png(path) != OK:
        return null
    print("ANNEESSENS_SCHOOL_AB_CAPTURE: %s" % path)
    return image


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


func _channel_byte(value: float) -> int:
    return clampi(int(round(value * 255.0)), 0, 255)


func _measure_impact(before: Image, after: Image) -> Dictionary:
    if before.get_width() != 1280 or before.get_height() != 720:
        return {"error": "unexpected BEFORE capture size"}
    if after.get_width() != before.get_width() or after.get_height() != before.get_height():
        return {"error": "capture dimensions differ"}

    var width := before.get_width()
    var height := before.get_height()
    var total := width * height
    var changed_gt3 := 0
    var changed_gt8 := 0
    var diff := Image.create_empty(width, height, false, Image.FORMAT_RGB8)

    for y: int in range(height):
        for x: int in range(width):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var dr := absi(_channel_byte(a.r) - _channel_byte(b.r))
            var dg := absi(_channel_byte(a.g) - _channel_byte(b.g))
            var db := absi(_channel_byte(a.b) - _channel_byte(b.b))
            var maximum := maxi(dr, maxi(dg, db))
            if maximum > 3:
                changed_gt3 += 1
            if maximum > 8:
                changed_gt8 += 1
            diff.set_pixel(x, y, Color(float(dr) / 255.0, float(dg) / 255.0, float(db) / 255.0, 1.0))

    var percent_gt3 := 100.0 * float(changed_gt3) / float(total)
    var percent_gt8 := 100.0 * float(changed_gt8) / float(total)
    var report := {
        "pixels": total,
        "changed_gt3": changed_gt3,
        "changed_gt8": changed_gt8,
        "percent_gt3": percent_gt3,
        "percent_gt8": percent_gt8,
    }

    var report_file := FileAccess.open("%s/impact.json" % OUTPUT_DIR, FileAccess.WRITE)
    if report_file == null:
        return {"error": "could not write impact report"}
    report_file.store_string(JSON.stringify(report, "\t"))
    report_file.close()
    if diff.save_png("%s/diff.png" % OUTPUT_DIR) != OK:
        return {"error": "could not save diff image"}
    return report


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
    var before_image := _capture("before_missing_school")
    if before_image == null:
        paused = false
        _fail("BEFORE capture failed")
        return

    hero.visible = true
    for _frame: int in range(4):
        await process_frame
    var after_image := _capture("after_school_restored")
    if after_image == null:
        paused = false
        _fail("AFTER capture failed")
        return

    var impact := _measure_impact(before_image, after_image)
    paused = false
    if impact.has("error"):
        _fail(str(impact["error"]))
        return
    var percent_gt3 := float(impact["percent_gt3"])
    var percent_gt8 := float(impact["percent_gt8"])
    print("ANNEESSENS_SCHOOL_IMPACT: %s" % JSON.stringify(impact))
    if percent_gt3 < MIN_PERCENT_GT3 or percent_gt8 < MIN_PERCENT_GT8:
        _fail("player-visible impact too small: >3=%.4f%% >8=%.4f%%" % [percent_gt3, percent_gt8])
        return

    print("ANNEESSENS_SCHOOL_AB_OK: frozen=true dynamic_masked=true player_eye=true osm_id=256375327")
    quit(0)
