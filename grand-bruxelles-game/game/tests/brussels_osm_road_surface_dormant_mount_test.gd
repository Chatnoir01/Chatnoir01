extends SceneTree

const ROAD_ID := 359177328

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ROAD_SURFACE_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _make_road(segment_index: int) -> CSGBox3D:
    var road := CSGBox3D.new()
    road.name = "Road_%d_0_%d" % [ROAD_ID, segment_index]
    road.size = Vector3(8.0, 0.15, 2.0)
    var legacy := StandardMaterial3D.new()
    legacy.albedo_color = Color(0.12, 0.12, 0.12, 1.0)
    legacy.roughness = 0.9
    road.material = legacy
    return road

func _make_official_surface() -> MeshInstance3D:
    var surface := MeshInstance3D.new()
    surface.name = "StreetSurfaces_S"
    var legacy := StandardMaterial3D.new()
    legacy.albedo_color = Color(0.18, 0.18, 0.18, 1.0)
    legacy.roughness = 0.92
    surface.material_override = legacy
    return surface

func _assert_bound_road(road: CSGBox3D, label: String) -> bool:
    var material := road.material
    if material == null or str(material.get_meta("material_family", "")) != "brussels_osm_road_surface_v1":
        _fail("shared road material was not applied to %s" % label)
        return false
    if int(road.get_meta("osm_id", 0)) != ROAD_ID:
        _fail("road source identity was not preserved for %s" % label)
        return false
    if str(road.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API" or str(road.get_meta("license", "")) != "ODbL-1.0":
        _fail("road provenance missing after nested bind for %s" % label)
        return false
    if bool(road.get_meta("geometry_changed_by_road_surface_runtime", true)):
        _fail("road surface runtime changed source-backed geometry for %s" % label)
        return false
    return true

func _run() -> void:
    var runtime := root.get_node_or_null("BrusselsOsmRoadSurfaceRuntime")
    if runtime == null:
        _fail("BrusselsOsmRoadSurfaceRuntime autoload missing")
        return

    for _frame: int in range(185):
        await process_frame
    if bool(runtime.call("failed")):
        _fail("road surface runtime treated absent GeneratedRoads as failure")
        return
    if bool(runtime.call("ready_complete")):
        _fail("road surface runtime completed without a generic road mount")
        return

    var viewport := SubViewport.new()
    viewport.name = "DormantRoadMountViewport"
    root.add_child(viewport)
    var main_mount := Node3D.new()
    main_mount.name = "Main"
    viewport.add_child(main_mount)
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    main_mount.add_child(osm)
    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    osm.add_child(roads)
    var first_road := _make_road(0)
    roads.add_child(first_road)

    for _frame: int in range(12):
        await process_frame

    if bool(runtime.call("failed")) or not bool(runtime.call("ready_complete")):
        _fail("road surface runtime did not bind after legitimate nested road mount")
        return
    if int(runtime.call("applied_road_count")) != 1:
        _fail("expected exactly one road after initial dormant-mount bind")
        return
    if not _assert_bound_road(first_road, "initial road"):
        return

    # Regression: GeneratedRoads can populate incrementally after the runtime has
    # completed its first valid bind. Late source-backed segments must join the
    # same material/provenance contract instead of being ignored.
    var late_road := _make_road(1)
    roads.add_child(late_road)
    for _frame: int in range(12):
        await process_frame

    if bool(runtime.call("failed")):
        _fail("road surface runtime failed while binding a late road segment")
        return
    if int(runtime.call("applied_road_count")) != 2:
        _fail("late road segment was ignored after ready_complete")
        return
    if not _assert_bound_road(late_road, "late road"):
        return

    # Ownership regression: after this runtime has bound a surface, another
    # legitimate owner may replace its presentation material. Enhanced toggles
    # must never steal that third-party material back.
    var official_parent := Node3D.new()
    official_parent.name = "OfficialIxellesStreetSurfaces"
    main_mount.add_child(official_parent)
    var official_surface := _make_official_surface()
    official_parent.add_child(official_surface)
    for _frame: int in range(8):
        await process_frame
    if int(runtime.call("official_applied_road_count")) != 1:
        _fail("official UrbIS road surface did not bind for ownership regression")
        return

    var foreign_osm := StandardMaterial3D.new()
    foreign_osm.albedo_color = Color(0.91, 0.19, 0.37, 1.0)
    var foreign_official := StandardMaterial3D.new()
    foreign_official.albedo_color = Color(0.17, 0.63, 0.91, 1.0)
    first_road.material = foreign_osm
    official_surface.material_override = foreign_official

    runtime.call("set_enhanced_enabled", false)
    if first_road.material != foreign_osm:
        _fail("OSM disable overwrote a foreign road material")
        return
    if official_surface.material_override != foreign_official:
        _fail("official disable overwrote a foreign road material")
        return

    runtime.call("set_enhanced_enabled", true)
    if first_road.material != foreign_osm:
        _fail("OSM re-enable stole material ownership from another runtime")
        return
    if official_surface.material_override != foreign_official:
        _fail("official re-enable stole material ownership from another runtime")
        return
    if str(official_surface.get_meta("ground_network_presentation_family", "")) != "":
        _fail("official foreign material retained stale shared presentation ownership metadata")
        return

    print("BRUSSELS_OSM_ROAD_SURFACE_DORMANT_MOUNT_OK: roads=2 official=1 off_zone_errors=0 nested_mount=true event_driven=true incremental_bind=true foreign_material_isolation=true geometry_changed=false source=OSM license=ODbL-1.0")
    quit(0)
