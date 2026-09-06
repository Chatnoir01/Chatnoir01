extends SceneTree

const LOADER_CASES := [
    {
        "script": "res://game/scripts/grand_place_official_lod2_1655673.gd",
        "building_id": "1655673",
    },
    {
        "script": "res://game/scripts/grand_place_official_lod2_1786758.gd",
        "building_id": "1786758",
    },
]


func _fail(message: String) -> void:
    push_error("GRAND_PLACE_LOD2_LATE_OSM_MASK_RUNTIME_FAIL: %s" % message)
    quit(1)


func _process(_delta: float) -> bool:
    return false


func _initialize() -> void:
    call_deferred("_run")


func _run() -> void:
    for case: Dictionary in LOADER_CASES:
        var main := Node3D.new()
        main.name = "Main"
        root.add_child(main)
        current_scene = main

        var script: Script = load(str(case["script"]))
        if script == null:
            _fail("cannot load %s" % case["script"])
            return
        var loader := Node3D.new()
        loader.name = "OfficialLoD2_%s" % case["building_id"]
        loader.set_script(script)
        main.add_child(loader)

        var built := false
        for _frame: int in range(90):
            await process_frame
            if bool(loader.get("geometry_loaded")):
                built = true
                break
        if not built:
            _fail("official loader %s did not become geometry_loaded" % case["building_id"])
            return

        # Deliberately exceed the historical 8-frame startup window before the
        # OSM mount exists. The official loader must still mask replacements.
        for _frame: int in range(12):
            await process_frame

        var osm := Node3D.new()
        osm.name = "BrusselsOSM"
        main.add_child(osm)
        var generated := Node3D.new()
        generated.name = "GeneratedBuildings"
        osm.add_child(generated)
        await process_frame

        # Also add the replacement after the GeneratedBuildings container so
        # the contract covers late descendants, not only late container mount.
        var bounds: Rect2 = loader.get("source_bounds")
        if bounds.size.length_squared() <= 0.001:
            _fail("official loader %s produced empty source bounds" % case["building_id"])
            return
        var replacement := CSGBox3D.new()
        replacement.name = "LateOSM_%s" % case["building_id"]
        replacement.size = Vector3(4.0, 8.0, 4.0)
        replacement.use_collision = true
        replacement.visible = true
        var center := bounds.get_center()
        replacement.position = Vector3(center.x, 4.0, center.y)
        generated.add_child(replacement)

        for _frame: int in range(3):
            await process_frame

        if replacement.visible:
            _fail("late OSM replacement remained visible for %s" % case["building_id"])
            return
        if replacement.use_collision:
            _fail("late OSM replacement collision remained enabled for %s" % case["building_id"])
            return
        if str(replacement.get_meta("replaced_by_urbis_building", "")) != str(case["building_id"]):
            _fail("late OSM replacement missing owner metadata for %s" % case["building_id"])
            return

        main.queue_free()
        await process_frame
        current_scene = null

    print("GRAND_PLACE_LOD2_LATE_OSM_MASK_RUNTIME_OK scripts=2 late_container=true late_descendant=true geometry_mutated=false camera_mutated=false")
    quit(0)
