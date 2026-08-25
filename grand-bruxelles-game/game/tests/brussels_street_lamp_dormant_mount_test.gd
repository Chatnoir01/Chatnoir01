extends SceneTree

const EXPECTED_COUNT := 8
const EXPECTED_FAMILY := "brussels_street_lamp_v1"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_STREET_LAMP_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := root.get_node_or_null("BrusselsStreetLampRuntime")
    if runtime == null:
        _fail("BrusselsStreetLampRuntime autoload missing")
        return

    for _frame: int in range(185):
        await process_frame
    if bool(runtime.call("failed")):
        _fail("street lamp runtime treated absent production mount as failure")
        return
    if bool(runtime.call("ready_complete")):
        _fail("street lamp runtime completed without a legitimate production mount")
        return

    var viewport := SubViewport.new()
    viewport.name = "DormantStreetLampMountViewport"
    root.add_child(viewport)
    var main_mount := Node3D.new()
    main_mount.name = "Main"
    viewport.add_child(main_mount)
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    main_mount.add_child(osm)
    var midi := Node3D.new()
    midi.name = "UrbISMidiExact"
    main_mount.add_child(midi)

    for _frame: int in range(16):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame

    if bool(runtime.call("failed")) or not bool(runtime.call("ready_complete")):
        _fail("street lamp runtime did not bind after legitimate nested production mount")
        return
    if int(runtime.call("point_count")) != EXPECTED_COUNT:
        _fail("street lamp source point count drifted")
        return
    if int(runtime.call("collision_count")) != EXPECTED_COUNT:
        _fail("street lamp collision count drifted")
        return
    if int(runtime.call("visual_batch_count")) != 3:
        _fail("street lamp batch count drifted")
        return
    if str(runtime.call("asset_family")) != EXPECTED_FAMILY:
        _fail("street lamp asset family drifted")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("street lamp source placement contract changed")
        return
    if main_mount.get_node_or_null("BrusselsSourceBackedStreetLamps") == null:
        _fail("street lamp runtime mounted outside the legitimate Main scene")
        return

    print("BRUSSELS_STREET_LAMP_DORMANT_MOUNT_OK: points=%d collisions=%d batches=%d nested_mount=true dormant_absence=true source_positions_unchanged=true source=OSM license=ODbL-1.0" % [EXPECTED_COUNT, EXPECTED_COUNT, 3])
    quit(0)
