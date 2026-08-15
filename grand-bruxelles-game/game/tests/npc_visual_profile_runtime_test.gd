extends SceneTree

var _failed := false

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    for _frame: int in range(8):
        await process_frame

    var visible_runtime := root.get_node_or_null("VisibleCityRuntime")
    if visible_runtime == null:
        _fail("VisibleCityRuntime autoload missing")
        return
    visible_runtime.call("ensure_zone_for_test", "midi")
    for _frame: int in range(6):
        await process_frame

    var civilians := get_nodes_in_group("behavioral_civilian")
    if civilians.size() < 2:
        _fail("need at least two production civilians")
        return

    var signatures: Dictionary = {}
    for civilian_value: Node in civilians:
        if not civilian_value is NpcAgent:
            continue
        var civilian := civilian_value as NpcAgent
        var visual := civilian.get_node_or_null("VisibleHumanoid")
        if visual == null:
            _fail("production civilian is missing VisibleHumanoid")
            return
        if not visual.has_method("visual_signature"):
            _fail("civilian visual does not expose its applied appearance profile")
            return
        var signature := str(visual.call("visual_signature"))
        if signature.is_empty():
            _fail("civilian visual signature must be non-empty")
            return
        signatures[signature] = true

        var pending: Array[Node] = [visual]
        var mesh_count := 0
        while not pending.is_empty():
            var node: Node = pending.pop_back()
            if node is MeshInstance3D:
                mesh_count += 1
                var mesh := (node as MeshInstance3D).mesh
                if mesh is BoxMesh or mesh is SphereMesh or mesh is CapsuleMesh or mesh is CylinderMesh or mesh is PrismMesh:
                    _fail("production civilian still uses an engine primitive mesh: %s" % mesh.get_class())
                    return
            for child: Node in node.get_children():
                pending.append(child)
        if mesh_count < 8:
            _fail("civilian visual is missing articulated production geometry")
            return

    if signatures.size() < 2:
        _fail("different civilian seeds must create visibly different appearance signatures")
        return

    print("NPC_VISUAL_PROFILE_RUNTIME_OK: civilians=%d signatures=%d primitive_meshes=0" % [civilians.size(), signatures.size()])
    quit(0)

func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error(message)
    print("NPC_VISUAL_PROFILE_RUNTIME_FAIL: %s" % message)
    quit(1)
