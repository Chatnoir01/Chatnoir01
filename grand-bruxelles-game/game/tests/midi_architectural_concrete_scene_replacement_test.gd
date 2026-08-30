extends SceneTree

const EXPECTED_SURFACES := 74
const MAX_BIND_FRAMES := 240

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_ARCHITECTURAL_CONCRETE_SCENE_REPLACEMENT_FAIL: %s" % message)
    quit(1)

func _find_midi(scene: Node) -> Node:
    var midi := scene.get_node_or_null("MidiHeroZone")
    if midi == null:
        midi = scene.find_child("MidiHeroZone", true, false)
    return midi

func _count_owned_material(node: Node, material: Material) -> int:
    var count := 0
    if node is MeshInstance3D and (node as MeshInstance3D).material_override == material:
        count += 1
    for child in node.get_children():
        count += _count_owned_material(child, material)
    return count

func _wait_for_runtime_bind(runtime: Node, scene: Node) -> bool:
    for _frame: int in range(MAX_BIND_FRAMES):
        var midi := _find_midi(scene)
        var material := runtime.call("enhanced_material") as Material
        if midi != null and material != null:
            var owned_count := _count_owned_material(midi, material)
            if bool(runtime.call("ready_complete")) and int(runtime.call("applied_surface_count")) == EXPECTED_SURFACES and owned_count == EXPECTED_SURFACES:
                return true
        await process_frame
    return false

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return

    var first_scene := packed.instantiate() as Node3D
    root.add_child(first_scene)

    var runtime := root.get_node_or_null("MidiArchitecturalConcreteSurfaceRuntime")
    if runtime == null:
        _fail("MidiArchitecturalConcreteSurfaceRuntime autoload missing")
        return

    if not await _wait_for_runtime_bind(runtime, first_scene):
        _fail("first scene architectural-concrete bind timed out")
        return

    var first_material := runtime.call("enhanced_material") as Material
    if first_material == null:
        _fail("first scene enhanced material missing")
        return

    first_scene.queue_free()
    for _frame: int in range(4):
        await process_frame

    var replacement_scene := packed.instantiate() as Node3D
    root.add_child(replacement_scene)

    if not await _wait_for_runtime_bind(runtime, replacement_scene):
        _fail("replacement scene did not receive architectural-concrete material from surviving autoload")
        return

    var replacement_midi := _find_midi(replacement_scene)
    var replacement_material := runtime.call("enhanced_material") as Material
    if replacement_midi == null or replacement_material == null:
        _fail("replacement scene binding state incomplete")
        return
    if _count_owned_material(replacement_midi, replacement_material) != EXPECTED_SURFACES:
        _fail("replacement scene concrete ownership coverage drifted")
        return

    print("MIDI_ARCHITECTURAL_CONCRETE_SCENE_REPLACEMENT_OK: surfaces=%d autoload_rebind=true geometry_changed=false" % EXPECTED_SURFACES)
    quit(0)
