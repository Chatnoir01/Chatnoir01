extends SceneTree

const EXPECTED_COUNT := 8
const EXPECTED_FAMILY := "brussels_street_lamp_v1"
const OWNED_COLLISION_META := "owner_runtime"
const OWNED_COLLISION_ID := "BrusselsStreetLampRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_STREET_LAMP_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _owned_colliders(collision_body: StaticBody3D) -> Array[CollisionShape3D]:
    var result: Array[CollisionShape3D] = []
    for child: Node in collision_body.get_children():
        if child is CollisionShape3D and str(child.get_meta(OWNED_COLLISION_META, "")) == OWNED_COLLISION_ID:
            result.append(child as CollisionShape3D)
    return result

func _expect_owned_collision_state(collision_body: StaticBody3D, disabled: bool, label: String) -> bool:
    var owned := _owned_colliders(collision_body)
    if owned.size() != EXPECTED_COUNT:
        _fail("%s owned street lamp collision count drifted: %d" % [label, owned.size()])
        return false
    for collider: CollisionShape3D in owned:
        if collider.disabled != disabled:
            _fail("%s owned street lamp collision visibility state drifted for %s" % [label, collider.name])
            return false
    return true

func _expect_visual_state(lamp_root: Node3D, visible: bool, label: String) -> bool:
    for batch_name: String in ["StreetLampPoles", "StreetLampArms", "StreetLampLuminaires"]:
        var batch := lamp_root.get_node_or_null(batch_name) as MultiMeshInstance3D
        if batch == null:
            _fail("%s missing visual batch %s" % [label, batch_name])
            return false
        if batch.visible != visible:
            _fail("%s visual batch %s visibility drifted" % [label, batch_name])
            return false
    return true

func _run() -> void:
    var runtime := root.get_node_or_null("BrusselsStreetLampRuntime")
    if runtime == null:
        _fail("BrusselsStreetLampRuntime autoload missing")
        return

    runtime.call("set_visual_enabled", false)

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

    var lamp_root := main_mount.get_node_or_null("BrusselsSourceBackedStreetLamps") as Node3D
    if lamp_root == null:
        _fail("street lamp runtime mounted outside the legitimate Main scene")
        return
    var collision_body := lamp_root.get_node_or_null("StreetLampCollisions") as StaticBody3D
    if collision_body == null:
        _fail("street lamp collision owner body missing")
        return

    if not _expect_visual_state(lamp_root, false, "prebind_off"):
        return
    if not _expect_owned_collision_state(collision_body, true, "prebind_off"):
        return

    var foreign := CollisionShape3D.new()
    foreign.name = "ForeignStreetLampCollision"
    foreign.shape = BoxShape3D.new()
    foreign.disabled = false
    collision_body.add_child(foreign)

    runtime.call("set_visual_enabled", true)
    if not _expect_visual_state(lamp_root, true, "enabled"):
        return
    if not _expect_owned_collision_state(collision_body, false, "enabled"):
        return
    if foreign.disabled:
        _fail("enabled toggle mutated foreign collision")
        return

    runtime.call("set_visual_enabled", false)
    if not _expect_visual_state(lamp_root, false, "disabled"):
        return
    if not _expect_owned_collision_state(collision_body, true, "disabled"):
        return
    if foreign.disabled:
        _fail("disabled toggle mutated foreign collision")
        return
    if int(runtime.call("collision_count")) != EXPECTED_COUNT:
        _fail("foreign collision polluted owned collision count")
        return
    if not bool(runtime.call("source_positions_unchanged")):
        _fail("foreign collision polluted source placement contract")
        return

    print("BRUSSELS_STREET_LAMP_DORMANT_MOUNT_OK: points=%d collisions=%d batches=%d nested_mount=true dormant_absence=true source_positions_unchanged=true visibility_collision_sync=true prebind_inheritance=true foreign_collision_isolation=true source=OSM license=ODbL-1.0" % [EXPECTED_COUNT, EXPECTED_COUNT, 3])
    quit(0)
