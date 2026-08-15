extends SceneTree

const EXPECTED_PARKED := 14
const EXPECTED_MOVING := 6

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AMBIENT_VEHICLE_VISUAL_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _frame: int in range(6):
        await process_frame

    var urban_life := scene.get_node_or_null("MidiUrbanLife")
    if urban_life == null:
        _fail("production MidiUrbanLife missing")
        return

    var parked: Array[Node] = []
    for index: int in range(EXPECTED_PARKED):
        var vehicle := urban_life.get_node_or_null("ParkedCar_%02d" % index)
        if vehicle == null:
            _fail("parked vehicle %02d missing" % index)
            return
        parked.append(vehicle)

    var moving := get_nodes_in_group("ambient_traffic")
    if moving.size() != EXPECTED_MOVING:
        _fail("expected %d moving vehicles, got %d" % [EXPECTED_MOVING, moving.size()])
        return

    var all_vehicles: Array[Node] = []
    all_vehicles.append_array(parked)
    all_vehicles.append_array(moving)
    if all_vehicles.size() != EXPECTED_PARKED + EXPECTED_MOVING:
        _fail("unexpected ambient vehicle total")
        return

    for vehicle: Node in all_vehicles:
        var visual := vehicle.get_node_or_null("ProductionVisual") as Node3D
        if visual == null:
            _fail("%s has no production civilian vehicle visual" % vehicle.name)
            return
        var body_shell := visual.get_node_or_null("BodyShell") as MeshInstance3D
        var glass_house := visual.get_node_or_null("GlassHouse") as MeshInstance3D
        if body_shell == null or not (body_shell.mesh is ArrayMesh):
            _fail("%s production visual did not build shaped BodyShell" % vehicle.name)
            return
        if glass_house == null or not (glass_house.mesh is ArrayMesh):
            _fail("%s production visual did not build shaped GlassHouse" % vehicle.name)
            return
        for legacy_name: String in ["LowerBody", "Hood", "Roof", "CabinGlass", "FrontLeftLamp", "FrontRightLamp", "RearLeftLamp", "RearRightLamp", "FrontPlate", "RearPlate", "Wheel"]:
            if vehicle.get_node_or_null(legacy_name) != null:
                _fail("%s still owns legacy primitive %s directly" % [vehicle.name, legacy_name])
                return

    print("MIDI_AMBIENT_VEHICLE_VISUAL_OK: parked=%d moving=%d" % [parked.size(), moving.size()])
    scene.queue_free()
    quit(0)
