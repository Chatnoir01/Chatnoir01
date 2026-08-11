extends SceneTree

const HEIGHTS_PATH := "res://data/urbis/laeken_jette/building_heights_dsm.game.json"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_BUILDING_HEIGHTS_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    if not FileAccess.file_exists(HEIGHTS_PATH):
        _fail("committed DSM building-height data missing")
        return
    var packed := load("res://game/zones/laeken_jette/laeken_jette.tscn") as PackedScene
    if packed == null:
        _fail("Laeken scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _i in range(12):
        await process_frame

    var height_pass = scene.get_node_or_null("BuildingHeightPass")
    if height_pass == null:
        _fail("BuildingHeightPass missing")
        return
    if not bool(height_pass.get("height_mesh_ready")):
        _fail("DSM building replacement mesh did not finish")
        return

    var derived := int(height_pass.get("derived_buildings"))
    var fallback := int(height_pass.get("fallback_buildings"))
    var high := int(height_pass.get("high_quality"))
    var medium := int(height_pass.get("medium_quality"))
    var low := int(height_pass.get("low_quality"))
    var min_height := float(height_pass.get("derived_min_height_m"))
    var max_height := float(height_pass.get("derived_max_height_m"))

    if derived < 9000:
        _fail("too few DSM-derived buildings used: %d" % derived)
        return
    if fallback > 500:
        _fail("too many buildings fell back to 10.5 m: %d" % fallback)
        return
    if derived + fallback != 9518:
        _fail("building accounting mismatch: derived=%d fallback=%d" % [derived, fallback])
        return
    if high < 7000 or medium < 1000 or low < 500:
        _fail("unexpected quality distribution: high=%d medium=%d low=%d" % [high, medium, low])
        return
    if min_height < 2.0 or max_height < 40.0 or max_height > 120.0:
        _fail("DSM height range implausible: [%.3f, %.3f]" % [min_height, max_height])
        return

    var old_mesh := scene.get_node_or_null("OfficialBuildings") as MeshInstance3D
    var dsm_mesh := scene.get_node_or_null("OfficialBuildingsDSM") as MeshInstance3D
    if old_mesh == null or dsm_mesh == null:
        _fail("old or DSM building mesh missing")
        return
    if old_mesh.visible:
        _fail("uniform-height original building mesh is still visible")
        return
    if not dsm_mesh.visible:
        _fail("DSM building mesh is not visible")
        return
    if dsm_mesh.mesh == null or dsm_mesh.mesh.get_surface_count() == 0:
        _fail("DSM building mesh geometry missing")
        return
    var bounds := dsm_mesh.mesh.get_aabb()
    if bounds.size.y < 50.0:
        _fail("DSM building mesh still lacks meaningful vertical variation: AABB %.3fm" % bounds.size.y)
        return

    var bridge = scene.get_node_or_null("BuildingDSMMaterialBridge")
    if bridge == null or not bool(bridge.get("material_bridged")):
        _fail("validated facade/roof material was not bridged to DSM mesh")
        return
    if not dsm_mesh.material_override is ShaderMaterial:
        _fail("DSM mesh final ShaderMaterial missing")
        return

    print("LAEKEN_BUILDING_HEIGHTS_OK: derived=%d fallback=%d quality={high:%d,medium:%d,low:%d} height=[%.2f,%.2f] mesh_vertical=%.2fm" % [derived, fallback, high, medium, low, min_height, max_height, bounds.size.y])
    scene.queue_free()
    await process_frame
    quit(0)
