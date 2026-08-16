extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    print("BOURSE_BLUE_STONE_PAVING_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var selector := get_root().get_node_or_null("ZoneSelectorRuntime")
    if selector == null:
        _fail("ZoneSelectorRuntime missing")
        return
    selector.call("_on_zone_pressed", "bourse")

    var main: Node = null
    var player: CharacterBody3D = null
    for _frame: int in range(360):
        await process_frame
        main = current_scene
        if main == null or main.scene_file_path != "res://game/main.tscn":
            continue
        player = main.get_node_or_null("Player") as CharacterBody3D
        if player != null and player.global_position.distance_to(Vector3(83.44, 1.05, -663.42)) < 0.8:
            break
    if main == null or player == null:
        _fail("Bourse player visit unavailable")
        return

    var runtime := get_root().get_node_or_null("BourseBlueStonePavingRuntime")
    if runtime == null:
        _fail("Bourse paving runtime missing")
        return
    for _frame: int in range(240):
        await process_frame
        if bool(runtime.call("ready_complete")):
            break
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("Bourse paving runtime did not complete")
        return
    if int(runtime.call("applied_surface_count")) != 1:
        _fail("expected one official sidewalk surface")
        return
    var material: ShaderMaterial = runtime.call("enhanced_material") as ShaderMaterial
    if material == null:
        _fail("shared blue-stone material missing")
        return
    if str(material.get_meta("recipe_source", "")) != "midi" or str(material.get_meta("zone", "")) != "bourse":
        _fail("Midi recipe provenance missing")
        return
    if bool(material.get_meta("geometry_changed", true)):
        _fail("paving lot changed geometry")
        return

    print("BOURSE_BLUE_STONE_PAVING_OK: visit=true surfaces=1 recipe=midi geometry_changed=false")
    quit(0)
