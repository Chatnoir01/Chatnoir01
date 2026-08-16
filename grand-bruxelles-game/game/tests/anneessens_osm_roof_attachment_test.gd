extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const RADIUS_M := 100.0
const MAX_ATTACHMENT_GAP_M := 0.25
const AFTER_PATH := "res://artifacts/qa/anneessens_roof_fix/anneessens_after_yaw_180.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_ROOF_ATTACHMENT_FAIL: %s" % message)
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

    for _frame: int in range(90):
        await process_frame

    var generated := main.get_node_or_null("BrusselsOSM/GeneratedBuildings") as Node3D
    if generated == null:
        _fail("GeneratedBuildings missing")
        return

    var nearby_pairs := 0
    var detached := 0
    var max_gap := -INF
    for child: Node in generated.get_children():
        if not child is CSGPolygon3D or not child.name.begins_with("Roof_"):
            continue
        var roof := child as CSGPolygon3D
        if Vector2(roof.global_position.x, roof.global_position.z).distance_to(Vector2(ANNEESSENS_SPAWN.x, ANNEESSENS_SPAWN.z)) > RADIUS_M:
            continue
        var osm_suffix := str(roof.name).trim_prefix("Roof_")
        var building := generated.get_node_or_null("Building_%s" % osm_suffix) as CSGPolygon3D
        if building == null:
            _fail("matching building missing for %s" % roof.name)
            return
        nearby_pairs += 1
        # MODE_DEPTH extrudes along negative local Z. With X=-90°, the polygon plane
        # at building.global_position.y is the visible top and depth extends downward.
        var building_top := building.global_position.y
        var roof_bottom := roof.global_position.y - roof.depth
        var gap := roof_bottom - building_top
        max_gap = maxf(max_gap, gap)
        if gap > MAX_ATTACHMENT_GAP_M:
            detached += 1
            print("ANNEESSENS_DETACHED_ROOF: roof=%s building=%s gap=%.3f" % [roof.name, building.name, gap])

    print("ANNEESSENS_ROOF_ATTACHMENT_METRIC: pairs=%d detached=%d max_gap=%.3f" % [nearby_pairs, detached, max_gap])
    if nearby_pairs < 10:
        _fail("not enough nearby roof/building pairs: %d" % nearby_pairs)
        return
    if detached > 0:
        _fail("%d/%d nearby OSM roofs detached; max_gap=%.3f m" % [detached, nearby_pairs, max_gap])
        return

    player.rotation_degrees.y = 180.0
    for _frame: int in range(6):
        await process_frame
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AFTER_PATH.get_base_dir()))
    var image := get_root().get_viewport().get_texture().get_image()
    if image == null or image.is_empty() or image.save_png(AFTER_PATH) != OK:
        _fail("AFTER witness capture failed")
        return
    print("ANNEESSENS_ROOF_ATTACHMENT_OK: pairs=%d detached=0 witness=%s" % [nearby_pairs, AFTER_PATH])
    quit(0)
