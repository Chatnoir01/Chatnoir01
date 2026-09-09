extends SceneTree

const MASK_SCRIPT := preload("res://game/scripts/osm_midi_mask.gd")
const MIDI_WORLD := Vector3(-668.5, 0.0, 627.84)

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("OSM_MIDI_MASK_FACADE_MULTIMESH_SPATIAL_SUPPORT_FAIL: %s" % message)
    quit(1)

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

func _append_transform_3d(buffer: PackedFloat32Array, transform: Transform3D) -> void:
    # MultiMesh.buffer stores 3D transforms row-major. Build the fixture through
    # the same renderer-facing representation that is consumed by instancing so
    # the regression stays deterministic under the CI headless renderer.
    buffer.append(transform.basis.x.x)
    buffer.append(transform.basis.y.x)
    buffer.append(transform.basis.z.x)
    buffer.append(transform.origin.x)
    buffer.append(transform.basis.x.y)
    buffer.append(transform.basis.y.y)
    buffer.append(transform.basis.z.y)
    buffer.append(transform.origin.y)
    buffer.append(transform.basis.x.z)
    buffer.append(transform.basis.y.z)
    buffer.append(transform.basis.z.z)
    buffer.append(transform.origin.z)

func _facade_multimesh() -> MultiMeshInstance3D:
    var mesh := BoxMesh.new()
    mesh.size = Vector3.ONE
    var multimesh := MultiMesh.new()
    multimesh.transform_format = MultiMesh.TRANSFORM_3D
    multimesh.mesh = mesh
    multimesh.instance_count = 4
    # The fourth instance is allocated but intentionally hidden. Filtering one
    # supported visible facade must not promote this tail into the rendered set.
    multimesh.visible_instance_count = 3
    var buffer := PackedFloat32Array()
    _append_transform_3d(buffer, Transform3D(Basis().scaled(Vector3(4.0, 4.0, 0.3)), MIDI_WORLD + Vector3(0.0, 10.0, 0.0)))
    _append_transform_3d(buffer, Transform3D(Basis().scaled(Vector3(4.0, 4.0, 0.3)), MIDI_WORLD + Vector3(80.0, 10.0, 0.0)))
    _append_transform_3d(buffer, Transform3D(Basis().scaled(Vector3(4.0, 4.0, 0.3)), MIDI_WORLD + Vector3(700.0, 10.0, 0.0)))
    _append_transform_3d(buffer, Transform3D(Basis().scaled(Vector3(4.0, 4.0, 0.3)), MIDI_WORLD + Vector3(720.0, 10.0, 0.0)))
    multimesh.buffer = buffer
    var instance := MultiMeshInstance3D.new()
    instance.name = "CorridorFacadeWindows"
    instance.multimesh = multimesh
    return instance

func _origin_near(actual: Vector3, expected: Vector3) -> bool:
    return actual.distance_to(expected) <= 0.001

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
    var details := Node3D.new()
    details.name = "GeneratedFacadeDetails"
    osm.add_child(details)
    var facade_batch := _facade_multimesh()
    details.add_child(facade_batch)
    var urbis := Node3D.new()
    urbis.name = "UrbISMidiExact"
    scene.add_child(urbis)
    var street_surfaces := Node3D.new()
    street_surfaces.name = "UrbISStreetSurfaces"
    urbis.add_child(street_surfaces)
    var exact_buildings := Node3D.new()
    exact_buildings.name = "UrbISExactBuildings"
    urbis.add_child(exact_buildings)
    exact_buildings.add_child(_authoritative_building(0.0))

    # Keep the mask in a harness without BrusselsOSM/UrbISMidiExact siblings for
    # its first deferred _apply_mask(). This preserves the production _ready()
    # behavior while allowing the test to prove its spatial precondition before
    # the one explicit application under the real sibling layout.
    var probe_harness := Node3D.new()
    probe_harness.name = "MaskProbeHarness"
    scene.add_child(probe_harness)
    var mask := Node.new()
    mask.name = "OSMMidiMask"
    mask.set_script(MASK_SCRIPT)
    probe_harness.add_child(mask)

    await process_frame
    await physics_frame
    var vertical_span: Vector2 = mask.call("_authoritative_geometry_vertical_span", exact_buildings)
    var source_transform: Transform3D = mask.call("_multimesh_transform_from_buffer", facade_batch.multimesh, 0)
    var world_sample: Vector3 = mask.call("_multimesh_instance_world_sample", facade_batch, source_transform)
    var direct_support: bool = mask.call("_authoritative_support_between", world_sample, exact_buildings, vertical_span.y, vertical_span.x)
    print("OSM_MIDI_MASK_FACADE_MULTIMESH_DIAGNOSTIC: sample=%s span=%s inside=%s support=%s buffer_floats=%d visible=%d" % [str(world_sample), str(vertical_span), str(mask.call("_inside", world_sample)), str(direct_support), facade_batch.multimesh.buffer.size(), facade_batch.multimesh.visible_instance_count])
    if facade_batch.multimesh.buffer.size() != 48 or facade_batch.multimesh.visible_instance_count != 3:
        _fail("precondition batch changed before explicit mask application")
        return
    if not direct_support:
        _fail("covered MultiMesh transform did not resolve concrete UrbIS collision support; sample=%s span=%s" % [str(world_sample), str(vertical_span)])
        return

    mask.reparent(scene)
    mask.call("_apply_mask")
    await process_frame
    if facade_batch.multimesh == null:
        _fail("CorridorFacadeWindows lost its MultiMesh resource")
        return
    if facade_batch.multimesh.instance_count != 3:
        _fail("expected one supported visible Midi facade to be removed while visible fallbacks and hidden tail remain; got %d instances" % facade_batch.multimesh.instance_count)
        return
    if facade_batch.multimesh.visible_instance_count != 2:
        _fail("hidden MultiMesh tail was promoted or visible-instance contract changed; got visible_instance_count=%d" % facade_batch.multimesh.visible_instance_count)
        return
    if facade_batch.multimesh.buffer.size() != 36:
        _fail("filtered renderer buffer has unexpected 3D payload size: %d" % facade_batch.multimesh.buffer.size())
        return
    var first_transform: Transform3D = mask.call("_multimesh_transform_from_buffer", facade_batch.multimesh, 0)
    var second_transform: Transform3D = mask.call("_multimesh_transform_from_buffer", facade_batch.multimesh, 1)
    var third_transform: Transform3D = mask.call("_multimesh_transform_from_buffer", facade_batch.multimesh, 2)
    var expected_unsupported := MIDI_WORLD + Vector3(80.0, 10.0, 0.0)
    var expected_outside := MIDI_WORLD + Vector3(700.0, 10.0, 0.0)
    var expected_hidden_tail := MIDI_WORLD + Vector3(720.0, 10.0, 0.0)
    if not _origin_near(first_transform.origin, expected_unsupported) or not _origin_near(second_transform.origin, expected_outside):
        _fail("remaining visible MultiMesh transforms were moved/reordered incorrectly: first=%s second=%s" % [str(first_transform.origin), str(second_transform.origin)])
        return
    if not _origin_near(third_transform.origin, expected_hidden_tail):
        _fail("allocated hidden MultiMesh tail was not preserved byte-order-equivalently: third=%s" % str(third_transform.origin))
        return
    if not facade_batch.is_visible_in_tree() or not details.visible:
        _fail("facade batch or parent was hidden wholesale instead of filtering only supported Midi instances")
        return
    print("OSM_MIDI_MASK_FACADE_MULTIMESH_SPATIAL_SUPPORT_OK: supported_removed=1 unsupported_preserved=1 outside_radius_preserved=1 hidden_tail_preserved=1 visible_count_preserved=true source_positions_preserved=true renderer_buffer_preserved=true radius_unchanged=true")
    quit(0)