extends SceneTree

const RUNTIME_PATH := "res://game/scripts/brussels_osm_sidewalk_surface_runtime.gd"
const OWNER_META := &"shared_sidewalk_material_owner"
const OWNER_VALUE := "brussels_osm_sidewalk_surface_runtime"
const AUTOLOAD_NAME := "BrusselsOsmSidewalkSurfaceRuntime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_SIDEWALK_SURFACE_AUTHORITY_FAIL: %s" % message)
    quit(1)

func _make_sidewalk(name_value: String) -> CSGBox3D:
    var sidewalk := CSGBox3D.new()
    sidewalk.name = name_value
    sidewalk.size = Vector3(1.85, 0.12, 14.0)
    sidewalk.position = Vector3(2.7, 0.01, -8.0)
    var baseline := StandardMaterial3D.new()
    baseline.albedo_color = Color(0.37, 0.36, 0.34, 1.0)
    sidewalk.material = baseline
    return sidewalk

func _add_osm_sidewalk(scene_owner: Node3D, sidewalk_name: String) -> CSGBox3D:
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    scene_owner.add_child(osm)
    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    osm.add_child(roads)
    var sidewalk := _make_sidewalk(sidewalk_name)
    roads.add_child(sidewalk)
    return sidewalk

func _resolve_runtime() -> Node:
    var canonical := root.get_node_or_null(AUTOLOAD_NAME)
    if canonical != null:
        return canonical
    var runtime_script := load(RUNTIME_PATH) as Script
    if runtime_script == null:
        return null
    var runtime := runtime_script.new() as Node
    if runtime == null:
        return null
    runtime.name = "BrusselsOsmSidewalkSurfaceAuthorityWitness"
    root.add_child(runtime)
    return runtime

func _run() -> void:
    if current_scene != null:
        _fail("script witness requires current_scene == null")
        return

    var runtime := _resolve_runtime()
    if runtime == null:
        _fail("canonical sidewalk surface runtime missing")
        return

    for _frame: int in range(6):
        await process_frame
    if int(runtime.call("applied_sidewalk_count")) != 0:
        _fail("runtime bound sidewalks before an authoritative scene existed")
        return

    var foreign_wrapper := Node3D.new()
    foreign_wrapper.name = "ForeignEnvironmentOwner"
    root.add_child(foreign_wrapper)
    var foreign_main := Node3D.new()
    foreign_main.name = "Main"
    foreign_wrapper.add_child(foreign_main)
    var foreign_sidewalk := _add_osm_sidewalk(foreign_main, "SidewalkAuthorityClone")
    var foreign_material := foreign_sidewalk.material
    var foreign_transform := foreign_sidewalk.global_transform
    var foreign_size := foreign_sidewalk.size

    for _frame: int in range(12):
        await process_frame
    if int(runtime.call("applied_sidewalk_count")) != 0:
        _fail("foreign nested anchor clone captured OSM sidewalk surface authority")
        return
    if foreign_sidewalk.material != foreign_material:
        _fail("foreign nested sidewalk material was mutated")
        return
    if foreign_sidewalk.has_meta(OWNER_META) or foreign_sidewalk.has_meta("material_family"):
        _fail("foreign nested sidewalk captured shared material ownership")
        return
    if not foreign_sidewalk.global_transform.is_equal_approx(foreign_transform) or not foreign_sidewalk.size.is_equal_approx(foreign_size):
        _fail("foreign nested sidewalk geometry changed")
        return

    var viewport := SubViewport.new()
    viewport.name = "SidewalkSurfaceViewport"
    root.add_child(viewport)
    var main := Node3D.new()
    main.name = "Main"
    viewport.add_child(main)
    var production_sidewalk := _add_osm_sidewalk(main, "SidewalkAuthorityProduction")
    var production_transform := production_sidewalk.global_transform
    var production_size := production_sidewalk.size

    for _frame: int in range(18):
        await process_frame

    if int(runtime.call("applied_sidewalk_count")) != 1:
        _fail("authoritative root-level viewport Main did not bind exactly one sidewalk")
        return
    if str(production_sidewalk.get_meta(OWNER_META, "")) != OWNER_VALUE:
        _fail("authoritative sidewalk did not receive canonical material ownership")
        return
    if str(production_sidewalk.get_meta("environment_role", "")) != "generated_osm_sidewalk":
        _fail("authoritative sidewalk role metadata missing")
        return
    if bool(production_sidewalk.get_meta("geometry_changed_by_sidewalk_surface_runtime", true)):
        _fail("runtime claimed a geometry mutation")
        return
    if not production_sidewalk.global_transform.is_equal_approx(production_transform) or not production_sidewalk.size.is_equal_approx(production_size):
        _fail("authoritative sidewalk geometry changed")
        return

    foreign_wrapper.queue_free()
    viewport.queue_free()
    for _frame: int in range(4):
        await process_frame

    print("BRUSSELS_OSM_SIDEWALK_SURFACE_AUTHORITY_OK: foreign_clone_rejected=true authoritative_viewport_main=true geometry_changed=false")
    quit(0)
