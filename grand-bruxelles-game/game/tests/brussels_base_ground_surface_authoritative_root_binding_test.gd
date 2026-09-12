extends SceneTree

const MATERIAL_FAMILY := "brussels_base_ground_surface_v1"
const EXPECTED_POSITION := Vector3(0.0, -0.23, 0.0)
const EXPECTED_SIZE := Vector3(1800.0, 0.4, 1800.0)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_BASE_GROUND_AUTHORITATIVE_ROOT_BIND_FAIL: %s" % message)
    quit(1)

func _make_anchor(name_value: String) -> Node3D:
    var node := Node3D.new()
    node.name = name_value
    return node

func _make_decoy_main() -> Node3D:
    var decoy := Node3D.new()
    decoy.name = "Main"

    var ground := CSGBox3D.new()
    ground.name = "Ground"
    ground.position = EXPECTED_POSITION
    ground.size = EXPECTED_SIZE
    ground.use_collision = true
    decoy.add_child(ground)

    decoy.add_child(_make_anchor("BrusselsOSM"))
    decoy.add_child(_make_anchor("UrbISMidiExact"))
    decoy.add_child(_make_anchor("Player"))
    return decoy

func _assert_decoy_rejected(runtime: Node, decoy: Node3D, label: String) -> bool:
    var ground := decoy.get_node("Ground") as CSGBox3D
    if ground.material != null:
        _fail("runtime applied shared ground material to non-canonical %s decoy" % label)
        return false
    if bool(runtime.call("ready_complete")):
        _fail("runtime completed binding against non-canonical %s decoy" % label)
        return false
    return true

func _free_node(node: Node) -> void:
    if node == null or not is_instance_valid(node):
        return
    if node.get_parent() != null:
        node.get_parent().remove_child(node)
    node.free()

func _run() -> void:
    var runtime := root.get_node_or_null("BrusselsBaseGroundSurfaceRuntime")
    if runtime == null:
        _fail("BrusselsBaseGroundSurfaceRuntime autoload missing")
        return

    var root_decoy := _make_decoy_main()
    root.add_child(root_decoy)

    var viewport_decoy_host := SubViewport.new()
    viewport_decoy_host.name = "EnvironmentToolViewport"
    root.add_child(viewport_decoy_host)
    var viewport_decoy := _make_decoy_main()
    viewport_decoy_host.add_child(viewport_decoy)

    for _frame: int in range(12):
        await process_frame

    if not _assert_decoy_rejected(runtime, root_decoy, "root-level"):
        return
    if not _assert_decoy_rejected(runtime, viewport_decoy, "viewport"):
        return

    _free_node(root_decoy)
    _free_node(viewport_decoy_host)
    await process_frame

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("canonical production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("canonical production main scene did not instantiate as Node3D")
        return
    root.add_child(scene)

    if str(scene.name) != "Main":
        _fail("canonical root identity drifted: %s" % str(scene.name))
        return
    if str(scene.scene_file_path) != "res://game/main.tscn":
        _fail("canonical scene identity drifted: %s" % str(scene.scene_file_path))
        return
    if current_scene != null:
        _fail("canonical fallback witness requires current_scene to remain null")
        return

    for _frame: int in range(20):
        await process_frame

    var production_ground := scene.get_node_or_null("Ground") as CSGBox3D
    if production_ground == null:
        _fail("canonical production Ground missing")
        return
    if production_ground.material == null:
        _fail("canonical root-instantiated Main did not receive shared ground material")
        return
    if str(production_ground.material.get_meta("material_family", "")) != MATERIAL_FAMILY:
        _fail("canonical Ground material family mismatch")
        return
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("runtime did not complete cleanly on canonical root-instantiated Main")
        return

    print("BRUSSELS_BASE_GROUND_AUTHORITATIVE_ROOT_BIND_OK: root_decoy_rejected=true viewport_decoy_rejected=true decoys_unmounted_before_canonical=true canonical_scene=true current_scene=null family=%s" % MATERIAL_FAMILY)
    quit(0)
