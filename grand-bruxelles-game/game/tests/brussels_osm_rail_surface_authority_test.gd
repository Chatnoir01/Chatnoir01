extends SceneTree

const RUNTIME_PATH := "res://game/scripts/brussels_osm_rail_surface_runtime.gd"
const MATERIAL_FAMILY := "brussels_osm_rail_surface_v1"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_RAIL_SURFACE_AUTHORITY_FAIL: %s" % message)
    quit(1)

func _make_rail(name_value: String) -> CSGBox3D:
    var rail := CSGBox3D.new()
    rail.name = name_value
    rail.size = Vector3(0.16, 0.12, 5.4)
    rail.position = Vector3(4.0, 0.25, -7.0)
    var baseline := StandardMaterial3D.new()
    baseline.albedo_color = Color(0.17, 0.18, 0.19, 1.0)
    rail.material = baseline
    return rail

func _add_osm_rails(scene_owner: Node3D, rail_name: String) -> CSGBox3D:
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    scene_owner.add_child(osm)
    var rails := Node3D.new()
    rails.name = "GeneratedRails"
    osm.add_child(rails)
    var rail := _make_rail(rail_name)
    rails.add_child(rail)
    return rail

func _run() -> void:
    if current_scene != null:
        _fail("script witness requires current_scene == null")
        return

    var runtime_script := load(RUNTIME_PATH) as Script
    if runtime_script == null:
        _fail("runtime script missing")
        return
    var runtime := runtime_script.new() as Node
    if runtime == null:
        _fail("runtime is not a Node")
        return
    runtime.name = "BrusselsOsmRailSurfaceAuthorityWitness"
    root.add_child(runtime)

    for _frame: int in range(6):
        await process_frame
    if int(runtime.call("applied_rail_count")) != 0:
        _fail("runtime bound rails before an authoritative scene existed")
        return

    var foreign_wrapper := Node3D.new()
    foreign_wrapper.name = "ForeignEnvironmentOwner"
    root.add_child(foreign_wrapper)
    var foreign_main := Node3D.new()
    foreign_main.name = "Main"
    foreign_wrapper.add_child(foreign_main)
    var foreign_rail := _add_osm_rails(foreign_main, "Rail_ForeignDecoy")
    var foreign_material := foreign_rail.material
    var foreign_transform := foreign_rail.global_transform
    var foreign_size := foreign_rail.size

    for _frame: int in range(12):
        await process_frame
    if int(runtime.call("applied_rail_count")) != 0:
        _fail("foreign nested anchor clone captured OSM rail surface authority")
        return
    if foreign_rail.material != foreign_material:
        _fail("foreign nested rail material was mutated")
        return
    if foreign_rail.has_meta("material_family"):
        _fail("foreign nested rail received shared material provenance")
        return
    if not foreign_rail.global_transform.is_equal_approx(foreign_transform) or not foreign_rail.size.is_equal_approx(foreign_size):
        _fail("foreign nested rail geometry changed")
        return

    var viewport := SubViewport.new()
    viewport.name = "RailSurfaceViewport"
    root.add_child(viewport)
    var main := Node3D.new()
    main.name = "Main"
    viewport.add_child(main)
    var production_rail := _add_osm_rails(main, "Rail_Authoritative")
    var production_transform := production_rail.global_transform
    var production_size := production_rail.size

    for _frame: int in range(18):
        await process_frame

    if int(runtime.call("applied_rail_count")) != 1:
        _fail("authoritative root-level viewport Main did not bind exactly one rail")
        return
    if str(production_rail.get_meta("material_family", "")) != MATERIAL_FAMILY:
        _fail("authoritative rail did not receive shared material family")
        return
    if str(production_rail.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
        _fail("source provenance changed")
        return
    if str(production_rail.get_meta("license", "")) != "ODbL-1.0":
        _fail("license provenance changed")
        return
    if not bool(production_rail.get_meta("placement_source_backed", false)):
        _fail("placement source-backed contract missing")
        return
    if bool(production_rail.get_meta("alloy_source_backed", true)):
        _fail("authored alloy was incorrectly promoted to source-backed")
        return
    if not production_rail.global_transform.is_equal_approx(production_transform) or not production_rail.size.is_equal_approx(production_size):
        _fail("authoritative rail geometry changed")
        return
    if not bool(runtime.call("geometry_unchanged")):
        _fail("runtime geometry invariant failed")
        return
    if foreign_rail.material != foreign_material or foreign_rail.has_meta("material_family"):
        _fail("foreign rail was mutated after authoritative owner arrived")
        return

    print("BRUSSELS_OSM_RAIL_SURFACE_AUTHORITY_OK: rails=1 foreign_nested_rejected=true owner=root-viewport-main source=OSM license=ODbL-1.0 geometry_changed=false")
    quit(0)
