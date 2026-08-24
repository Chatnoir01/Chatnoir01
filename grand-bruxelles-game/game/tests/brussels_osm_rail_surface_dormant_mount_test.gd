extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_RAIL_SURFACE_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _make_rail(name_value: String) -> CSGBox3D:
    var rail := CSGBox3D.new()
    rail.name = name_value
    rail.size = Vector3(0.11, 0.08, 8.0)
    var legacy := StandardMaterial3D.new()
    legacy.albedo_color = Color(0.28, 0.29, 0.30, 1.0)
    legacy.metallic = 0.7
    legacy.roughness = 0.45
    rail.material = legacy
    return rail

func _assert_bound_rail(rail: CSGBox3D, label: String) -> bool:
    var material := rail.material
    if material == null or str(material.get_meta("material_family", "")) != "brussels_osm_rail_surface_v1":
        _fail("shared rail material was not applied to %s" % label)
        return false
    if str(rail.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("rail source provenance missing for %s" % label)
        return false
    if str(rail.get_meta("license", "")) != "ODbL-1.0":
        _fail("rail license provenance missing for %s" % label)
        return false
    if bool(rail.get_meta("geometry_changed_by_rail_surface_runtime", true)):
        _fail("rail runtime changed geometry for %s" % label)
        return false
    return true

func _run() -> void:
    var runtime := root.get_node_or_null("BrusselsOsmRailSurfaceRuntime")
    if runtime == null:
        _fail("BrusselsOsmRailSurfaceRuntime autoload missing")
        return

    for _frame: int in range(185):
        await process_frame
    if bool(runtime.call("failed")):
        _fail("rail surface runtime treated absent GeneratedRails as failure")
        return
    if bool(runtime.call("ready_complete")):
        _fail("rail surface runtime completed without a generic rail mount")
        return

    var viewport := SubViewport.new()
    viewport.name = "DormantRailMountViewport"
    root.add_child(viewport)
    var main_mount := Node3D.new()
    main_mount.name = "Main"
    viewport.add_child(main_mount)
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    main_mount.add_child(osm)
    var rails_root := Node3D.new()
    rails_root.name = "GeneratedRails"
    osm.add_child(rails_root)

    var first_rail := _make_rail("Rail_359177328_0_0")
    rails_root.add_child(first_rail)
    for _frame: int in range(12):
        await process_frame

    if bool(runtime.call("failed")) or not bool(runtime.call("ready_complete")):
        _fail("rail surface runtime did not bind after legitimate nested rail mount")
        return
    if int(runtime.call("applied_rail_count")) != 1:
        _fail("expected exactly one rail after initial dormant-mount bind")
        return
    if not _assert_bound_rail(first_rail, "initial rail"):
        return

    var late_rail := _make_rail("Rail_359177328_0_1")
    rails_root.add_child(late_rail)
    for _frame: int in range(12):
        await process_frame

    if bool(runtime.call("failed")):
        _fail("rail surface runtime failed while binding a late rail")
        return
    if int(runtime.call("applied_rail_count")) != 2:
        _fail("late rail was ignored after ready_complete")
        return
    if not _assert_bound_rail(late_rail, "late rail"):
        return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("rail geometry changed during lifecycle bind")
        return

    print("BRUSSELS_OSM_RAIL_SURFACE_DORMANT_MOUNT_OK: rails=2 off_zone_errors=0 nested_mount=true event_driven=true incremental_bind=true geometry_changed=false source=OSM license=ODbL-1.0")
    quit(0)
