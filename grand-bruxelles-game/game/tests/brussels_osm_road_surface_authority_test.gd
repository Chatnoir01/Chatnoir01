extends SceneTree

const RUNTIME_PATH := "res://game/scripts/brussels_osm_road_surface_runtime.gd"
const SOURCE := "OpenStreetMap contributors via Overpass API"
const LICENSE := "ODbL-1.0"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ROAD_SURFACE_AUTHORITY_FAIL: %s" % message)
    quit(1)

func _make_road(name_value: String) -> CSGBox3D:
    var road := CSGBox3D.new()
    road.name = name_value
    road.size = Vector3(6.4, 0.10, 14.0)
    road.position = Vector3(3.0, -0.03, -9.0)
    var baseline := StandardMaterial3D.new()
    baseline.albedo_color = Color(0.22, 0.23, 0.24, 1.0)
    road.material = baseline
    return road

func _make_official_surface() -> MeshInstance3D:
    var surface := MeshInstance3D.new()
    surface.name = "JetteOfficialStreetSurfaces"
    var baseline := StandardMaterial3D.new()
    baseline.albedo_color = Color(0.31, 0.32, 0.33, 1.0)
    surface.material_override = baseline
    return surface

func _add_osm_roads(scene_owner: Node3D, road_name: String) -> CSGBox3D:
    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    scene_owner.add_child(osm)
    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    osm.add_child(roads)
    var road := _make_road(road_name)
    roads.add_child(road)
    return road

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
    runtime.name = "BrusselsOsmRoadSurfaceAuthorityWitness"
    root.add_child(runtime)

    for _frame: int in range(6):
        await process_frame
    if int(runtime.call("applied_road_count")) != 0:
        _fail("runtime bound roads before an authoritative scene existed")
        return

    var foreign_wrapper := Node3D.new()
    foreign_wrapper.name = "ForeignEnvironmentOwner"
    root.add_child(foreign_wrapper)
    var foreign_main := Node3D.new()
    foreign_main.name = "Main"
    foreign_wrapper.add_child(foreign_main)
    var foreign_road := _add_osm_roads(foreign_main, "Road_359177328_0")
    var foreign_material := foreign_road.material
    var foreign_transform := foreign_road.global_transform
    var foreign_size := foreign_road.size
    var foreign_official := _make_official_surface()
    foreign_main.add_child(foreign_official)
    var foreign_official_material := foreign_official.material_override

    for _frame: int in range(12):
        await process_frame
    if int(runtime.call("applied_road_count")) != 0:
        _fail("foreign nested anchor clone captured OSM road surface authority")
        return
    if foreign_road.material != foreign_material:
        _fail("foreign nested road material was mutated")
        return
    if foreign_road.has_meta("source") or foreign_road.has_meta("license"):
        _fail("foreign nested road received source provenance")
        return
    if not foreign_road.global_transform.is_equal_approx(foreign_transform) or not foreign_road.size.is_equal_approx(foreign_size):
        _fail("foreign nested road geometry changed")
        return
    if foreign_official.material_override != foreign_official_material:
        _fail("foreign nested Jette official surface material was mutated")
        return
    if foreign_official.has_meta("ground_network_provider") or foreign_official.has_meta("ground_network_presentation_family"):
        _fail("foreign nested Jette official surface captured shared ground-network authority")
        return

    var viewport := SubViewport.new()
    viewport.name = "RoadSurfaceViewport"
    root.add_child(viewport)
    var main := Node3D.new()
    main.name = "Main"
    viewport.add_child(main)
    var production_road := _add_osm_roads(main, "Road_359177328_0")
    var production_transform := production_road.global_transform
    var production_size := production_road.size
    var production_official := _make_official_surface()
    main.add_child(production_official)
    var production_official_legacy := production_official.material_override

    for _frame: int in range(18):
        await process_frame

    if int(runtime.call("applied_road_count")) != 1:
        _fail("authoritative root-level viewport Main did not bind exactly one road")
        return
    if str(production_road.get_meta("source", "")) != SOURCE:
        _fail("source provenance changed")
        return
    if str(production_road.get_meta("license", "")) != LICENSE:
        _fail("license provenance changed")
        return
    if int(production_road.get_meta("osm_id", 0)) != 359177328:
        _fail("source OSM id changed")
        return
    if bool(production_road.get_meta("geometry_changed_by_road_surface_runtime", true)):
        _fail("runtime claimed geometry mutation")
        return
    if not production_road.global_transform.is_equal_approx(production_transform) or not production_road.size.is_equal_approx(production_size):
        _fail("authoritative road geometry changed")
        return
    if foreign_road.material != foreign_material or foreign_road.has_meta("source") or foreign_road.has_meta("license"):
        _fail("foreign road was mutated after authoritative owner arrived")
        return
    if foreign_official.material_override != foreign_official_material or foreign_official.has_meta("ground_network_provider"):
        _fail("foreign Jette official surface was mutated after authoritative owner arrived")
        return
    if int(runtime.call("official_applied_road_count")) != 1:
        _fail("authoritative Jette official surface did not bind exactly once")
        return
    if production_official.material_override == production_official_legacy:
        _fail("authoritative Jette official surface did not receive shared presentation")
        return
    if str(production_official.get_meta("ground_network_provider", "")) != "UrbIS":
        _fail("authoritative Jette official surface provider changed")
        return
    if bool(production_official.get_meta("geometry_changed_by_ground_network_runtime", true)):
        _fail("runtime claimed official Jette geometry mutation")
        return

    print("BRUSSELS_OSM_ROAD_SURFACE_AUTHORITY_OK: roads=1 official_jette=1 foreign_nested_rejected=true owner=root-viewport-main osm_id=359177328 source=OSM license=ODbL-1.0 geometry_changed=false")
    quit(0)
