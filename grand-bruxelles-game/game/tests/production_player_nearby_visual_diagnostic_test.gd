extends SceneTree

func _initialize() -> void:
    call_deferred("_run")

func _material_color(instance: MeshInstance3D) -> String:
    var material: Material = instance.material_override
    if material == null and instance.mesh != null and instance.mesh.get_surface_count() > 0:
        material = instance.mesh.surface_get_material(0)
    if material is StandardMaterial3D:
        return str((material as StandardMaterial3D).albedo_color)
    return "none"

func _walk(node: Node, player: Node3D) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.is_visible_in_tree():
            var distance := mesh_instance.global_position.distance_to(player.global_position)
            if distance <= 3.0:
                print("PLAYER_NEARBY_VISUAL: path=%s distance=%.3f pos=%s mesh=%s color=%s" % [str(mesh_instance.get_path()), distance, str(mesh_instance.global_position), mesh_instance.mesh.get_class() if mesh_instance.mesh != null else "null", _material_color(mesh_instance)])
    elif node is CSGShape3D:
        var csg := node as CSGShape3D
        if csg.is_visible_in_tree():
            var distance := csg.global_position.distance_to(player.global_position)
            if distance <= 3.0:
                print("PLAYER_NEARBY_CSG: path=%s distance=%.3f pos=%s type=%s" % [str(csg.get_path()), distance, str(csg.global_position), csg.get_class()])
    for child in node.get_children():
        _walk(child, player)

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        push_error("PLAYER_NEARBY_VISUAL_DIAGNOSTIC_FAIL: main scene did not load")
        quit(1)
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    var traffic_manager := scene.get_node_or_null("TrafficManager")
    if traffic_manager != null:
        traffic_manager.set("auto_spawn_runtime", false)
    for _frame in range(100):
        await process_frame
    var player := scene.get_node_or_null("Player") as Node3D
    if player == null:
        push_error("PLAYER_NEARBY_VISUAL_DIAGNOSTIC_FAIL: player missing")
        quit(1)
        return
    print("PLAYER_NEARBY_VISUAL_DIAGNOSTIC_BEGIN: player=%s" % str(player.global_position))
    _walk(scene, player)
    print("PLAYER_NEARBY_VISUAL_DIAGNOSTIC_OK")
    scene.queue_free()
    quit(0)
