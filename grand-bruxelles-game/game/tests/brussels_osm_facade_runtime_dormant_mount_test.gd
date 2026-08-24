extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_FACADE_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _make_building() -> CSGPolygon3D:
    var building := CSGPolygon3D.new()
    building.name = "Building_DormantMountWitness"
    building.polygon = PackedVector2Array([
        Vector2(-2.0, 0.0),
        Vector2(2.0, 0.0),
        Vector2(2.0, 3.0),
        Vector2(-2.0, 3.0),
    ])
    building.depth = 0.25
    var legacy := StandardMaterial3D.new()
    legacy.albedo_color = Color(0.58, 0.54, 0.49, 1.0)
    legacy.roughness = 0.82
    building.material = legacy
    return building

func _run() -> void:
    var surface := root.get_node_or_null("BrusselsOsmFacadeSurfaceRuntime")
    var articulation := root.get_node_or_null("BrusselsOsmFacadeArticulationRuntime")
    if surface == null or articulation == null:
        _fail("required facade autoloads missing")
        return

    for _frame: int in range(245):
        await process_frame
    if bool(surface.call("failed")):
        _fail("surface runtime treated absent GeneratedBuildings as failure")
        return
    if bool(articulation.call("failed")):
        _fail("articulation runtime treated absent GeneratedBuildings as failure")
        return
    if bool(surface.call("ready_complete")) or bool(articulation.call("ready_complete")):
        _fail("facade runtime completed without a generic city mount")
        return

    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    root.add_child(osm)
    var buildings := Node3D.new()
    buildings.name = "GeneratedBuildings"
    osm.add_child(buildings)
    var building := _make_building()
    buildings.add_child(building)

    for _frame: int in range(12):
        await process_frame

    if bool(surface.call("failed")) or not bool(surface.call("ready_complete")):
        _fail("surface runtime did not bind after legitimate generic city mount")
        return
    if bool(articulation.call("failed")) or not bool(articulation.call("ready_complete")):
        _fail("articulation runtime did not bind after legitimate generic city mount")
        return
    if int(surface.call("applied_building_count")) != 1 or int(articulation.call("applied_building_count")) != 1:
        _fail("expected exactly one generic building in dormant-mount witness")
        return
    if not bool(surface.call("geometry_unchanged")) or not bool(articulation.call("geometry_unchanged")):
        _fail("facade runtime changed source-backed building geometry")
        return
    if str(building.get_meta("placement_provenance", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("surface placement provenance missing")
        return
    if str(building.get_meta("license", "")) != "ODbL-1.0":
        _fail("surface license provenance missing")
        return
    if bool(building.get_meta("building_material_claimed", true)):
        _fail("authored facade material was incorrectly claimed as source-backed")
        return

    print("BRUSSELS_OSM_FACADE_DORMANT_MOUNT_OK: buildings=1 off_zone_errors=0 event_driven=true geometry_changed=false source=OSM license=ODbL-1.0")
    quit(0)
