extends SceneTree

const MASK_SCRIPT := preload("res://game/scripts/osm_midi_mask.gd")
const MIDI_WORLD := Vector3(-668.5, 0.0, 627.84)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("OSM_MIDI_MASK_AUTHORITATIVE_AVAILABILITY_FAIL: %s" % message)
    quit(1)

func _geometry(name: String) -> CSGBox3D:
    var geometry := CSGBox3D.new()
    geometry.name = name
    geometry.position = MIDI_WORLD
    geometry.size = Vector3(8.0, 0.2, 8.0)
    geometry.visible = true
    return geometry

func _authoritative_mesh(name: String) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = name
    var mesh := BoxMesh.new()
    mesh.size = Vector3(8.0, 0.2, 8.0)
    instance.mesh = mesh
    instance.position = MIDI_WORLD + Vector3(0.0, 0.075, 0.0)
    instance.visible = true
    instance.create_trimesh_collision()
    for child: Node in instance.get_children():
        if child is StaticBody3D:
            var body := child as StaticBody3D
            body.collision_layer = 1
            body.collision_mask = 1
    return instance

func _fixture(with_surfaces: bool, with_buildings: bool) -> Dictionary:
    var scene := Node3D.new()
    scene.name = "Main"
    root.add_child(scene)

    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    scene.add_child(osm)

    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    osm.add_child(roads)
    var road := _geometry("Road_1_0_0")
    roads.add_child(road)

    var buildings := Node3D.new()
    buildings.name = "GeneratedBuildings"
    osm.add_child(buildings)
    var building := _geometry("Building_1")
    buildings.add_child(building)

    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    scene.add_child(urbis)
    if with_surfaces:
        var surfaces := Node3D.new()
        surfaces.name = "UrbISStreetSurfaces"
        urbis.add_child(surfaces)
        surfaces.add_child(_authoritative_mesh("ExactRoadCarriageways"))
    if with_buildings:
        var exact_buildings := Node3D.new()
        exact_buildings.name = "UrbISExactBuildings"
        urbis.add_child(exact_buildings)
        exact_buildings.add_child(_authoritative_mesh("ExactBuildings_0"))

    var mask := Node.new()
    mask.name = "OSMMidiMask"
    mask.set_script(MASK_SCRIPT)
    scene.add_child(mask)
    return {"scene": scene, "road": road, "building": building, "mask": mask}

func _settle_and_apply(fixture: Dictionary) -> void:
    await process_frame
    await physics_frame
    (fixture["mask"] as Node).call("_apply_mask")
    await process_frame

func _destroy(fixture: Dictionary) -> void:
    var scene: Node = fixture["scene"]
    scene.queue_free()
    await process_frame

func _run() -> void:
    var absent := _fixture(false, false)
    await _settle_and_apply(absent)
    if not (absent["road"] as Node3D).visible or not (absent["building"] as Node3D).visible:
        _fail("OSM fallback geometry was hidden without materialized authoritative UrbIS replacement")
        return
    await _destroy(absent)

    var surfaces_only := _fixture(true, false)
    await _settle_and_apply(surfaces_only)
    if (surfaces_only["road"] as Node3D).visible:
        _fail("OSM road fallback stayed visible despite spatially overlapping authoritative UrbIS street surfaces")
        return
    if not (surfaces_only["building"] as Node3D).visible:
        _fail("OSM building fallback was hidden without materialized authoritative UrbIS buildings")
        return
    await _destroy(surfaces_only)

    var buildings_only := _fixture(false, true)
    await _settle_and_apply(buildings_only)
    if not (buildings_only["road"] as Node3D).visible:
        _fail("OSM road fallback was hidden without materialized authoritative UrbIS street surfaces")
        return
    if (buildings_only["building"] as Node3D).visible:
        _fail("OSM building fallback stayed visible despite materialized authoritative UrbIS buildings")
        return
    await _destroy(buildings_only)

    print("OSM_MIDI_MASK_AUTHORITATIVE_AVAILABILITY_OK: absent_preserves_fallback=true surfaces_mask_spatially_supported_roads_only=true buildings_mask_buildings_only=true")
    quit(0)
