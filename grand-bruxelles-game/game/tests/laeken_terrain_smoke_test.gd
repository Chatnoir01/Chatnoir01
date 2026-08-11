extends SceneTree

const ATOMIUM_X := 224.92615906274295
const ATOMIUM_Z := -6553.143077999353


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_TERRAIN_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed: PackedScene = load("res://game/zones/laeken_jette/laeken_jette.tscn")
    if packed == null:
        _fail("Laeken scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await process_frame
    await process_frame

    var terrain = scene.get_node_or_null("LaekenTerrain")
    if terrain == null:
        _fail("LaekenTerrain node missing")
        return
    if not bool(terrain.get("terrain_loaded")):
        _fail("official DTM terrain did not load")
        return
    if scene.get_node_or_null("LaekenTerrain/OfficialDTMTerrainMesh") == null:
        _fail("official DTM mesh missing")
        return
    if scene.get_node_or_null("LaekenTerrain/OfficialDTMTerrainCollision") == null:
        _fail("official DTM collision missing")
        return

    var min_height := float(terrain.get("min_height_m"))
    var max_height := float(terrain.get("max_height_m"))
    var valid_samples := int(terrain.get("valid_sample_count"))
    var invalid_samples := int(terrain.get("invalid_sample_count"))
    var atomium_abs := float(terrain.get("atomium_absolute_elevation_m"))
    var atomium_height := float(terrain.call("sample_height", ATOMIUM_X, ATOMIUM_Z))

    if min_height < -30.0 or max_height > 40.0:
        _fail("relative terrain range unsafe: [%.3f, %.3f]" % [min_height, max_height])
        return
    if max_height - min_height < 0.5:
        _fail("terrain is effectively flat")
        return
    if valid_samples <= 0:
        _fail("terrain has no valid DTM samples")
        return
    if valid_samples + invalid_samples != 257 * 257:
        _fail("DTM validity accounting mismatch")
        return
    if atomium_abs < 40.0 or atomium_abs > 90.0:
        _fail("Atomium absolute terrain elevation is implausible: %.3f" % atomium_abs)
        return
    if absf(atomium_height) > 1.0:
        _fail("Atomium local terrain should be near Y=0, got %.3f" % atomium_height)
        return

    var drape = scene.get_node_or_null("TerrainDrape")
    if drape == null:
        _fail("TerrainDrape node missing")
        return
    var road_vertices := int(drape.get("road_vertices_draped"))
    var building_vertices := int(drape.get("building_vertices_draped"))
    var tram_vertices := int(drape.get("tram_vertices_draped"))
    var train_vertices := int(drape.get("train_vertices_draped"))
    if road_vertices < 100:
        _fail("too few official road vertices draped: %d" % road_vertices)
        return
    if building_vertices < 100:
        _fail("too few official building vertices draped: %d" % building_vertices)
        return
    if tram_vertices < 4 or train_vertices < 4:
        _fail("official transit geometry was not draped: tram=%d train=%d" % [tram_vertices, train_vertices])
        return

    print("LAEKEN_TERRAIN_SMOKE_OK: range=[%.2f, %.2f]m atomium_local=%.3fm atomium_abs=%.3fm valid=%d holes=%d draped={roads:%d,buildings:%d,tram:%d,train:%d}" % [min_height, max_height, atomium_height, atomium_abs, valid_samples, invalid_samples, road_vertices, building_vertices, tram_vertices, train_vertices])
    scene.queue_free()
    await process_frame
    quit(0)
