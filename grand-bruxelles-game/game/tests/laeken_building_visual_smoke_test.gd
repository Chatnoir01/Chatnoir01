extends SceneTree

const ORTHO := "res://data/orthophoto/laeken_jette/phase1_ortho.jpg"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_BUILDING_VISUAL_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed := load("res://game/zones/laeken_jette/laeken_jette.tscn") as PackedScene
    if packed == null:
        _fail("Laeken scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _i in range(6):
        await process_frame

    var pass_node = scene.get_node_or_null("BuildingVisualPass")
    if pass_node == null:
        _fail("BuildingVisualPass missing")
        return
    if not bool(pass_node.get("building_visual_active")):
        _fail("building visual pass did not activate")
        return

    var buildings := scene.get_node_or_null("OfficialBuildings") as MeshInstance3D
    if buildings == null:
        _fail("OfficialBuildings missing")
        return
    if not buildings.material_override is ShaderMaterial:
        _fail("building ShaderMaterial override missing")
        return

    if ResourceLoader.exists(ORTHO) and not bool(pass_node.get("orthophoto_roof_active")):
        _fail("official orthophoto exists but building roofs are not using it")
        return

    print("LAEKEN_BUILDING_VISUAL_OK: ortho_roofs=%s" % bool(pass_node.get("orthophoto_roof_active")))
    scene.queue_free()
    await process_frame
    quit(0)
