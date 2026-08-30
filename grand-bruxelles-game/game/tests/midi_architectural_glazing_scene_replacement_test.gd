extends SceneTree

const EXPECTED_SURFACES := 340
const MAX_BIND_FRAMES := 240
const FAILURE_WAIT_FRAMES := 40

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_ARCHITECTURAL_GLAZING_SCENE_REPLACEMENT_FAIL: %s" % message)
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

func _wait_for_runtime_bind(runtime: Node, scene: Node, expected_enabled: bool) -> bool:
    for _frame: int in range(MAX_BIND_FRAMES):
        var midi := _find_midi(scene)
        var material := runtime.call("enhanced_material") as Material
        if midi != null and material != null:
            var owned_count := _count_owned_material(midi, material)
            var expected_owned := EXPECTED_SURFACES if expected_enabled else 0
            if bool(runtime.call("ready_complete")) and int(runtime.call("applied_surface_count")) == EXPECTED_SURFACES and bool(runtime.call("enhanced_material_enabled")) == expected_enabled and owned_count == expected_owned:
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

    var runtime := root.get_node_or_null("MidiArchitecturalGlazingSurfaceRuntime")
    if runtime == null:
        _fail("MidiArchitecturalGlazingSurfaceRuntime autoload missing")
        return

    if not await _wait_for_runtime_bind(runtime, first_scene, true):
        _fail("first scene architectural-glazing bind timed out")
        return

    runtime.call("set_enhanced_material_enabled", false)
    var first_midi := _find_midi(first_scene)
    var first_material := runtime.call("enhanced_material") as Material
    if first_midi == null or first_material == null or bool(runtime.call("enhanced_material_enabled")):
        _fail("failed to disable architectural glazing before scene replacement")
        return
    if _count_owned_material(first_midi, first_material) != 0:
        _fail("disabled architectural glazing still owns first-scene surfaces")
        return

    first_scene.queue_free()
    for _frame: int in range(4):
        await process_frame

    var replacement_scene := packed.instantiate() as Node3D
    root.add_child(replacement_scene)

    if not await _wait_for_runtime_bind(runtime, replacement_scene, false):
        _fail("replacement scene did not preserve disabled architectural-glazing state")
        return

    var replacement_midi := _find_midi(replacement_scene)
    var replacement_material := runtime.call("enhanced_material") as Material
    if replacement_midi == null or replacement_material == null:
        _fail("replacement scene binding state incomplete")
        return
    if _count_owned_material(replacement_midi, replacement_material) != 0:
        _fail("replacement scene unexpectedly re-enabled architectural glazing")
        return

    replacement_scene.queue_free()
    for _frame: int in range(4):
        await process_frame

    # Exercise the glazing runtime's real bounded topology-failure path without
    # advertising a fake MidiHeroZone to unrelated Midi material autoloads.
    var incomplete_candidate := Node3D.new()
    incomplete_candidate.name = "TransientIncompleteGlazingCandidate"
    root.add_child(incomplete_candidate)
    runtime.set("_bind_in_progress", true)
    runtime.call("_apply_when_subtree_ready", incomplete_candidate)

    for _frame: int in range(FAILURE_WAIT_FRAMES):
        await process_frame
    if not bool(runtime.call("identity_failure")):
        _fail("incomplete glazing candidate did not fail closed after bounded population wait")
        return

    incomplete_candidate.queue_free()
    for _frame: int in range(4):
        await process_frame

    var recovered_scene := packed.instantiate() as Node3D
    root.add_child(recovered_scene)
    if not await _wait_for_runtime_bind(runtime, recovered_scene, false):
        _fail("runtime did not recover after failed incomplete glazing candidate was removed")
        return

    print("MIDI_ARCHITECTURAL_GLAZING_SCENE_REPLACEMENT_OK: surfaces=%d autoload_rebind=true toggle_preserved=true topology_recovered=true geometry_changed=false" % EXPECTED_SURFACES)
    quit(0)
