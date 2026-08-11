extends SceneTree

const SCENES := [
    "res://game/vehicles/police_patrol.tscn",
    "res://game/vehicles/police_civil.tscn",
    "res://game/vehicles/police_bab_van.tscn",
]

const DECAL_TEXTURES := [
    "res://assets/police/decals/police_bilingual_decal.png",
    "res://assets/police/decals/police_blue_stripes.png",
    "res://assets/police/decals/police_rear_chevrons.png",
]


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("POLICE_VEHICLE_SMOKE_FAIL: %s" % message)
    quit(1)


func _decal_world_width(sprite: Sprite3D) -> float:
    if sprite.texture == null:
        return 0.0
    return float(sprite.texture.get_width()) * sprite.pixel_size


func _validate_decal_scale(runtime_decals: Node, scene_path: String) -> bool:
    var bilingual: Sprite3D = runtime_decals.get_node_or_null("BilingualLeft") as Sprite3D
    var stripe: Sprite3D = runtime_decals.get_node_or_null("StripeLeft") as Sprite3D
    var rear: Sprite3D = runtime_decals.get_node_or_null("RearChevrons") as Sprite3D
    if bilingual == null or stripe == null or rear == null:
        _fail("required decal sprites missing in %s" % scene_path)
        return false

    var bilingual_width := _decal_world_width(bilingual)
    var stripe_width := _decal_world_width(stripe)
    var rear_width := _decal_world_width(rear)

    if bilingual_width < 0.8 or bilingual_width > 2.2:
        _fail("bilingual decal world width %.3f m is unrealistic in %s" % [bilingual_width, scene_path])
        return false
    if stripe_width < 2.0 or stripe_width > 5.0:
        _fail("side stripe world width %.3f m is unrealistic in %s" % [stripe_width, scene_path])
        return false
    if rear_width < 1.2 or rear_width > 2.5:
        _fail("rear chevron world width %.3f m is unrealistic in %s" % [rear_width, scene_path])
        return false
    return true


func _run() -> void:
    for texture_path in DECAL_TEXTURES:
        var texture: Texture2D = load(texture_path) as Texture2D
        if texture == null:
            _fail("failed to load decal texture %s" % texture_path)
            return

    for scene_path in SCENES:
        var packed: PackedScene = load(scene_path) as PackedScene
        if packed == null:
            _fail("failed to load %s" % scene_path)
            return
        var vehicle: Node = packed.instantiate()
        root.add_child(vehicle)
        await process_frame
        await process_frame

        if not vehicle.is_in_group("vehicle") or not vehicle.is_in_group("police_vehicle"):
            _fail("vehicle groups missing in %s" % scene_path)
            return
        if not vehicle.has_method("enter_driver") or not vehicle.has_method("exit_driver"):
            _fail("drive API missing in %s" % scene_path)
            return

        var visuals: Node = vehicle.get_node_or_null("EmergencyVisuals")
        if visuals == null:
            _fail("EmergencyVisuals missing in %s" % scene_path)
            return
        if not visuals.has_method("set_emergency_lights") or not visuals.has_method("are_emergency_lights_active"):
            _fail("emergency-light API missing in %s" % scene_path)
            return

        if vehicle.is_in_group("police_marked") or vehicle.is_in_group("police_bab"):
            var runtime_decals: Node = vehicle.get_node_or_null("RuntimeDecals")
            if runtime_decals == null:
                _fail("runtime decal layer missing in %s" % scene_path)
                return
            if runtime_decals.get_child_count() < 5:
                _fail("expected side and rear decals in %s" % scene_path)
                return
            if not _validate_decal_scale(runtime_decals, scene_path):
                return

        visuals.call("set_emergency_lights", true)
        await process_frame
        if not bool(visuals.call("are_emergency_lights_active")):
            _fail("lights did not activate in %s" % scene_path)
            return
        var left: Node3D = visuals.get_node_or_null("LeftFlashGroup") as Node3D
        var right: Node3D = visuals.get_node_or_null("RightFlashGroup") as Node3D
        if left == null or right == null:
            _fail("flash groups missing in %s" % scene_path)
            return
        if not left.visible and not right.visible:
            _fail("no flash group visible after activation in %s" % scene_path)
            return

        visuals.call("set_emergency_lights", false)
        await process_frame
        if left.visible or right.visible:
            _fail("flash groups stayed visible after shutdown in %s" % scene_path)
            return

        vehicle.queue_free()
        await process_frame

    var main_packed: PackedScene = load("res://game/main.tscn") as PackedScene
    if main_packed == null:
        _fail("main scene failed to load")
        return
    var main_scene: Node = main_packed.instantiate()
    root.add_child(main_scene)
    await process_frame
    for node_name in ["PolicePatrol", "PoliceCivilUnit", "PoliceBAB"]:
        if main_scene.get_node_or_null(node_name) == null:
            _fail("main scene missing %s" % node_name)
            return

    print("POLICE_VEHICLE_SMOKE_OK: variants, decals, world scale and emergency lights loaded correctly")
    main_scene.queue_free()
    await process_frame
    quit(0)
