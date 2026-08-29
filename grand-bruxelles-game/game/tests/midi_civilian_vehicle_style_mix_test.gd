extends SceneTree

const VISUAL_SCRIPT := preload("res://game/scripts/civilian_vehicle_visual.gd")
const RUNTIME_NAME := "MidiCivilianVehicleStyleMixRuntime"
const CONTRACT := "midi_civilian_vehicle_style_mix_v1"
const MIX_VISUAL_NAME := "ProductionVisualStyleMix"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MIDI_CIVILIAN_VEHICLE_STYLE_MIX_FAIL: %s" % message)
    quit(1)


func _make_vehicle(parent: Node3D, name_value: String, paint: Color) -> Node3D:
    var vehicle := Node3D.new()
    vehicle.name = name_value
    var source := VISUAL_SCRIPT.new()
    source.name = "ProductionVisual"
    source.set("paint_color", paint)
    source.set("body_style", 0)
    vehicle.add_child(source)
    parent.add_child(vehicle)
    return vehicle


func _mix_child_count(vehicle: Node3D) -> int:
    var count := 0
    for child: Node in vehicle.get_children():
        if str(child.name) == MIX_VISUAL_NAME:
            count += 1
    return count


func _run() -> void:
    var runtime: Node = null
    for _frame: int in range(30):
        runtime = root.get_node_or_null(RUNTIME_NAME)
        if runtime != null:
            break
        await process_frame
    if runtime == null:
        _fail("bootstrap did not load %s" % RUNTIME_NAME)
        return
    if not runtime.has_method("get_contract"):
        _fail("runtime contract API missing")
        return

    var contract: Dictionary = runtime.call("get_contract")
    if str(contract.get("schema", "")) != CONTRACT:
        _fail("wrong contract schema")
        return
    if int(contract.get("style_count", 0)) != 3:
        _fail("expected exactly three existing production body styles")
        return
    if not bool(contract.get("movement_owner_unchanged", false)):
        _fail("movement ownership must remain unchanged")
        return
    if not bool(contract.get("collision_owner_unchanged", false)):
        _fail("collision ownership must remain unchanged")
        return
    if not bool(contract.get("geography_unchanged", false)):
        _fail("geography must remain unchanged")
        return

    var midi := Node3D.new()
    midi.name = "MidiUrbanLife"
    root.add_child(midi)

    var paint0 := Color(0.11, 0.18, 0.27, 1.0)
    var paint1 := Color(0.31, 0.075, 0.055, 1.0)
    var paint2 := Color(0.62, 0.62, 0.59, 1.0)
    var sedan := _make_vehicle(midi, "ParkedCar_00", paint0)
    var hatch := _make_vehicle(midi, "ParkedCar_01", paint1)
    var wagon := _make_vehicle(midi, "AmbientTraffic_02", paint2)

    for _frame: int in range(6):
        await process_frame

    if int(sedan.get_meta("midi_vehicle_style", -1)) != 0:
        _fail("ParkedCar_00 should keep sedan style")
        return
    var sedan_source := sedan.get_node_or_null("ProductionVisual") as Node3D
    if sedan_source == null or not sedan_source.visible:
        _fail("style 0 should keep the original production visual visible")
        return
    if sedan.get_node_or_null(MIX_VISUAL_NAME) != null:
        _fail("style 0 should not allocate a replacement visual")
        return

    var vehicles: Array[Node3D] = [hatch, wagon]
    var styles: Array[int] = [1, 2]
    var paints: Array[Color] = [paint1, paint2]
    for index: int in range(vehicles.size()):
        var vehicle: Node3D = vehicles[index]
        var expected_style: int = styles[index]
        var expected_paint: Color = paints[index]
        var source := vehicle.get_node_or_null("ProductionVisual") as Node3D
        var replacement := vehicle.get_node_or_null(MIX_VISUAL_NAME) as Node3D
        if source == null or source.visible:
            _fail("%s original sedan should be hidden" % str(vehicle.name))
            return
        if replacement == null or replacement.get_script() != VISUAL_SCRIPT:
            _fail("%s replacement visual missing" % str(vehicle.name))
            return
        if int(replacement.get("body_style")) != expected_style:
            _fail("%s wrong replacement body style" % str(vehicle.name))
            return
        var actual_paint: Color = replacement.get("paint_color")
        if actual_paint != expected_paint:
            _fail("%s paint not preserved" % str(vehicle.name))
            return
        if int(vehicle.get_meta("midi_vehicle_style", -1)) != expected_style:
            _fail("%s metadata style mismatch" % str(vehicle.name))
            return

    if bool(runtime.call("apply_to_vehicle", hatch)):
        _fail("second application must be idempotent")
        return
    if _mix_child_count(hatch) != 1:
        _fail("idempotence created duplicate replacement visuals")
        return

    var unrelated := _make_vehicle(midi, "PlayerCar_01", Color(0.2, 0.2, 0.2, 1.0))
    for _frame: int in range(3):
        await process_frame
    if unrelated.has_meta("midi_vehicle_style_mix_contract"):
        _fail("runtime touched an unrelated vehicle")
        return
    if unrelated.get_node_or_null(MIX_VISUAL_NAME) != null:
        _fail("runtime created a replacement for an unrelated vehicle")
        return

    print("MIDI_CIVILIAN_VEHICLE_STYLE_MIX_OK: sedan/hatchback/wagon exposed at Midi; movement/collision/geography untouched")
    quit(0)
