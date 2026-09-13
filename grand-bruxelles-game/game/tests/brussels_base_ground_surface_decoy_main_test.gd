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

func _free_node(node: Node) -> void:
    if node == null or not is_instance_valid(node):
        return
    if node.get_parent() != null:
        node.get_parent().remove_child(node)
    node.free()

func _run() -> void:
    var runtime := root.get_node_or_null(TARGET_RUNTIME)
    if runtime == null:
        _fail("base-ground autoload missing")
        return
    if bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("runtime must begin dormant without production Main")
        return

    # An unrelated editor/test mount named Main must not poison the autoload.
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
    _free_node(decoy_main)
    await _wait_frames(2)

    # A canonical production scene under a tool/preview SubViewport is still non-authoritative.
    var viewport := SubViewport.new()
    viewport.name = "GroundNestedMountViewport"
    viewport.size = Vector2i(1280, 720)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var nested_main := MAIN_SCENE.instantiate()
    viewport.add_child(nested_main)

    await _wait_frames(20)
    if bool(runtime.call("ready_complete")):
        _fail("canonical Main under SubViewport was incorrectly accepted as authoritative")
        return
    if bool(runtime.call("failed")):
        _fail("non-authoritative canonical viewport mount permanently failed runtime")
        return
    var nested_ground := nested_main.get_node_or_null("Ground") as CSGBox3D
    if nested_ground == null:
        _fail("canonical viewport Ground missing")
        return
    if nested_ground.material != null:
        _fail("canonical viewport Ground received shared material despite lacking authority")
        return

    _free_node(viewport)
    await _wait_frames(2)

    # The same canonical packed scene remains eligible for the documented root fallback.
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(30):
        await process_frame
        if bool(runtime.call("ready_complete")):
            break
    if not bool(runtime.call("ready_complete")):
        _fail("runtime did not bind canonical root-level production Main")
        return
    if bool(runtime.call("failed")):
        _fail("runtime failed after canonical root-level production Main appeared")
        return
    if str(runtime.call("material_family")) != "brussels_base_ground_surface_v1":
        _fail("material family drifted after root-level bind")
        return
    if int(runtime.call("presentation_revision")) != 6:
        _fail("presentation revision drifted after root-level bind")
        return

    var ground := main.get_node_or_null("Ground") as CSGBox3D
    if ground == null or not ground.material is ShaderMaterial:
        _fail("canonical root-level Ground was not enhanced")
        return
    var material := ground.material as ShaderMaterial
    if str(material.get_meta("material_family", "")) != "brussels_base_ground_surface_v1":
        _fail("enhanced Ground material metadata missing")
        return
    if bool(material.get_meta("geometry_changed", true)) or bool(material.get_meta("collision_changed", true)):
        _fail("root-level binding changed Ground geometry/collision contract")
        return

    print("BRUSSELS_BASE_GROUND_SURFACE_DECOY_MAIN_OK: decoy_ignored=true canonical_viewport_rejected=true canonical_root_bound=true geometry_changed=false collision_changed=false")
    quit(0)
