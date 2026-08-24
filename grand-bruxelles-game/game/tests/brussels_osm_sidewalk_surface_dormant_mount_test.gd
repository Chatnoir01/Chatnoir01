extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SIDEWALK_SURFACE_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _make_sidewalk(name_value: String, width: float) -> CSGBox3D:
    var sidewalk := CSGBox3D.new()
    sidewalk.name = name_value
    sidewalk.size = Vector3(width, 0.12, 8.0)
    var legacy := StandardMaterial3D.new()
    legacy.albedo_color = Color(0.45, 0.45, 0.45, 1.0)
    legacy.roughness = 0.95
    sidewalk.material = legacy
    return sidewalk

func _assert_bound_sidewalk(sidewalk: CSGBox3D, label: String) -> bool:
    var material := sidewalk.material
    if material == null or str(material.get_meta("material_family", "")) != "brussels_osm_sidewalk_surface_v1":
        _fail("shared sidewalk material was not applied to %s" % label)
        return false
    if str(sidewalk.get_meta("environment_role", "")) != "generated_osm_sidewalk":
        _fail("sidewalk environment role missing for %s" % label)
        return false
    if str(sidewalk.get_meta("placement_provenance", "")) != "adjacent_to_existing_osm_road_runtime_convention":
        _fail("sidewalk placement provenance missing for %s" % label)
        return false
    if bool(sidewalk.get_meta("surface_composition_claimed", true)):
        _fail("sidewalk composition was incorrectly claimed for %s" % label)
        return false
    if bool(sidewalk.get_meta("geometry_changed_by_sidewalk_surface_runtime", true)):
        _fail("sidewalk runtime changed geometry for %s" % label)
        return false
    return true

func _run() -> void:
    var runtime := root.get_node_or_null("BrusselsOsmSidewalkSurfaceRuntime")
    if runtime == null:
        _fail("BrusselsOsmSidewalkSurfaceRuntime autoload missing")
        return

    for _frame: int in range(185):
        await process_frame
    if bool(runtime.call("failed")):
        _fail("sidewalk surface runtime treated absent GeneratedRoads as failure")
        return
    if bool(runtime.call("ready_complete")):
        _fail("sidewalk surface runtime completed without a generic sidewalk mount")
        return

    var viewport := SubViewport.new()
    viewport.name = "DormantSidewalkMountViewport"
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

    var first_sidewalk := _make_sidewalk("Sidewalk_359177328_0_left", 1.85)
    roads.add_child(first_sidewalk)
    for _frame: int in range(12):
        await process_frame

    if bool(runtime.call("failed")) or not bool(runtime.call("ready_complete")):
        _fail("sidewalk surface runtime did not bind after legitimate nested sidewalk mount")
        return
    if int(runtime.call("applied_sidewalk_count")) != 1:
        _fail("expected exactly one sidewalk after initial dormant-mount bind")
        return
    if not _assert_bound_sidewalk(first_sidewalk, "initial sidewalk"):
        return

    var late_sidewalk := _make_sidewalk("Sidewalk_359177328_1_right", 2.55)
    roads.add_child(late_sidewalk)
    for _frame: int in range(12):
        await process_frame

    if bool(runtime.call("failed")):
        _fail("sidewalk surface runtime failed while binding a late sidewalk")
        return
    if int(runtime.call("applied_sidewalk_count")) != 2:
        _fail("late sidewalk was ignored after ready_complete")
        return
    if not _assert_bound_sidewalk(late_sidewalk, "late sidewalk"):
        return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("sidewalk geometry changed during lifecycle bind")
        return

    print("BRUSSELS_OSM_SIDEWALK_SURFACE_DORMANT_MOUNT_OK: sidewalks=2 off_zone_errors=0 nested_mount=true event_driven=true incremental_bind=true geometry_changed=false source=OSM-adjacent license=ODbL-1.0")
    quit(0)
