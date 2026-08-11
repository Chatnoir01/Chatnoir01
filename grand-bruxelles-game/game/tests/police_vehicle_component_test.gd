extends SceneTree

const SCENES := [
    "res://game/vehicles/police_patrol.tscn",
    "res://game/vehicles/police_civil.tscn",
    "res://game/vehicles/police_bab_van.tscn",
]
const DECALS := [
    "res://assets/police/decals/police_bilingual_decal.png",
    "res://assets/police/decals/police_blue_stripes.png",
    "res://assets/police/decals/police_rear_chevrons.png",
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("POLICE_VEHICLE_COMPONENT_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    for texture_path in DECALS:
        if load(texture_path) == null:
            _fail("decal failed to load: %s" % texture_path)
            return

    for scene_path in SCENES:
        var packed := load(scene_path) as PackedScene
        if packed == null:
            _fail("scene failed to load: %s" % scene_path)
            return
        var vehicle := packed.instantiate()
        root.add_child(vehicle)
        await process_frame
        await process_frame

        if not vehicle.is_in_group("vehicle") or not vehicle.is_in_group("police_vehicle"):
            _fail("required groups missing: %s" % scene_path)
            return
        if not vehicle.has_method("enter_driver") or not vehicle.has_method("exit_driver"):
            _fail("drive API missing: %s" % scene_path)
            return

        var visuals := vehicle.get_node_or_null("EmergencyVisuals")
        if visuals == null or not visuals.has_method("set_emergency_lights"):
            _fail("emergency-light component missing: %s" % scene_path)
            return

        visuals.call("set_emergency_lights", true)
        await process_frame
        if not bool(visuals.call("are_emergency_lights_active")):
            _fail("emergency lights failed to activate: %s" % scene_path)
            return
        visuals.call("set_emergency_lights", false)
        await process_frame

        if vehicle.is_in_group("police_marked") or vehicle.is_in_group("police_bab"):
            var decals := vehicle.get_node_or_null("RuntimeDecals")
            if decals == null or decals.get_child_count() < 5:
                _fail("runtime decals missing: %s" % scene_path)
                return

        vehicle.queue_free()
        await process_frame

    print("POLICE_VEHICLE_COMPONENT_OK")
    quit(0)
