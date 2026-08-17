extends SceneTree

const BUILDER := preload("res://game/scripts/urbis_midi_builder.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_EXACT_BUILDING_COLLISION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var builder: Node3D = BUILDER.new()
    builder.name = "MidiCollisionProbe"
    root.add_child(builder)
    await process_frame
    await physics_frame

    var exact_root: Node = builder.get_node_or_null("UrbISExactBuildings")
    if exact_root == null:
        _fail("UrbISExactBuildings runtime root is missing")
        return

    var mesh_count := 0
    var static_body_count := 0
    var first_mesh: MeshInstance3D = null
    for child: Node in exact_root.get_children():
        if child is not MeshInstance3D:
            continue
        var mesh_instance := child as MeshInstance3D
        mesh_count += 1
        if first_mesh == null and mesh_instance.mesh != null:
            first_mesh = mesh_instance
        var has_valid_static := false
        for nested: Node in mesh_instance.get_children():
            if nested is not StaticBody3D:
                continue
            var body := nested as StaticBody3D
            if body.collision_layer != 1 or body.collision_mask != 1:
                _fail("%s collider must stay on player/world layer+mask 1" % mesh_instance.name)
                return
            var has_shape := false
            for shape_node: Node in body.get_children():
                if shape_node is CollisionShape3D and (shape_node as CollisionShape3D).shape != null:
                    has_shape = true
                    break
            if has_shape:
                has_valid_static = true
                static_body_count += 1
                break
        if not has_valid_static:
            _fail("%s is visible UrbIS Midi geometry without a StaticBody3D collision" % mesh_instance.name)
            return

    if mesh_count == 0 or first_mesh == null:
        _fail("no exact Midi building mesh batches were built")
        return
    if static_body_count != mesh_count:
        _fail("expected one valid static collision per exact building mesh batch")
        return

    var arrays := first_mesh.mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    if vertices.size() < 3:
        _fail("first exact building mesh has no wall triangle for forced-contact probe")
        return
    var a := first_mesh.to_global(vertices[0])
    var b := first_mesh.to_global(vertices[1])
    var c := first_mesh.to_global(vertices[2])
    var normal := (b - a).cross(c - a).normalized()
    if normal.length_squared() < 0.5:
        _fail("forced-contact wall triangle has invalid normal")
        return
    var center := (a + b + c) / 3.0
    var query := PhysicsRayQueryParameters3D.create(center + normal * 1.5, center - normal * 1.5, 1)
    var hit := builder.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        _fail("forced contact ray crossed an exact Midi building wall without physics hit")
        return
    if hit.get("collider") is not StaticBody3D:
        _fail("forced contact hit was not a StaticBody3D building collider")
        return

    print("MIDI_EXACT_BUILDING_COLLISION_OK: %d exact mesh batches solid; forced wall contact blocked" % mesh_count)
    builder.queue_free()
    quit(0)
