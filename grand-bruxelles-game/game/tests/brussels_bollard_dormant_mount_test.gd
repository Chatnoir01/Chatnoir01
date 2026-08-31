extends SceneTree

const EXPECTED_COUNT := 27
const EXPECTED_FAMILY := "brussels_bollard_v1"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BOLLARD_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _collision_state_matches(root_node: Node, expected_disabled: bool) -> bool:
    var collision_body := root_node.get_node_or_null("BollardCollisions")
    if collision_body == null:
        return false
    var count := 0
    for child: Node in collision_body.get_children():
        if child is CollisionShape3D:
            count += 1
            if (child as CollisionShape3D).disabled != expected_disabled:
                return false
    return count == EXPECTED_COUNT

func _run() -> void:
    var runtime := root.get_node_or_null("BrusselsBollardRuntime")
    if runtime == null:
        _fail("BrusselsBollardRuntime autoload missing")
        return

    for _frame: int in range(185):
        await process_frame
    if bool(runtime.call("failed")):
        _fail("bollard runtime treated absent production mount as failure")
        return
    if bool(runtime.call("ready_complete")):
        _fail("bollard runtime completed without a legitimate production mount")
        return

    # Disable before the legitimate mount exists. Newly created owned colliders must
    # inherit the same state instead of becoming invisible-but-solid.
    runtime.call("set_visual_enabled", false)
    if bool(runtime.call("visual_enabled")):
        _fail("bollard visual state did not retain pre-bind disabled state")
        return

    var viewport := SubViewport.new()
    viewport.name = "DormantBollardMountViewport"
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
        _fail("bollard runtime did not bind after legitimate nested production mount")
        return
    if int(runtime.call("point_count")) != EXPECTED_COUNT:
        _fail("bollard source point count drifted")
        return
    if int(runtime.call("collision_count")) != EXPECTED_COUNT:
        _fail("bollard collision count drifted")
        return
    if int(runtime.call("visual_batch_count")) != 2:
        _fail("bollard batch count drifted")
        return
    if str(runtime.call("asset_family")) != EXPECTED_FAMILY:
        _fail("bollard asset family drifted")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("bollard source placement contract changed")
        return
    var bollard_root := main_mount.get_node_or_null("BrusselsSourceBackedBollards")
    if bollard_root == null:
        _fail("bollard runtime mounted outside the legitimate Main scene")
        return

    if not _collision_state_matches(bollard_root, true):
        _fail("pre-bind hidden bollards retained active owned collisions")
        return

    runtime.call("set_visual_enabled", true)
    if not bool(runtime.call("visual_enabled")):
        _fail("bollard visual state did not enable")
        return
    if not _collision_state_matches(bollard_root, false):
        _fail("visible bollards did not restore owned collisions")
        return

    runtime.call("set_visual_enabled", false)
    if bool(runtime.call("visual_enabled")):
        _fail("bollard visual state did not disable")
        return
    if not _collision_state_matches(bollard_root, true):
        _fail("hidden bollards retained active owned collisions")
        return

    print("BRUSSELS_BOLLARD_DORMANT_MOUNT_OK: points=%d collisions=%d batches=%d nested_mount=true dormant_absence=true source_positions_unchanged=true visibility_collision_sync=true prebind_inheritance=true source=OSM license=ODbL-1.0" % [EXPECTED_COUNT, EXPECTED_COUNT, 2])
    quit(0)
