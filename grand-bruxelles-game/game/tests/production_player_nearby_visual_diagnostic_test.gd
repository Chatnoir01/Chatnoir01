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

func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
    var ab := b - a
    var denom := ab.length_squared()
    if denom <= 0.000001:
        return point.distance_to(a)
    var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
    return point.distance_to(a + ab * t)

func _walk(node: Node, player: Node3D, camera: Camera3D) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.is_visible_in_tree():
            var player_distance := mesh_instance.global_position.distance_to(player.global_position)
            var corridor_distance := _distance_to_segment(mesh_instance.global_position, camera.global_position, player.global_position)
            if player_distance <= 6.0 or corridor_distance <= 1.0:
                print("PLAYER_NEARBY_VISUAL: path=%s player_distance=%.3f corridor_distance=%.3f pos=%s mesh=%s color=%s" % [str(mesh_instance.get_path()), player_distance, corridor_distance, str(mesh_instance.global_position), mesh_instance.mesh.get_class() if mesh_instance.mesh != null else "null", _material_color(mesh_instance)])
    elif node is CSGShape3D:
        var csg := node as CSGShape3D
        if csg.is_visible_in_tree():
            var player_distance := csg.global_position.distance_to(player.global_position)
            var corridor_distance := _distance_to_segment(csg.global_position, camera.global_position, player.global_position)
            if player_distance <= 6.0 or corridor_distance <= 1.0:
                print("PLAYER_NEARBY_CSG: path=%s player_distance=%.3f corridor_distance=%.3f pos=%s type=%s" % [str(csg.get_path()), player_distance, corridor_distance, str(csg.global_position), csg.get_class()])
    elif node is MultiMeshInstance3D:
        var multi := node as MultiMeshInstance3D
        if multi.is_visible_in_tree():
            var player_distance := multi.global_position.distance_to(player.global_position)
            var corridor_distance := _distance_to_segment(multi.global_position, camera.global_position, player.global_position)
            if player_distance <= 6.0 or corridor_distance <= 1.0:
                print("PLAYER_NEARBY_MULTIMESH: path=%s player_distance=%.3f corridor_distance=%.3f pos=%s instances=%d" % [str(multi.get_path()), player_distance, corridor_distance, str(multi.global_position), multi.multimesh.instance_count if multi.multimesh != null else 0])
    for child in node.get_children():
        _walk(child, player, camera)

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
    var camera := scene.get_node_or_null("Player/CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if player == null or camera == null:
        push_error("PLAYER_NEARBY_VISUAL_DIAGNOSTIC_FAIL: player or gameplay camera missing")
        quit(1)
        return
    print("PLAYER_NEARBY_VISUAL_DIAGNOSTIC_BEGIN: player=%s camera=%s" % [str(player.global_position), str(camera.global_position)])
    _walk(scene, player, camera)
    print("PLAYER_NEARBY_VISUAL_DIAGNOSTIC_OK")
    scene.queue_free()
    quit(0)
