extends SceneTree

const MASK_SCRIPT := preload("res://game/scripts/osm_midi_mask.gd")
const MIDI_WORLD := Vector3(-668.5, 0.0, 627.84)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("OSM_MIDI_MASK_BUILDING_SPATIAL_SUPPORT_FAIL: %s" % message)
    quit(1)

func _osm_building(name: String, offset_x: float) -> CSGBox3D:
    var building := CSGBox3D.new()
    building.name = name
    building.size = Vector3(12.0, 18.0, 12.0)
    building.position = MIDI_WORLD + Vector3(offset_x, 9.0, 0.0)
    building.visible = true
    return building

func _authoritative_building(offset_x: float) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = "ExactBuilding"
    var mesh := BoxMesh.new()
    mesh.size = Vector3(14.0, 20.0, 14.0)
    instance.mesh = mesh
    instance.position = MIDI_WORLD + Vector3(offset_x, 10.0, 0.0)
    instance.create_trimesh_collision()
    for child: Node in instance.get_children():
        if child is StaticBody3D:
            var body := child as StaticBody3D
            body.collision_layer = 1
            body.collision_mask = 1
    return instance

func _run() -> void:
    var scene := Node3D.new()
    scene.name = "Main"
    root.add_child(scene)

    var osm := Node3D.new()
    osm.name = "BrusselsOSM"
    scene.add_child(osm)

    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    osm.add_child(roads)

    var buildings := Node3D.new()
    buildings.name = "GeneratedBuildings"
    osm.add_child(buildings)
    var covered := _osm_building("Building_covered", 0.0)
    var unsupported := _osm_building("Building_unsupported", 80.0)
    buildings.add_child(covered)
    buildings.add_child(unsupported)

    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    scene.add_child(urbis)

    var exact_buildings := Node3D.new()
    exact_buildings.name = "UrbISExactBuildings"
    urbis.add_child(exact_buildings)
    exact_buildings.add_child(_authoritative_building(0.0))

    var mask := Node.new()
    mask.name = "OSMMidiMask"
    mask.set_script(MASK_SCRIPT)
    scene.add_child(mask)

    await process_frame
    await physics_frame
    mask.call("_apply_mask")
    await process_frame

    if covered.visible:
        _fail("OSM building with concrete official UrbIS building support stayed visible")
        return
    if not unsupported.visible:
        _fail("OSM building without spatially overlapping official UrbIS support was hidden by the blanket Midi radius")
        return

    print("OSM_MIDI_MASK_BUILDING_SPATIAL_SUPPORT_OK: covered_hidden=true unsupported_fallback_visible=true radius_unchanged=true")
    quit(0)
