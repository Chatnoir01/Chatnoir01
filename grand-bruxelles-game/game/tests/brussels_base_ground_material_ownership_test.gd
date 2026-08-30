extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_MATERIAL_OWNERSHIP_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var runtime := root.get_node_or_null("BrusselsBaseGroundSurfaceRuntime")
    if runtime == null:
        _fail("canonical BrusselsBaseGroundSurfaceRuntime autoload missing")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)

    for _frame: int in range(180):
        await process_frame
        if bool(runtime.call("ready_complete")):
            break

    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("canonical runtime did not bind cleanly to production Main/Ground identity")
        return

    var ground := main.get_node_or_null("Ground") as CSGBox3D
    if ground == null:
        _fail("production Ground missing")
        return

    var enhanced := ground.material
    if not enhanced is ShaderMaterial:
        _fail("canonical enhanced material was not installed")
        return

    runtime.call("set_enhanced_enabled", false)
    var legacy := ground.material
    if legacy == null or legacy == enhanced:
        _fail("canonical runtime did not expose its captured legacy material")
        return

    runtime.call("set_enhanced_enabled", true)
    if ground.material != enhanced:
        _fail("canonical owned legacy material did not restore enhanced material")
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
        _fail("owned enhanced material did not restore exact captured legacy material")
        return

    runtime.call("set_enhanced_enabled", true)
    if ground.material != enhanced:
        _fail("exact captured legacy material did not restore owned enhanced material")
        return

    print("BRUSSELS_BASE_GROUND_MATERIAL_OWNERSHIP_OK: canonical_autoload=true production_main=true foreign_owner_preserved=true exact_owner_toggle=true geometry_changed=false collision_changed=false")
    quit(0)
