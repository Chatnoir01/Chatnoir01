extends SceneTree

const HEIGHTS_PATH := "res://data/urbis/laeken_jette/building_heights_dsm.game.json"
const OVERRIDES_PATH := "res://data/urbis/laeken_jette/building_height_landmark_overrides.game.json"
const PALAIS5_OUTLINE_PATH := "res://data/sources/laeken_jette/palais5_osm_outline.game.json"
const MAX_READY_FRAMES := 90


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LAEKEN_BUILDING_HEIGHTS_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    for required in [HEIGHTS_PATH, OVERRIDES_PATH, PALAIS5_OUTLINE_PATH]:
        if not FileAccess.file_exists(required):
            _fail("required building-height data missing: %s" % required)
            return
    var packed := load("res://game/zones/laeken_jette/laeken_jette.tscn") as PackedScene
    if packed == null:
        _fail("Laeken scene failed to load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)

    var height_pass = scene.get_node_or_null("BuildingHeightPass")
    var bridge = scene.get_node_or_null("BuildingDSMMaterialBridge")
    if height_pass == null:
        _fail("BuildingHeightPass missing")
        return
    if bridge == null:
        _fail("BuildingDSMMaterialBridge missing")
        return

    var ready_frame := -1
    for frame_index in range(MAX_READY_FRAMES):
        if bool(height_pass.get("height_mesh_ready")) and bool(bridge.get("material_bridged")):
            ready_frame = frame_index
            break
        await process_frame
    if ready_frame < 0:
        _fail("DSM mesh/material did not become ready within %d frames; height_ready=%s material_bridged=%s" % [
            MAX_READY_FRAMES,
            bool(height_pass.get("height_mesh_ready")),
            bool(bridge.get("material_bridged")),
        ])
        return

    var derived := int(height_pass.get("derived_buildings"))
    var fallback := int(height_pass.get("fallback_buildings"))
    var corrected := int(height_pass.get("landmark_corrected_buildings"))
    var official_holes := int(height_pass.get("official_hole_rings"))
    var palais5_cutouts := int(height_pass.get("palais5_cutouts"))
    var roof_triangles := int(height_pass.get("hole_aware_roof_triangles"))
    var high := int(height_pass.get("high_quality"))
    var medium := int(height_pass.get("medium_quality"))
    var low := int(height_pass.get("low_quality"))
    var min_height := float(height_pass.get("derived_min_height_m"))
    var max_height := float(height_pass.get("derived_max_height_m"))

    if derived != 9163 or fallback != 355:
        _fail("building accounting mismatch: derived=%d fallback=%d" % [derived, fallback])
        return
    if corrected != 1:
        _fail("expected exactly one audited landmark-overlap correction, got %d" % corrected)
        return
    if official_holes < 14:
        _fail("official UrbIS interior rings were lost: holes=%d" % official_holes)
        return
    if palais5_cutouts != 1:
        _fail("Palais 5 must be cut from exactly one Expo aggregate polygon, got %d" % palais5_cutouts)
        return
    if roof_triangles <= 0:
        _fail("hole-aware roof triangulation emitted no triangles")
        return
    if high != 7357 or medium != 1136 or low != 670:
        _fail("source quality accounting changed: high=%d medium=%d low=%d" % [high, medium, low])
        return
    if min_height < 2.0 or max_height < 35.0 or max_height > 120.0:
        _fail("runtime height range implausible after landmark correction: [%.3f, %.3f]" % [min_height, max_height])
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
    if not dsm_mesh.material_override is ShaderMaterial:
        _fail("DSM mesh final ShaderMaterial missing")
        return

    print("LAEKEN_BUILDING_HEIGHTS_OK: ready_frame=%d derived=%d fallback=%d landmark_corrected=%d holes=%d palais5_cutouts=%d roof_triangles=%d quality={high:%d,medium:%d,low:%d} height=[%.2f,%.2f] mesh_vertical=%.2fm" % [ready_frame, derived, fallback, corrected, official_holes, palais5_cutouts, roof_triangles, high, medium, low, min_height, max_height, bounds.size.y])
    scene.queue_free()
    await process_frame
    quit(0)
