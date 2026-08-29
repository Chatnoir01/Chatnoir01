extends SceneTree

const EXPECTED_SURFACES := 3
const MAX_BIND_FRAMES := 240

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_BLUE_STONE_SCENE_REPLACEMENT_FAIL: %s" % message)
    quit(1)

func _collect_blue_stone(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D and node.name == "BlueStoneBase":
        out.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_blue_stone(child, out)

func _find_midi(scene: Node) -> Node:
    var midi := scene.get_node_or_null("MidiHeroZone")
    if midi == null:
        midi = scene.find_child("MidiHeroZone", true, false)
    return midi

func _wait_for_surface_count(scene: Node) -> Array[MeshInstance3D]:
    for _frame: int in range(MAX_BIND_FRAMES):
        var midi := _find_midi(scene)
        if midi != null:
            var targets: Array[MeshInstance3D] = []
            _collect_blue_stone(midi, targets)
            if targets.size() == EXPECTED_SURFACES:
                return targets
        await process_frame
    return []

func _wait_for_runtime_material(runtime: Node, targets: Array[MeshInstance3D]) -> bool:
    for _frame: int in range(MAX_BIND_FRAMES):
        var material := runtime.call("enhanced_material") as Material
        if material != null:
            var all_owned := true
            for target in targets:
                if not is_instance_valid(target) or target.material_override != material:
                    all_owned = false
                    break
            if all_owned:
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

    var runtime := root.get_node_or_null("MidiBlueStoneSurfaceRuntime")
    if runtime == null:
        _fail("MidiBlueStoneSurfaceRuntime autoload missing")
        return

    var first_targets := await _wait_for_surface_count(first_scene)
    if first_targets.size() != EXPECTED_SURFACES:
        _fail("first scene BlueStoneBase coverage mismatch")
        return
    if not await _wait_for_runtime_material(runtime, first_targets):
        _fail("first scene blue-stone material bind timed out")
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
    var replacement_targets := await _wait_for_surface_count(replacement_scene)
    if replacement_targets.size() != EXPECTED_SURFACES:
        _fail("replacement scene BlueStoneBase coverage mismatch")
        return

    if not await _wait_for_runtime_material(runtime, replacement_targets):
        _fail("replacement scene did not receive Midi blue-stone material from surviving autoload")
        return

    if int(runtime.call("applied_surface_count")) != EXPECTED_SURFACES:
        _fail("runtime surface registry did not converge to replacement scene")
        return

    print("MIDI_BLUE_STONE_SCENE_REPLACEMENT_OK: surfaces=%d autoload_rebind=true geometry_changed=false" % EXPECTED_SURFACES)
    quit(0)
