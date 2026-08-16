extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_SPAWN := Vector3(-272.04, 1.05, -217.07)
const EXPECTED_TREE_IDS := [4672009403, 4672009414, 4672009415, 4672009416, 4672009417, 11929097332, 11929097333]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("ANNEESSENS_OSM_FURNITURE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    if selector == null:
        _fail("ZoneSelectorRuntime missing")
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
        _fail("Anneessens spawn unavailable")
        return

    for _frame: int in range(30):
        await process_frame

    var root := main.get_node_or_null("AnneessensOsmFurniture") as Node3D
    if root == null or not root.visible:
        _fail("Anneessens OSM furniture root missing or inactive")
        return

    var found_ids: Array[int] = []
    for node: Node in get_nodes_in_group("osm_environment_furniture"):
        if not node is StaticBody3D:
            _fail("OSM furniture must have physical collision owner")
            return
        var tree := node as StaticBody3D
        if not tree.is_visible_in_tree():
            continue
        if str(tree.get_meta("license", "")) != "ODbL-1.0":
            _fail("OSM furniture provenance/license missing")
            return
        var collision := tree.get_node_or_null("CollisionShape3D") as CollisionShape3D
        if collision == null or collision.shape == null:
            _fail("tree collision missing: %s" % tree.name)
            return
        found_ids.append(int(tree.get_meta("osm_id", 0)))

    found_ids.sort()
    var expected := EXPECTED_TREE_IDS.duplicate()
    expected.sort()
    if found_ids != expected:
        _fail("expected seven exact OSM trees, got %s" % str(found_ids))
        return

    print("ANNEESSENS_OSM_FURNITURE_OK: trees=7 collisions=7 source=OSM license=ODbL-1.0")
    quit(0)
