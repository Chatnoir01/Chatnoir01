extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const TARGET_RUNTIME := "BrusselsBaseGroundSurfaceRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_SURFACE_DECOY_MAIN_FAIL: %s" % message)
    quit(1)

func _wait_frames(count: int) -> void:
    for _frame: int in range(count):
        await process_frame

func _run() -> void:
    var runtime := root.get_node_or_null(TARGET_RUNTIME)
    if runtime == null:
        _fail("base-ground autoload missing")
        return
    if bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("runtime must begin dormant without production Main")
        return

    # RED regression: an unrelated editor/test mount named Main must not poison the autoload.
    var decoy_main := Node3D.new()
    decoy_main.name = "Main"
    root.add_child(decoy_main)
    var decoy_ground := Node3D.new()
    decoy_ground.name = "Ground"
    decoy_main.add_child(decoy_ground)
    await _wait_frames(4)
    if bool(runtime.call("failed")):
        _fail("decoy Main permanently failed production runtime")
        return
    if bool(runtime.call("ready_complete")):
        _fail("decoy Main was incorrectly accepted as production Main")
        return
    decoy_main.queue_free()
    await _wait_frames(2)

    # Legitimate production scene may be nested under a SubViewport with current_scene == null.
    var viewport := SubViewport.new()
    viewport.name = "GroundNestedMountViewport"
    viewport.size = Vector2i(1280, 720)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var main := MAIN_SCENE.instantiate()
    viewport.add_child(main)

    for _frame: int in range(30):
        await process_frame
        if bool(runtime.call("ready_complete")):
            break
    if not bool(runtime.call("ready_complete")):
        _fail("runtime did not bind legitimate nested production Main")
        return
    if bool(runtime.call("failed")):
        _fail("runtime failed after legitimate nested production Main appeared")
        return
    if str(runtime.call("material_family")) != "brussels_base_ground_surface_v1":
        _fail("material family drifted after nested bind")
        return
    if int(runtime.call("presentation_revision")) != 6:
        _fail("presentation revision drifted after nested bind")
        return

    var ground := main.get_node_or_null("Ground") as CSGBox3D
    if ground == null or not ground.material is ShaderMaterial:
        _fail("legitimate Ground was not enhanced after nested bind")
        return
    var material := ground.material as ShaderMaterial
    if str(material.get_meta("material_family", "")) != "brussels_base_ground_surface_v1":
        _fail("enhanced Ground material metadata missing")
        return
    if bool(material.get_meta("geometry_changed", true)) or bool(material.get_meta("collision_changed", true)):
        _fail("nested binding changed Ground geometry/collision contract")
        return

    print("BRUSSELS_BASE_GROUND_SURFACE_DECOY_MAIN_OK: decoy_ignored=true nested_main_bound=true geometry_changed=false collision_changed=false")
    quit(0)
