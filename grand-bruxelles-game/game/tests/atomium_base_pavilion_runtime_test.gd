extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_BASE_PAVILION_RUNTIME_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var world := Node3D.new()
    root.add_child(world)
    var terrain := TERRAIN_SCRIPT.new()
    terrain.build_collision = false
    world.add_child(terrain)
    await process_frame
    await process_frame
    if not bool(terrain.get("terrain_loaded")):
        _fail("terrain did not load")
        return
    var hero := HERO_SCRIPT.new()
    world.add_child(hero)
    if not bool(hero.call("build_on_terrain", terrain)):
        _fail("hero did not build")
        return
    if not bool(hero.get("base_pavilion_built")):
        _fail("hero did not mount pavilion")
        return
    var pavilion := hero.get_node_or_null("SourceBoundedBasePavilion")
    if pavilion == null:
        _fail("pavilion node missing")
        return
    if absf(float(pavilion.get("source_diameter_m")) - 26.0) > 0.001:
        _fail("26 m official plan diameter drifted")
        return
    if absf(float(pavilion.get("measured_facade_height_m")) - 4.027) > 0.001:
        _fail("DSM-DTM median facade height drifted")
        return
    if bool(pavilion.get("roof_geometry_resolved")) or bool(pavilion.get("support_geometry_resolved")):
        _fail("unresolved roof/support geometry was promoted")
        return
    if not bool(pavilion.get("glass_facade_only")):
        _fail("runtime scope expanded beyond glazed facade")
        return
    var facade := pavilion.get_node_or_null("SourceBoundedGlazedPavilionFacade") as MeshInstance3D
    if facade == null or facade.mesh == null:
        _fail("glazed facade mesh missing")
        return
    if facade.mesh.get_surface_count() != 1:
        _fail("unexpected pavilion surface count")
        return
    if facade.mesh.surface_get_array_len(0) != 130:
        _fail("pavilion vertex contract drifted")
        return
    if facade.mesh.surface_get_array_index_len(0) != 384:
        _fail("pavilion triangle contract drifted")
        return
    print("ATOMIUM_BASE_PAVILION_RUNTIME_OK: diameter=%.3f measured_facade_height=%.3f vertices=%d indices=%d roof_resolved=%s supports_resolved=%s" % [float(pavilion.get("source_diameter_m")), float(pavilion.get("measured_facade_height_m")), facade.mesh.surface_get_array_len(0), facade.mesh.surface_get_array_index_len(0), str(pavilion.get("roof_geometry_resolved")), str(pavilion.get("support_geometry_resolved"))])
    quit(0)
