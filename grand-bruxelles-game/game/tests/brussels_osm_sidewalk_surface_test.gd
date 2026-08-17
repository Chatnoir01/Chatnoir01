extends SceneTree

const MATERIAL_FACTORY := preload("res://game/scripts/brussels_osm_sidewalk_surface_material.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SIDEWALK_SURFACE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    root.add_child(scene)

    var runtime := root.get_node_or_null("BrusselsOsmSidewalkSurfaceRuntime")
    if runtime == null:
        _fail("shared sidewalk surface runtime missing")
        return

    for _frame: int in range(180):
        if bool(runtime.call("ready_complete")):
            break
        await process_frame
    if not bool(runtime.call("ready_complete")) or bool(runtime.call("failed")):
        _fail("shared sidewalk runtime did not bind cleanly")
        return

    var applied := int(runtime.call("applied_sidewalk_count"))
    if applied < 4:
        _fail("expected at least 4 existing OSM sidewalks, got %d" % applied)
        return
    if int(runtime.call("shared_material_count")) != 1:
        _fail("expected exactly one shared material instance")
        return

    var material := MATERIAL_FACTORY.create_material()
    if str(material.get_meta("material_family", "")) != MATERIAL_FACTORY.MATERIAL_FAMILY:
        _fail("material family metadata missing")
        return
    if str(material.get_meta("license", "")) != "ODbL-1.0":
        _fail("OSM placement provenance missing")
        return
    if bool(material.get_meta("surface_composition_claimed", true)):
        _fail("authored presentation must not claim sidewalk composition")
        return
    if bool(material.get_meta("exact_rgb_is_photometric_measurement", true)):
        _fail("authored RGB must not claim photometric measurement")
        return
    if bool(material.get_meta("geometry_changed", true)):
        _fail("material-only lot must not claim geometry changes")
        return

    print("BRUSSELS_OSM_SIDEWALK_SURFACE_OK: sidewalks=%d shared_materials=1 family=%s source=OSM placement_only license=ODbL-1.0 geometry_changed=false composition_claimed=false" % [applied, MATERIAL_FACTORY.MATERIAL_FAMILY])
    quit(0)
