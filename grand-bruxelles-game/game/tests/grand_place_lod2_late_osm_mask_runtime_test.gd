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


func _process(_delta: float) -> bool:
    return false


func _initialize() -> void:
    call_deferred("_run")


func _source_bounds(building_id: String) -> Rect2:
    var path := "res://data/urbis/grand_place_lod2/%s.game.json" % building_id
    if not FileAccess.file_exists(path):
        return Rect2()
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return Rect2()
    var initialized := false
    var lo := Vector2.ZERO
    var hi := Vector2.ZERO
    for raw_face: Variant in (parsed as Dictionary).get("faces", []):
        if typeof(raw_face) != TYPE_DICTIONARY:
            continue
        for raw_triangle: Variant in (raw_face as Dictionary).get("triangles", []):
            if typeof(raw_triangle) != TYPE_ARRAY:
                continue
            for raw_point: Variant in raw_triangle:
                if typeof(raw_point) != TYPE_ARRAY or raw_point.size() != 3:
                    continue
                var xz := Vector2(float(raw_point[0]), float(raw_point[2]))
                if not initialized:
                    lo = xz
                    hi = xz
                    initialized = true
                else:
                    lo.x = minf(lo.x, xz.x)
                    lo.y = minf(lo.y, xz.y)
                    hi.x = maxf(hi.x, xz.x)
                    hi.y = maxf(hi.y, xz.y)
    return Rect2(lo, hi - lo) if initialized else Rect2()


func _new_main() -> Node3D:
    var main := Node3D.new()
    main.name = "Main"
    root.add_child(main)
    current_scene = main
    return main


func _add_generated_buildings(main: Node3D) -> Node3D:
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    main.add_child(osm)
    var generated := Node3D.new()
    generated.name = "GeneratedBuildings"
    osm.add_child(generated)
    return generated


func _add_replacement(generated: Node3D, bounds: Rect2, name: String) -> CSGBox3D:
    var replacement := CSGBox3D.new()
    replacement.name = name
    replacement.size = Vector3(4.0, 8.0, 4.0)
    replacement.use_collision = true
    replacement.visible = true
    var center := bounds.get_center()
    replacement.position = Vector3(center.x, 4.0, center.y)
    generated.add_child(replacement)
    return replacement


func _add_loader(main: Node3D, case: Dictionary) -> Node3D:
    var script: Script = load(str(case["script"]))
    if script == null:
        return null
    var loader := Node3D.new()
    loader.name = "OfficialLoD2_%s" % case["building_id"]
    loader.set_script(script)
    main.add_child(loader)
    return loader


func _wait_for_geometry(loader: Node3D) -> bool:
    for _frame: int in range(90):
        await process_frame
        if bool(loader.get("geometry_loaded")):
            return true
    return false


func _mask_failure(replacement: CSGBox3D, building_id: String, phase: String) -> String:
    if replacement.visible:
        return "%s OSM replacement remained visible for %s" % [phase, building_id]
    if replacement.use_collision:
        return "%s OSM replacement collision remained enabled for %s" % [phase, building_id]
    if str(replacement.get_meta("replaced_by_urbis_building", "")) != building_id:
        return "%s OSM replacement missing owner metadata for %s" % [phase, building_id]
    return ""


func _cleanup(main: Node3D) -> void:
    if is_instance_valid(main):
        main.queue_free()
        await process_frame
    current_scene = null


func _run() -> void:
    var failures: Array[String] = []

    for case: Dictionary in LOADER_CASES:
        var building_id := str(case["building_id"])
        var bounds := _source_bounds(building_id)
        if bounds.size.length_squared() <= 0.001:
            failures.append("source bounds missing for %s" % building_id)
            continue

        # A: deterministic positive control. The OSM replacement exists before
        # the official loader builds, so the existing one-shot mask must work.
        var early_main := _new_main()
        var early_generated := _add_generated_buildings(early_main)
        var early_replacement := _add_replacement(early_generated, bounds, "EarlyOSM_%s" % building_id)
        await process_frame
        var early_loader := _add_loader(early_main, case)
        if early_loader == null:
            failures.append("cannot load %s" % case["script"])
            await _cleanup(early_main)
            continue
        if not await _wait_for_geometry(early_loader):
            failures.append("early-control loader %s did not become geometry_loaded" % building_id)
            await _cleanup(early_main)
            continue
        var early_failure := _mask_failure(early_replacement, building_id, "early-control")
        if early_failure.is_empty():
            print("GRAND_PLACE_LOD2_LATE_OSM_MASK_EARLY_CONTROL_OK building=%s visible=false collision=false" % building_id)
        else:
            failures.append(early_failure)
        await _cleanup(early_main)

        # B: causal late-arrival case. Exceed the historical 8-frame window,
        # then mount both the container and its descendant. This must behave
        # identically to A after the production race is fixed.
        var late_main := _new_main()
        var late_loader := _add_loader(late_main, case)
        if late_loader == null:
            failures.append("cannot load %s for late case" % case["script"])
            await _cleanup(late_main)
            continue
        if not await _wait_for_geometry(late_loader):
            failures.append("late-case loader %s did not become geometry_loaded" % building_id)
            await _cleanup(late_main)
            continue
        for _frame: int in range(12):
            await process_frame
        var late_generated := _add_generated_buildings(late_main)
        await process_frame
        var late_replacement := _add_replacement(late_generated, bounds, "LateOSM_%s" % building_id)
        for _frame: int in range(3):
            await process_frame
        var late_failure := _mask_failure(late_replacement, building_id, "late-arrival")
        if late_failure.is_empty():
            print("GRAND_PLACE_LOD2_LATE_OSM_MASK_LATE_CONTROL_OK building=%s visible=false collision=false" % building_id)
        else:
            failures.append(late_failure)
        await _cleanup(late_main)

    if not failures.is_empty():
        for failure: String in failures:
            push_error("GRAND_PLACE_LOD2_LATE_OSM_MASK_RUNTIME_FAIL: %s" % failure)
        print("GRAND_PLACE_LOD2_LATE_OSM_MASK_AB_RED early_expected=masked late_expected=masked failures=%d scripts=2 geometry_mutated=false camera_mutated=false" % failures.size())
        quit(1)
        return

    print("GRAND_PLACE_LOD2_LATE_OSM_MASK_RUNTIME_OK scripts=2 early_control=true late_container=true late_descendant=true geometry_mutated=false camera_mutated=false")
    quit(0)
