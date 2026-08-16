extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const ACTIVE_RADIUS_M := 240.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_POPULATION_HUD_FAIL: %s" % message)
    quit(1)

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

    var local_ambient := _local_ambient_count(player)
    var counts: Dictionary = visible_runtime.call("visible_population_counts")
    var reported := int(counts.get("civilians", -1))
    var hud_text := str(visible_runtime.call("status_text_for_test"))
    print("ANNEESSENS_POPULATION_HUD_METRIC: local_ambient=%d reported=%d hud=%s" % [local_ambient, reported, hud_text])

    if local_ambient < 1:
        _fail("Anneessens has no local ambient pedestrians to validate")
        return
    if reported < local_ambient:
        _fail("HUD under-reports local civilians: ambient=%d reported=%d" % [local_ambient, reported])
        return
    if not hud_text.contains("%d civils actifs" % reported):
        _fail("HUD text does not expose computed civilian count")
        return

    print("ANNEESSENS_POPULATION_HUD_OK: local_ambient=%d reported=%d" % [local_ambient, reported])
    quit(0)
