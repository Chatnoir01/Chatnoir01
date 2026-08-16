extends SceneTree

const ATOMIUM_X := 224.92615906274295
const ATOMIUM_Z := -6553.143077999353
const PRIMARY_DTM := "res://data/terrain/laeken_jette/phase1_dtm.game.json"
const ORTHO := "res://data/orthophoto/laeken_jette/phase1_ortho.jpg"


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

    var terrain_width := int(terrain.get("width"))
    var terrain_height := int(terrain.get("height"))
    var data_path := String(terrain.get("data_path_used"))
    var min_height := float(terrain.get("min_height_m"))
    var max_height := float(terrain.get("max_height_m"))
    var valid_samples := int(terrain.get("valid_sample_count"))
    var invalid_samples := int(terrain.get("invalid_sample_count"))
    var atomium_abs := float(terrain.get("atomium_absolute_elevation_m"))
    var atomium_height := float(terrain.call("sample_height", ATOMIUM_X, ATOMIUM_Z))

    if terrain_width < 2 or terrain_height < 2:
        _fail("invalid terrain dimensions: %dx%d" % [terrain_width, terrain_height])
        return
    if min_height < -60.0 or max_height > 70.0:
        _fail("relative terrain range unsafe: [%.3f, %.3f]" % [min_height, max_height])
        return
    if max_height - min_height < 0.5:
        _fail("terrain is effectively flat")
        return
    if valid_samples <= 0:
        _fail("terrain has no valid DTM samples")
        return
    if valid_samples + invalid_samples != terrain_width * terrain_height:
        _fail("DTM validity accounting mismatch: valid=%d holes=%d dimensions=%dx%d" % [valid_samples, invalid_samples, terrain_width, terrain_height])
        return
    if atomium_abs < 40.0 or atomium_abs > 90.0:
        _fail("Atomium absolute terrain elevation is implausible: %.3f" % atomium_abs)
        return
    if absf(atomium_height) > 1.0:
        _fail("Atomium local terrain should be near Y=0, got %.3f" % atomium_height)
        return
    if FileAccess.file_exists(PRIMARY_DTM):
        if data_path != PRIMARY_DTM:
            _fail("full phase-1 DTM exists but terrain did not select it: %s" % data_path)
            return
        if terrain_width != 360 or terrain_height != 620:
            _fail("full phase-1 DTM must be 360x620 at 5m, got %dx%d" % [terrain_width, terrain_height])
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

    var ortho_active := false
    if ResourceLoader.exists(ORTHO):
        var ortho = scene.get_node_or_null("OrthophotoPass")
        if ortho == null:
            _fail("orthophoto texture exists but OrthophotoPass node is missing")
            return
        ortho_active = bool(ortho.get("orthophoto_active"))
        if not ortho_active:
            _fail("official orthophoto texture exists but was not applied to terrain + roads")
            return
        var terrain_mesh := scene.get_node_or_null("LaekenTerrain/OfficialDTMTerrainMesh") as MeshInstance3D
        var roads_mesh := scene.get_node_or_null("OfficialStreetSurfaces") as MeshInstance3D
        if terrain_mesh == null or not terrain_mesh.material_override is ShaderMaterial:
            _fail("orthophoto terrain material override missing")
            return
        if roads_mesh == null or not roads_mesh.material_override is ShaderMaterial:
            _fail("orthophoto road material override missing")
            return

    print("LAEKEN_TERRAIN_SMOKE_OK: source=%s size=%dx%d range=[%.2f, %.2f]m atomium_local=%.3fm atomium_abs=%.3fm valid=%d holes=%d ortho=%s draped={roads:%d,buildings:%d,tram:%d,train:%d}" % [data_path, terrain_width, terrain_height, min_height, max_height, atomium_height, atomium_abs, valid_samples, invalid_samples, ortho_active, road_vertices, building_vertices, tram_vertices, train_vertices])
    scene.queue_free()
    await process_frame
    quit(0)
