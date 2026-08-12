extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_REALISM_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/zones/laeken_jette/laeken_jette.tscn")
    if packed == null:
        _fail("zone scene did not load")
        return
    var scene: Node = packed.instantiate()
    root.add_child(scene)

    var realism := scene.get_node_or_null("RealismPass")
    var corridor := scene.get_node_or_null("AtomiumCorridor")
    var official_trees := scene.get_node_or_null("OfficialTrees")
    var source_cleanup := scene.get_node_or_null("SourceTruthCleanup")
    if realism == null or corridor == null or official_trees == null or source_cleanup == null:
        _fail("required realism/source-truth nodes missing")
        return

    # These builders are deferred and terrain draping can take several frames.
    for _frame in range(220):
        if (
            bool(official_trees.get("trees_loaded"))
            and bool(source_cleanup.get("cleanup_ready"))
            and int(corridor.get("generated_lamps")) > 0
        ):
            break
        await process_frame

    var buildings := scene.get_node_or_null("OfficialBuildings") as MeshInstance3D
    if buildings == null:
        _fail("OfficialBuildings missing")
        return
    if not buildings.material_override is ShaderMaterial:
        _fail("official buildings did not receive procedural facade shader")
        return
    if scene.get_node_or_null("AtomiumBaseRealism") == null:
        _fail("Atomium base realism detail missing")
        return

    var axis_distance := float(corridor.get("official_axis_distance_m"))
    var synthetic_trees := int(corridor.get("generated_trees"))
    var lamps := int(corridor.get("generated_lamps"))
    var synthetic_dashes := int(corridor.get("generated_dashes"))
    var official_tree_count := int(official_trees.get("official_tree_count"))
    var terrain_grounded_trees := int(official_trees.get("terrain_grounded_count"))

    if axis_distance > 150.0:
        _fail("nearest official approach axis unexpectedly far: %.2f m" % axis_distance)
        return
    # Source-truth policy: no corridor trees or painted dashes are guessed. Tree
    # positions come from the official City dataset and pavement/markings from the
    # georeferenced orthophoto. Lamps remain provisional until an authoritative
    # point layer is wired, so only their presence is expected here.
    if synthetic_trees != 0 or synthetic_dashes != 0:
        _fail("synthetic corridor clutter reappeared: trees=%d dashes=%d" % [synthetic_trees, synthetic_dashes])
        return
    if lamps < 8:
        _fail("provisional corridor lamp pass unexpectedly missing: lamps=%d" % lamps)
        return
    if official_tree_count < 8000 or terrain_grounded_trees != official_tree_count:
        _fail("official tree population not fully grounded: official=%d terrain=%d" % [official_tree_count, terrain_grounded_trees])
        return
    if not bool(source_cleanup.get("rail_source_checked")):
        _fail("rail source-truth audit did not run")
        return
    if bool(source_cleanup.get("rail_source_duplicate_detected")) and not bool(source_cleanup.get("duplicate_train_ribbon_hidden")):
        _fail("duplicate rail source detected without suppressing duplicate visual")
        return

    print("LAEKEN_REALISM_SMOKE_OK: official_axis=%.2fm synthetic_trees=%d official_trees=%d lamps=%d synthetic_dashes=%d rail_duplicate=%s" % [
        axis_distance,
        synthetic_trees,
        official_tree_count,
        lamps,
        synthetic_dashes,
        bool(source_cleanup.get("rail_source_duplicate_detected")),
    ])
    scene.queue_free()
    await process_frame
    quit(0)
