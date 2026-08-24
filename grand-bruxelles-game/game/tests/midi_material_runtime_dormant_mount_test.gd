extends SceneTree

const BLUE_RUNTIME := preload("res://game/scripts/midi_blue_stone_surface_runtime.gd")
const CONCRETE_RUNTIME := preload("res://game/scripts/midi_architectural_concrete_surface_runtime.gd")
const GLAZING_RUNTIME := preload("res://game/scripts/midi_architectural_glazing_surface_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_MATERIAL_DORMANT_MOUNT_FAIL: %s" % message)
    quit(1)

func _mesh(name_value: String) -> MeshInstance3D:
    var node := MeshInstance3D.new()
    node.name = name_value
    node.mesh = BoxMesh.new()
    return node

func _build_midi_hero() -> Node3D:
    var midi := Node3D.new()
    midi.name = "MidiHeroZone"

    var blue_group := Node3D.new()
    blue_group.name = "BlueStoneWitness"
    midi.add_child(blue_group)
    for index: int in range(3):
        var holder := Node3D.new()
        holder.name = "BlueHolder_%d" % index
        holder.add_child(_mesh("BlueStoneBase"))
        blue_group.add_child(holder)

    var concrete_group := Node3D.new()
    concrete_group.name = "ConcreteWitness"
    midi.add_child(concrete_group)
    concrete_group.add_child(_mesh("VerticalGlassTowerFrame"))
    concrete_group.add_child(_mesh("EntranceConcreteCanopy"))
    for index: int in range(36):
        concrete_group.add_child(_mesh("HorizontalBand_%d" % index))
        concrete_group.add_child(_mesh("VerticalMullion_%d" % index))

    var glazing_group := Node3D.new()
    glazing_group.name = "GlazingWitness"
    midi.add_child(glazing_group)
    glazing_group.add_child(_mesh("StationLongGlassBand"))
    glazing_group.add_child(_mesh("EntranceGlazing"))
    for index: int in range(169):
        glazing_group.add_child(_mesh("Window_%d" % index))
        glazing_group.add_child(_mesh("GroundOpening_%d" % index))
    return midi

func _run() -> void:
    var blue: Node = BLUE_RUNTIME.new()
    blue.name = "BlueRuntimeWitness"
    root.add_child(blue)
    var concrete: Node = CONCRETE_RUNTIME.new()
    concrete.name = "ConcreteRuntimeWitness"
    root.add_child(concrete)
    var glazing: Node = GLAZING_RUNTIME.new()
    glazing.name = "GlazingRuntimeWitness"
    root.add_child(glazing)

    for _frame: int in range(3):
        await process_frame

    for runtime: Node in [blue, concrete, glazing]:
        if bool(runtime.call("identity_failure")):
            _fail("runtime treated missing MidiHeroZone as identity failure: %s" % runtime.name)
            return
        if bool(runtime.call("ready_complete")):
            _fail("runtime completed before MidiHeroZone existed: %s" % runtime.name)
            return
        if not bool(runtime.call("awaiting_midi")):
            _fail("runtime is not dormant/awaiting MidiHeroZone: %s" % runtime.name)
            return

    var midi := _build_midi_hero()
    root.add_child(midi)
    for _frame: int in range(5):
        await process_frame

    var expected := {
        "BlueRuntimeWitness": 3,
        "ConcreteRuntimeWitness": 74,
        "GlazingRuntimeWitness": 340,
    }
    for runtime: Node in [blue, concrete, glazing]:
        if bool(runtime.call("identity_failure")):
            _fail("runtime failed after legitimate MidiHeroZone mount: %s" % runtime.name)
            return
        if not bool(runtime.call("ready_complete")):
            _fail("runtime did not complete after legitimate MidiHeroZone mount: %s" % runtime.name)
            return
        if bool(runtime.call("awaiting_midi")):
            _fail("runtime kept waiting after legitimate MidiHeroZone mount: %s" % runtime.name)
            return
        var count := int(runtime.call("applied_surface_count"))
        if count != int(expected[runtime.name]):
            _fail("runtime surface count mismatch for %s: %d" % [runtime.name, count])
            return

    print("MIDI_MATERIAL_DORMANT_MOUNT_OK: blue=3 concrete=74 glazing=340 off_zone_errors=0 event_driven=true")
    quit(0)
