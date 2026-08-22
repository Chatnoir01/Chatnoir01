extends SceneTree

const MANAGER_SCRIPT := preload("res://game/scripts/traffic_manager_npc_crossing_extension.gd")
const RGSDEV_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("LABO_CURRENT_SEDAN_DENSITY_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var manager := MANAGER_SCRIPT.new()
    manager.auto_load_data = false
    manager.auto_spawn_runtime = false
    manager.official_density_enabled = false
    manager.scooter_share = 0.0
    manager.motorcycle_share = 0.0
    root.add_child(manager)
    await process_frame

    var cycle: Array = manager.call("get_labo_civilian_model_cycle")
    if cycle.size() != 10:
        _fail("LABO civilian model cycle must stay deterministic at 10 slots")
        return
    var sedan_count := cycle.count("sedan")
    if sedan_count != 6:
        _fail("current sedan must occupy 6/10 LABO civilian slots, got %d" % sedan_count)
        return
    for model_id: Variant in cycle:
        if str(model_id) not in ["sedan", "hatchback", "suv", "van", "pickup"]:
            _fail("legacy/non-target civilian model leaked into LABO cycle: %s" % str(model_id))
            return

    var seen: Dictionary = {}
    for index: int in range(10):
        manager.set("_spawn_serial", index)
        var vehicle := manager.call("_create_vehicle_node") as Node3D
        root.add_child(vehicle)
        await process_frame
        var visual := vehicle.get_node_or_null("RgsdevVisual")
        if visual == null or visual.get_script() != RGSDEV_SCRIPT:
            _fail("traffic vehicle %d is not using the Rgsdev visual" % index)
            return
        var contract: Dictionary = visual.call("get_visual_contract")
        var model_id := str(contract.get("model_id", ""))
        seen[model_id] = int(seen.get(model_id, 0)) + 1
        if str(visual.get_meta("labo_vehicle_model", "")) != model_id:
            _fail("LABO vehicle metadata/model mismatch for slot %d" % index)
            return
    if int(seen.get("sedan", 0)) != 6:
        _fail("runtime did not instantiate six current sedans: %s" % str(seen))
        return

    var world := Node3D.new()
    world.name = "World"
    root.add_child(world)
    manager.reparent(world)

    var starter := Node3D.new()
    starter.name = "PrototypeCar"
    world.add_child(starter)
    for legacy_name: String in ["Body", "Cabin", "VisualUpgrade", "ABLabel"]:
        var legacy := Node3D.new()
        legacy.name = legacy_name
        starter.add_child(legacy)
    var old_physical := Node3D.new()
    old_physical.name = "PhysicalCarB"
    world.add_child(old_physical)

    manager.call("_upgrade_scene_vehicle_visuals")
    await process_frame
    await process_frame

    if world.get_node_or_null("PhysicalCarB") != null:
        _fail("old PhysicalCarB prototype still exists after production cleanup")
        return
    for legacy_name: String in ["Body", "Cabin", "VisualUpgrade", "ABLabel"]:
        if starter.get_node_or_null(legacy_name) != null:
            _fail("legacy starter visual still exists: %s" % legacy_name)
            return
    var starter_visual := starter.get_node_or_null("RgsdevVisual")
    if starter_visual == null:
        _fail("current sedan visual missing from starter vehicle")
        return
    var starter_contract: Dictionary = starter_visual.call("get_visual_contract")
    if str(starter_contract.get("model_id", "")) != "sedan":
        _fail("starter vehicle is no longer the current sedan")
        return

    print("LABO_CURRENT_SEDAN_DENSITY_OK: current_sedan=6/10 allowed=sedan,hatchback,suv,van,pickup legacy_removed=true")
    quit(0)
