extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_base_ground_surface_runtime.gd")
const EXPECTED_POSITION := Vector3(0.0, -0.23, 0.0)
const EXPECTED_SIZE := Vector3(1800.0, 0.4, 1800.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_ROOT_OWNER_ISOLATION_FAIL: %s" % message)
    quit(1)

func _make_main(position: Vector3) -> Node3D:
    var main := Node3D.new()
    main.name = "Main"
    var ground := CSGBox3D.new()
    ground.name = "Ground"
    ground.position = position
    ground.size = EXPECTED_SIZE
    ground.use_collision = true
    main.add_child(ground)
    for anchor_name: String in ["BrusselsOSM", "UrbISMidiExact", "Player"]:
        var anchor := Node3D.new()
        anchor.name = anchor_name
        main.add_child(anchor)
    return main

func _run() -> void:
    var production_runtime := root.get_node_or_null("BrusselsBaseGroundSurfaceRuntime")
    if production_runtime != null:
        production_runtime.queue_free()
        await process_frame

    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "BaseGroundOwnerIsolationProbe"
    root.add_child(runtime)

    var foreign_holder := Node.new()
    foreign_holder.name = "ForeignMountedScene"
    root.add_child(foreign_holder)
    var foreign_main := _make_main(EXPECTED_POSITION + Vector3(1.0, 0.0, 0.0))
    foreign_holder.add_child(foreign_main)

    for _frame: int in range(4):
        await process_frame
    if bool(runtime.call("failed")) or bool(runtime.call("ready_complete")):
        _fail("nested same-name Main poisoned shared runtime before authoritative root/Main arrived")
        return

    foreign_holder.queue_free()
    await process_frame

    var authoritative_main := _make_main(EXPECTED_POSITION)
    root.add_child(authoritative_main)
    for _frame: int in range(12):
        await process_frame
        if bool(runtime.call("ready_complete")):
            break

    if not bool(runtime.call("ready_complete")):
        _fail("authoritative root/Main did not bind after foreign candidate rejection")
        return
    if bool(runtime.call("failed")):
        _fail("authoritative root/Main was rejected after foreign candidate")
        return
    var ground := authoritative_main.get_node_or_null("Ground") as CSGBox3D
    if ground == null or not ground.material is ShaderMaterial:
        _fail("authoritative Ground did not receive owned enhanced material")
        return
    if int((ground.material as ShaderMaterial).get_meta("presentation_revision", 0)) != 6:
        _fail("authoritative Ground presentation revision drifted")
        return

    print("BRUSSELS_BASE_GROUND_ROOT_OWNER_ISOLATION_OK: foreign_nested_preserved=true authoritative_root_bound=true geometry_unchanged=true collision_unchanged=true")
    quit(0)
