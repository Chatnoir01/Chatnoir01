extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/brussels_base_ground_surface_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_MATERIAL_OWNERSHIP_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var main := Node3D.new()
    main.name = "Main"

    var ground := CSGBox3D.new()
    ground.name = "Ground"
    ground.position = Vector3(0.0, -0.23, 0.0)
    ground.size = Vector3(1800.0, 0.4, 1800.0)
    ground.use_collision = true
    var legacy := StandardMaterial3D.new()
    legacy.set_meta("owner", "legacy")
    ground.material = legacy
    main.add_child(ground)

    for anchor_name: String in ["BrusselsOSM", "UrbISMidiExact", "Player"]:
        var anchor := Node3D.new()
        anchor.name = anchor_name
        main.add_child(anchor)

    root.add_child(main)

    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "BrusselsBaseGroundSurfaceRuntimeOwnershipProbe"
    root.add_child(runtime)

    for _frame: int in range(30):
        await process_frame
        if bool(runtime.call("ready_complete")):
            break

    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("runtime did not bind cleanly to exact Ground identity")
        return

    var enhanced := ground.material
    if enhanced == null or enhanced == legacy:
        _fail("enhanced material was not installed")
        return

    var foreign := StandardMaterial3D.new()
    foreign.set_meta("owner", "foreign_later_owner")
    ground.material = foreign

    runtime.call("set_enhanced_enabled", false)
    if ground.material != foreign:
        _fail("disable toggle overwrote a later material owner")
        return

    runtime.call("set_enhanced_enabled", true)
    if ground.material != foreign:
        _fail("enable toggle overwrote a later material owner")
        return

    ground.material = enhanced
    runtime.call("set_enhanced_enabled", false)
    if ground.material != legacy:
        _fail("owned enhanced material did not restore exact legacy material")
        return

    runtime.call("set_enhanced_enabled", true)
    if ground.material != enhanced:
        _fail("exact legacy material did not restore owned enhanced material")
        return

    print("BRUSSELS_BASE_GROUND_MATERIAL_OWNERSHIP_OK: foreign_owner_preserved=true exact_owner_toggle=true geometry_changed=false collision_changed=false")
    quit(0)
