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
    await process_frame
    await process_frame
    await process_frame

    var realism := scene.get_node_or_null("RealismPass")
    if realism == null:
        _fail("RealismPass node missing")
        return
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
    if scene.get_node_or_null("AtomiumApproachPhotoGuided") == null:
        _fail("Atomium approach was not generated from official street axis")
        return

    var axis_distance := float(realism.get("selected_axis_distance_m"))
    var trees := int(realism.get("generated_trees"))
    var lamps := int(realism.get("generated_lamps"))
    var dashes := int(realism.get("generated_dashes"))
    if axis_distance > 150.0:
        _fail("nearest official approach axis unexpectedly far: %.2f m" % axis_distance)
        return
    if trees < 4 or lamps < 4 or dashes < 4:
        _fail("photo-guided detail counts too low: trees=%d lamps=%d dashes=%d" % [trees, lamps, dashes])
        return

    print("LAEKEN_REALISM_SMOKE_OK: axis=%.2fm trees=%d lamps=%d dashes=%d" % [axis_distance, trees, lamps, dashes])
    scene.queue_free()
    await process_frame
    quit(0)
