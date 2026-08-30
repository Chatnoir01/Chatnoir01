extends SceneTree

const EXPECTED := {
    "buildings": 1015,
    "street_surfaces": 627,
    "street_axes": 168,
    "tram_network": 162,
    "train_network": 162,
}

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("NORD_CITY_MACHINE_LABO_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var script := load("res://game/zones/nord/nord_city_machine_zone.gd") as Script
    if script == null:
        _fail("runtime script missing")
        return

    var zone := Node3D.new()
    zone.name = "NordMachineLaboProof"
    zone.set_script(script)
    root.add_child(zone)
    await process_frame

    var stats = zone.get("last_stats")
    if not (stats is Dictionary):
        _fail("last_stats missing")
        return
    for key in EXPECTED:
        if int(stats.get(key, -1)) != int(EXPECTED[key]):
            _fail("%s expected=%s actual=%s" % [key, EXPECTED[key], stats.get(key, -1)])
            return

    for child_name in [
        "NordCityMachineReviewPad",
        "NordCityMachineStreetSurfaces",
        "NordCityMachineBuildings",
        "NordCityMachineTramNetwork",
        "NordCityMachineTrainNetwork",
    ]:
        if zone.get_node_or_null(child_name) == null:
            _fail("visible mesh missing: %s" % child_name)
            return

    var streets := zone.get_node("NordCityMachineStreetSurfaces") as MeshInstance3D
    var buildings := zone.get_node("NordCityMachineBuildings") as MeshInstance3D
    if streets.mesh == null or streets.mesh.get_surface_count() == 0:
        _fail("street mesh empty")
        return
    if buildings.mesh == null or buildings.mesh.get_surface_count() == 0:
        _fail("building mesh empty")
        return

    print(
        "NORD_CITY_MACHINE_LABO_OK buildings=%d street_surfaces=%d street_axes=%d tram_network=%d train_network=%d geometry_visible=true promotion=false" % [
            stats["buildings"],
            stats["street_surfaces"],
            stats["street_axes"],
            stats["tram_network"],
            stats["train_network"],
        ]
    )
    zone.queue_free()
    await process_frame
    quit(0)
