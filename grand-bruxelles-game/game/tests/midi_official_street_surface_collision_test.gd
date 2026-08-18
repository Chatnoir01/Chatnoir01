extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const REQUIRED_SURFACES := [
    "ExactRoadCarriageways",
    "ExactSidewalks",
    "ExactTrafficIslands",
    "ExactPavedAreas",
    "ExactOtherStreetSurfaces",
]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_OFFICIAL_STREET_COLLISION_FAIL: %s" % message)
    quit(1)

func _surface_static_body(mesh_instance: MeshInstance3D) -> StaticBody3D:
    for child: Node in mesh_instance.get_children():
        if child is StaticBody3D:
            var body := child as StaticBody3D
            if body.collision_layer != 1 or body.collision_mask != 1:
                return null
            for shape_child: Node in body.get_children():
                if shape_child is CollisionShape3D and (shape_child as CollisionShape3D).shape != null:
                    return body
    return null

func _triangle_centroid(mesh_instance: MeshInstance3D) -> Vector3:
    if mesh_instance.mesh == null or mesh_instance.mesh.get_surface_count() == 0:
        return Vector3.INF
    var arrays := mesh_instance.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.size() < 3:
        return Vector3.INF
    return mesh_instance.to_global((vertices[0] + vertices[1] + vertices[2]) / 3.0)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(8):
        await process_frame
    await physics_frame

    var builder := main.get_node_or_null("UrbISMidiExact") as Node3D
    if builder == null:
        _fail("UrbISMidiExact missing from production scene")
        return
    var surfaces := builder.get_node_or_null("UrbISStreetSurfaces")
    if surfaces == null:
        _fail("official Midi street-surface root missing")
        return

    var checked := 0
    var contact_mesh: MeshInstance3D = null
    var contact_body: StaticBody3D = null
    for surface_name: String in REQUIRED_SURFACES:
        var mesh := surfaces.get_node_or_null(surface_name) as MeshInstance3D
        if mesh == null or mesh.mesh == null or mesh.mesh.get_surface_count() == 0:
            continue
        checked += 1
        var body := _surface_static_body(mesh)
        if body == null:
            _fail("official surface %s has no player-foot StaticBody3D trimesh collision" % surface_name)
            return
        if contact_mesh == null:
            contact_mesh = mesh
            contact_body = body

    if checked < 4:
        _fail("too few official surface families reached runtime: %d" % checked)
        return
    if contact_mesh == null or contact_body == null:
        _fail("no populated official surface available for physical contact proof")
        return

    var centroid := _triangle_centroid(contact_mesh)
    if not centroid.is_finite():
        _fail("official surface has no triangle for contact proof")
        return

    # First prove the exact rendered triangle is visible to PhysicsServer3D.
    var ray := PhysicsRayQueryParameters3D.create(centroid + Vector3.UP * 2.0, centroid + Vector3.DOWN * 2.0, 1)
    var hit := builder.get_world_3d().direct_space_state.intersect_ray(ray)
    if hit.is_empty():
        _fail("ray crossed an official street triangle without physics contact")
        return
    if hit.get("collider") != contact_body:
        _fail("official street contact ray hit a different collider")
        return

    # Then use a real player-like CharacterBody3D capsule and force one downward
    # motion through the same point. A valid collision proves the player cannot
    # simply ghost through the official street surface.
    var probe := CharacterBody3D.new()
    probe.name = "OfficialStreetPlayerFootProbe"
    probe.collision_layer = 1
    probe.collision_mask = 1
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.30
    capsule.height = 1.70
    var shape := CollisionShape3D.new()
    shape.shape = capsule
    probe.add_child(shape)
    builder.add_child(probe)
    probe.global_position = centroid + Vector3.UP * 1.40
    await physics_frame
    var contact := probe.move_and_collide(Vector3.DOWN * 2.0)
    if contact == null:
        _fail("player-foot capsule crossed the official street surface without collision")
        return
    if contact.get_collider() != contact_body:
        _fail("player-foot capsule contacted a different collider than the official street surface")
        return
    if probe.global_position.y <= centroid.y:
        _fail("player-foot capsule ended below the official street surface")
        return

    print("MIDI_OFFICIAL_STREET_COLLISION_OK: solid_surface_families=%d source_geometry_reused=true ray_contact=true player_capsule_blocked=true contact_surface=%s" % [checked, contact_mesh.name])
    main.queue_free()
    quit(0)
