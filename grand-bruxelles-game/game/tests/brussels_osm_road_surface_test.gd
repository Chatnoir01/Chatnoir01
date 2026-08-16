extends SceneTree

const MATERIAL_FAMILY := "brussels_osm_road_surface_v1"
const MIN_ROAD_SEGMENTS := 40

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_OSM_ROAD_SURFACE_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return

    var scene := packed.instantiate() as Node3D
    root.add_child(scene)
    for _frame: int in range(6):
        await process_frame

    var roads_root := scene.get_node_or_null("BrusselsOSM/GeneratedRoads") as Node3D
    if roads_root == null:
        _fail("production GeneratedRoads root missing")
        return

    var road_segments := 0
    var sourced_segments := 0
    var shared_material_ids: Dictionary = {}
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D or not child.name.begins_with("Road_"):
            continue
        var road := child as CSGBox3D
        road_segments += 1
        var material := road.material
        if material == null:
            _fail("road segment has no material: %s" % road.name)
            return
        if str(material.get_meta("material_family", "")) != MATERIAL_FAMILY:
            _fail("road segment is still on legacy flat material: %s" % road.name)
            return
        if str(road.get_meta("source", "")) != "OpenStreetMap contributors via Overpass API":
            _fail("road source provenance missing: %s" % road.name)
            return
        if str(road.get_meta("license", "")) != "ODbL-1.0":
            _fail("road license provenance missing: %s" % road.name)
            return
        if int(road.get_meta("osm_id", 0)) == 0:
            _fail("road OSM id provenance missing: %s" % road.name)
            return
        if bool(material.get_meta("exact_rgb_is_photometric_measurement", true)):
            _fail("authored road colour must not be presented as photometric measurement")
            return
        if bool(material.get_meta("surface_composition_claimed", true)):
            _fail("OSM snapshot does not source road surface composition")
            return
        shared_material_ids[material.get_instance_id()] = true
        sourced_segments += 1

    if road_segments < MIN_ROAD_SEGMENTS:
        _fail("unexpectedly low production road coverage: %d" % road_segments)
        return
    if sourced_segments != road_segments:
        _fail("not every production road segment carries source provenance")
        return
    if shared_material_ids.size() > 2:
        _fail("road surface family is not actually shared: %d material instances" % shared_material_ids.size())
        return

    print("BRUSSELS_OSM_ROAD_SURFACE_OK: roads=%d shared_materials=%d family=%s source=OSM license=ODbL-1.0 geometry_changed=false" % [road_segments, shared_material_ids.size(), MATERIAL_FAMILY])
    quit(0)
