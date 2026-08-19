extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_authored_vehicle_review_runtime.gd")
const MODEL_PATHS: Array[String] = [
    "res://assets/vehicles/kenney_car_kit/models/sedan.glb",
    "res://assets/vehicles/kenney_car_kit/models/hatchback-sports.glb",
    "res://assets/vehicles/kenney_car_kit/models/suv.glb",
    "res://assets/vehicles/kenney_car_kit/models/van.glb",
    "res://assets/vehicles/kenney_car_kit/models/taxi.glb",
]


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MIDI_AUTHORED_VEHICLE_REVIEW_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    for model_path: String in MODEL_PATHS:
        if not ResourceLoader.exists(model_path):
            _fail("missing model %s" % model_path)
            return
        var resource := load(model_path)
        if resource == null or not resource is PackedScene:
            _fail("model is not an importable PackedScene: %s" % model_path)
            return

    var scene := Node3D.new()
    scene.name = "TestScene"
    root.add_child(scene)

    var midi := Node3D.new()
    midi.name = "MidiUrbanLife"
    scene.add_child(midi)

    var vehicle := Node3D.new()
    vehicle.name = "ParkedCar_00"
    midi.add_child(vehicle)

    var fallback := Node3D.new()
    fallback.name = "ProductionVisual"
    vehicle.add_child(fallback)

    var mesh_instance := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(1.82, 1.35, 4.28)
    mesh_instance.mesh = box
    fallback.add_child(mesh_instance)

    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "RuntimeUnderTest"
    root.add_child(runtime)
    await process_frame

    if not runtime.apply_to_vehicle(vehicle):
        _fail("runtime refused a valid Midi vehicle")
        return

    var authored := vehicle.get_node_or_null("KenneyAuthoredVehicleReview") as Node3D
    if authored == null:
        _fail("authored review node missing")
        return
    if fallback.visible:
        _fail("procedural fallback stayed visible after successful authored mount")
        return
    if not authored.visible:
        _fail("authored review node is hidden")
        return
    if str(vehicle.get_meta("kenney_authored_vehicle_model", "")) != MODEL_PATHS[0]:
        _fail("deterministic model selection changed")
        return

    var child_count := vehicle.get_child_count()
    if not runtime.apply_to_vehicle(vehicle):
        _fail("idempotent second application failed")
        return
    if vehicle.get_child_count() != child_count:
        _fail("second application duplicated authored nodes")
        return

    runtime.set_review_enabled(false)
    if not fallback.visible or authored.visible:
        _fail("owner-review OFF toggle did not restore fallback")
        return
    runtime.set_review_enabled(true)
    if fallback.visible or not authored.visible:
        _fail("owner-review ON toggle did not restore authored model")
        return

    print("MIDI_AUTHORED_VEHICLE_REVIEW_OK: models=%d selected=%s" % [MODEL_PATHS.size(), MODEL_PATHS[0]])
    quit(0)
