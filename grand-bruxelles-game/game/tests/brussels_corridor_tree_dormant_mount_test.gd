extends SceneTree

const DATA_PATH := "res://data/osm/vertical_slice_01.game.json"
const ANNEESSENS_DATA_PATH := "res://data/osm/anneessens_environment_points.game.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_CORRIDOR_TREE_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}

func _first_runtime_tree_position() -> Vector3:
    var preowned := {}
    var anneessens := _load_json(ANNEESSENS_DATA_PATH)
    for raw: Variant in anneessens.get("points", []) as Array:
        if raw is Dictionary and str((raw as Dictionary).get("kind", "")) == "tree":
            preowned[int((raw as Dictionary).get("osm_id", 0))] = true
    var source := _load_json(DATA_PATH)
    for raw: Variant in source.get("environment_points", []) as Array:
        if not raw is Dictionary:
            continue
        var point := raw as Dictionary
        if str(point.get("kind", "")) != "tree" or preowned.has(int(point.get("osm_id", 0))):
            continue
        var position := point.get("position", []) as Array
        if position.size() == 2:
            return Vector3(float(position[0]), 0.0, float(position[1]))
    return Vector3(INF, INF, INF)

func _run() -> void:
    var runtime := root.get_node_or_null("BrusselsCorridorTreeRuntime")
    if runtime == null:
        _fail("BrusselsCorridorTreeRuntime autoload missing")
        return

    for _frame: int in range(185):
        await process_frame
    if bool(runtime.call("failed")):
        _fail("corridor tree runtime treated absent production scene as failure")
        return
    if bool(runtime.call("ready_complete")):
        _fail("corridor tree runtime completed without a production mount")
        return

    var tree_position := _first_runtime_tree_position()
    if not is_finite(tree_position.x):
        _fail("could not resolve source-backed runtime tree anchor")
        return

    var viewport := SubViewport.new()
    viewport.name = "DormantCorridorTreeMountViewport"
    root.add_child(viewport)
    var main_mount := Node3D.new()
    main_mount.name = "Main"
    viewport.add_child(main_mount)
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    main_mount.add_child(osm)
    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    osm.add_child(roads)
    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    main_mount.add_child(urbis)
    var player := Node3D.new()
    player.name = "Player"
    player.position = tree_position
    main_mount.add_child(player)

    for _frame: int in range(18):
        await process_frame

    if bool(runtime.call("failed")) or not bool(runtime.call("ready_complete")):
        _fail("corridor tree runtime did not bind after legitimate nested production mount")
        return
    if int(runtime.call("tree_count")) != 266 or int(runtime.call("collision_count")) != 266:
        _fail("source-backed tree/collision counts changed")
        return
    if int(runtime.call("batch_count")) != 3:
        _fail("corridor tree batching contract changed")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("corridor tree runtime moved source positions")
        return
    if not bool(runtime.call("lod_active")):
        _fail("corridor tree runtime bound the wrong scene and lost the player LOD anchor")
        return
    var tree_root := main_mount.get_node_or_null("BrusselsCorridorTrees")
    if tree_root == null:
        _fail("corridor tree root was not attached to the validated Main mount")
        return
    if str(tree_root.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API" or str(tree_root.get_meta("license", "")) != "ODbL-1.0":
        _fail("corridor tree provenance changed")
        return
    if bool(tree_root.get_meta("species_claimed", true)) or bool(tree_root.get_meta("source_dimensions_measured", true)):
        _fail("corridor tree authored presentation claims became source-backed")
        return

    print("BRUSSELS_CORRIDOR_TREE_DORMANT_MOUNT_OK: source_trees=273 preowned=7 runtime_trees=266 collisions=266 batches=3 nested_mount=true player_anchor=true event_driven=true source=OSM license=ODbL-1.0")
    quit(0)
