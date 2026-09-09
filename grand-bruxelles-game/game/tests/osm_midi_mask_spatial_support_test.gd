extends SceneTree

const MASK_SCRIPT := preload("res://game/scripts/osm_midi_mask.gd")
const MIDI_WORLD := Vector3(-668.5, 0.0, 627.84)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("OSM_MIDI_MASK_SPATIAL_SUPPORT_FAIL: %s" % message)
    quit(1)

func _road(name: String, offset_x: float) -> CSGBox3D:
    var road := CSGBox3D.new()
    road.name = name
    road.size = Vector3(8.0, 0.10, 18.0)
    road.position = MIDI_WORLD + Vector3(offset_x, 0.025, 0.0)
    road.visible = true
    return road

func _authoritative_surface(offset_x: float) -> MeshInstance3D:
    var instance := MeshInstance3D.new()
    instance.name = "ExactRoadCarriageways"
    var mesh := BoxMesh.new()
    mesh.size = Vector3(10.0, 0.10, 24.0)
    instance.mesh = mesh
    instance.position = MIDI_WORLD + Vector3(offset_x, 0.075, 0.0)
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

    var covered := _road("Road_covered", 0.0)
    var unsupported := _road("Road_unsupported", 80.0)
    roads.add_child(covered)
    roads.add_child(unsupported)

    var buildings := Node3D.new()
    buildings.name = "GeneratedBuildings"
    osm.add_child(buildings)

    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    scene.add_child(urbis)
    var surfaces := Node3D.new()
    surfaces.name = "UrbISStreetSurfaces"
    urbis.add_child(surfaces)
    surfaces.add_child(_authoritative_surface(0.0))

    var mask := Node.new()
    mask.name = "OSMMidiMask"
    mask.set_script(MASK_SCRIPT)
    scene.add_child(mask)

    await process_frame
    await physics_frame
    mask.call("_apply_mask")
    await process_frame

    if covered.visible:
        _fail("OSM road with concrete official UrbIS surface support stayed visible")
        return
    if not unsupported.visible:
        _fail("OSM road without spatially overlapping official UrbIS support was hidden by the blanket Midi radius")
        return

    print("OSM_MIDI_MASK_SPATIAL_SUPPORT_OK: covered_hidden=true unsupported_fallback_visible=true radius_unchanged=true")
    quit(0)
