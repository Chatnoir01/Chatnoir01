extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_TOPO_ESPLANADE_FAIL: %s" % message)
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
        _fail("official DTM did not load")
        return
    var hero := HERO_SCRIPT.new()
    world.add_child(hero)
    if not bool(hero.call("build_on_terrain", terrain)):
        _fail("hero/context build failed")
        return
    var context := hero.get_node_or_null("OfficialTopoEsplanadeContext")
    if context == null or not bool(context.get("context_built")):
        _fail("source-backed context missing")
        return
    if int(context.get("stair_feature_count")) != 14 or int(context.get("bench_feature_count")) != 5:
        _fail("bounded source feature counts drifted")
        return
    if int(context.get("stair_segment_count")) < 40 or int(context.get("bench_polygon_count")) != 5:
        _fail("source geometry was not materially rendered")
        return
    if bool(context.get("surveyed_vertical_dimensions")) or bool(context.get("has_collision")):
        _fail("presentation-only vertical profile was incorrectly promoted")
        return
    if context.get_node_or_null("OfficialTopoStairs") == null or context.get_node_or_null("OfficialTopoBenches") == null:
        _fail("runtime meshes missing")
        return
    print("ATOMIUM_TOPO_ESPLANADE_OK: stairs=%d segments=%d benches=%d polygons=%d collision=%s" % [int(context.get("stair_feature_count")), int(context.get("stair_segment_count")), int(context.get("bench_feature_count")), int(context.get("bench_polygon_count")), str(bool(context.get("has_collision")))])
    quit(0)
