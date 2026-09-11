extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/mmc_generic_sedan_car1_runtime.gd")
const MODEL_PATH := "res://assets/vehicles/mmc_generic_sedan/generic_sedan.glb"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("MMC_GENERIC_SEDAN_CAR1_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var scene := Node3D.new()
    scene.name = "TestScene"
    root.add_child(scene)

    var vehicle := Node3D.new()
    vehicle.name = "PhysicalCarB"
    scene.add_child(vehicle)

    var fallback := Node3D.new()
    fallback.name = "VisualUpgrade"
    vehicle.add_child(fallback)

    var mesh_instance := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = Vector3(1.82, 1.45, 4.28)
    mesh_instance.mesh = box
    fallback.add_child(mesh_instance)

    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "RuntimeUnderTest"
    root.add_child(runtime)
    await process_frame

    var contract: Dictionary = runtime.get_contract()
    if str(contract.get("target", "")) != "PhysicalCarB":
        _fail("CAR-1 target changed")
        return
    if bool(contract.get("changes_physics", true)):
        _fail("renderer bridge claims a physics change")
        return
    if bool(contract.get("changes_collision", true)):
        _fail("renderer bridge claims a collision change")
        return
    if bool(contract.get("changes_traffic", true)):
        _fail("renderer bridge claims a traffic change")
        return
    if bool(contract.get("changes_geography", true)):
        _fail("renderer bridge claims a geography change")
        return
    if bool(contract.get("production_authorized", true)):
        _fail("candidate became production-authorized without owner review")
        return

    var wrong_target := Node3D.new()
    wrong_target.name = "PrototypeCar"
    scene.add_child(wrong_target)
    if runtime.apply_to_vehicle(wrong_target):
        _fail("bridge mounted on a non-CAR-1 vehicle")
        return

    var model_exists := ResourceLoader.exists(MODEL_PATH)
    var mounted := runtime.apply_to_vehicle(vehicle)

    if not model_exists:
        if mounted:
            _fail("runtime mounted without official asset bytes")
            return
        if not fallback.visible:
            _fail("fallback was hidden while official asset is missing")
            return
        if runtime.mount_reason() != "official_asset_missing":
            _fail("unexpected missing-asset reason: %s" % runtime.mount_reason())
            return
        if vehicle.get_node_or_null("MMCGenericSedanCAR1") != null:
            _fail("authored holder exists without official asset")
            return
        print("MMC_GENERIC_SEDAN_CAR1_OK: official_asset_missing fallback_preserved=true")
        quit(0)
        return

    if not mounted:
        _fail("official asset exists but failed to mount: %s" % runtime.mount_reason())
        return

    var authored := vehicle.get_node_or_null("MMCGenericSedanCAR1") as Node3D
    if authored == null:
        _fail("authored holder missing after successful mount")
        return
    if fallback.visible:
        _fail("procedural fallback stayed visible after successful mount")
        return
    if not authored.visible:
        _fail("authored holder is hidden after successful mount")
        return
    if str(vehicle.get_meta("mmc_generic_sedan_model", "")) != MODEL_PATH:
        _fail("vehicle model metadata is wrong")
        return
    if bool(authored.get_meta("production_authorized", true)):
        _fail("mounted witness incorrectly marked production-authorized")
        return

    var child_count := vehicle.get_child_count()
    if not runtime.apply_to_vehicle(vehicle):
        _fail("idempotent second mount failed")
        return
    if vehicle.get_child_count() != child_count:
        _fail("second mount duplicated authored nodes")
        return

    runtime.set_review_enabled(false)
    if not fallback.visible or authored.visible:
        _fail("review OFF did not restore procedural fallback")
        return

    runtime.set_review_enabled(true)
    if fallback.visible or not authored.visible:
        _fail("review ON did not restore authored witness")
        return

    print("MMC_GENERIC_SEDAN_CAR1_OK: official_asset_present mounted=true fallback_recoverable=true")
    quit(0)
