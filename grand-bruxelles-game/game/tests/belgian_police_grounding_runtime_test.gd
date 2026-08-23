extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const GROUNDING_VERSION := "mesh-surface-v3"
const FOOT_CLEARANCE_M := 0.02
const CLEARANCE_TOLERANCE_M := 0.04
const MIN_SANE_BODY_HEIGHT_M := 1.50
const MAX_SANE_BODY_HEIGHT_M := 2.50
const SYNTHETIC_LOCAL_HEIGHT_M := 2.20

var _failed := false


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error("BELGIAN_POLICE_GROUNDING_FAIL: %s" % message)
    print("BELGIAN_POLICE_GROUNDING_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var main := packed.instantiate() as Node3D
    if main == null:
        _fail("main scene did not instantiate")
        return
    root.add_child(main)
    current_scene = main

    var visible_city := root.get_node_or_null("VisibleCityRuntime")
    if visible_city == null or not visible_city.has_method("ensure_zone_for_test"):
        _fail("VisibleCityRuntime unavailable")
        return

    var grounding_runtime: Node = null
    for _frame: int in range(30):
        grounding_runtime = root.get_node_or_null("BelgianPoliceGroundingRuntime")
        if grounding_runtime != null:
            break
        await process_frame
    if grounding_runtime == null:
        _fail("BelgianPoliceGroundingRuntime registry module unavailable")
        return

    if not _verify_local_visual_path(grounding_runtime):
        return

    visible_city.call("ensure_zone_for_test", "midi")
    for _frame: int in range(45):
        await process_frame
    for _frame: int in range(4):
        await physics_frame

    var police: Array[NpcAgent] = []
    for node: Node in get_nodes_in_group("police_officer"):
        if node is NpcAgent and (node == main or main.is_ancestor_of(node)):
            police.append(node as NpcAgent)
    if police.size() < 2:
        _fail("expected at least two behavioral police in Midi")
        return

    for agent: NpcAgent in police:
        var visual := agent.get_node_or_null("BelgianPoliceVisual") as Node3D
        if visual == null:
            _fail("BelgianPoliceVisual missing on %s" % agent.name)
            return
        var body := visual.get_node_or_null("CC0PoliceBody") as Node3D
        if body == null:
            _fail("public CC0PoliceBody missing on %s" % agent.name)
            return
        if str(visual.get_meta("grounding_version", "")) != GROUNDING_VERSION:
            _fail("surface grounding metadata missing on %s" % agent.name)
            return

        var bounds := _body_bounds_in_agent_space(visual, body)
        if bounds.size.y < MIN_SANE_BODY_HEIGHT_M or bounds.size.y > MAX_SANE_BODY_HEIGHT_M:
            _fail("public body height changed unexpectedly on %s: %.4f" % [agent.name, bounds.size.y])
            return

        var surface := _static_surface_below(agent)
        if surface.is_empty():
            _fail("no physical walk surface found under %s" % agent.name)
            return
        var surface_position: Vector3 = surface["position"]
        var foot_world_y := agent.global_position.y + bounds.position.y
        var clearance := foot_world_y - surface_position.y
        print("BELGIAN_POLICE_SURFACE_SAMPLE agent=%s agent_y=%.4f visual_y=%.4f foot_world_y=%.4f surface_y=%.4f clearance=%.4f height=%.4f collider=%s" % [
            agent.name,
            agent.global_position.y,
            visual.position.y,
            foot_world_y,
            surface_position.y,
            clearance,
            bounds.size.y,
            str(surface.get("collider", null)),
        ])
        if absf(clearance - FOOT_CLEARANCE_M) > CLEARANCE_TOLERANCE_M:
            _fail("rendered feet do not track physical surface on %s: foot_y=%.4f surface_y=%.4f clearance=%.4f" % [
                agent.name,
                foot_world_y,
                surface_position.y,
                clearance,
            ])
            return

        _log_foot_bones(body, surface_position.y, agent.name)

    print("BELGIAN_POLICE_GROUNDING_OK police=%d feet_on_physical_surface=true local_path_verified=true scale_preserved=true clearance=%.3f" % [
        police.size(),
        FOOT_CLEARANCE_M,
    ])
    quit(0)


func _verify_local_visual_path(grounding_runtime: Node) -> bool:
    var visual := Node3D.new()
    visual.name = "SyntheticLocalPoliceVisual"
    visual.set_meta("visual_source", "local_gta_derived")

    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = "SyntheticLocalBody"
    var box := BoxMesh.new()
    box.size = Vector3(0.62, SYNTHETIC_LOCAL_HEIGHT_M, 0.42)
    mesh_instance.mesh = box
    mesh_instance.position.y = -0.35
    visual.add_child(mesh_instance)

    if not bool(grounding_runtime.call("_ground_visual_for_test", visual)):
        _fail("local authored visual source was not accepted")
        visual.free()
        return false
    if str(visual.get_meta("grounding_version", "")) != GROUNDING_VERSION:
        _fail("local authored visual did not receive current grounding version")
        visual.free()
        return false

    var bounds := _node_bounds_in_parent_space(visual)
    if absf(bounds.size.y - SYNTHETIC_LOCAL_HEIGHT_M) > 0.01:
        _fail("local grounding changed authored scale: height=%.4f" % bounds.size.y)
        visual.free()
        return false
    if absf(bounds.position.y - FOOT_CLEARANCE_M) > 0.01:
        _fail("synthetic local model was not lifted to the foot plane: lowest_y=%.4f" % bounds.position.y)
        visual.free()
        return false

    print("BELGIAN_POLICE_LOCAL_PATH_OK lowest_y=%.4f height=%.4f scale=%.4f lift=%.4f" % [
        bounds.position.y,
        bounds.size.y,
        visual.scale.y,
        visual.position.y,
    ])
    visual.free()
    return true


func _static_surface_below(agent: NpcAgent) -> Dictionary:
    var world := agent.get_world_3d()
    if world == null:
        return {}
    var origin := agent.global_position
    var exclusions: Array[RID] = [agent.get_rid()]
    for _attempt: int in range(8):
        var query := PhysicsRayQueryParameters3D.create(
            origin + Vector3(0.0, 2.5, 0.0),
            origin - Vector3(0.0, 3.5, 0.0)
        )
        query.exclude = exclusions
        query.collide_with_areas = false
        query.collide_with_bodies = true
        var hit := world.direct_space_state.intersect_ray(query)
        if hit.is_empty():
            return {}
        var collider: Variant = hit.get("collider", null)
        if collider is StaticBody3D:
            return hit
        if collider is CollisionObject3D:
            exclusions.append((collider as CollisionObject3D).get_rid())
            continue
        return hit
    return {}


func _body_bounds_in_agent_space(visual: Node3D, body: Node3D) -> AABB:
    var state := {"found": false, "min": Vector3.ZERO, "max": Vector3.ZERO}
    _collect_bounds(body, visual.transform * body.transform, state)
    return _state_to_aabb(state)


func _node_bounds_in_parent_space(node: Node3D) -> AABB:
    var state := {"found": false, "min": Vector3.ZERO, "max": Vector3.ZERO}
    _collect_bounds(node, node.transform, state)
    return _state_to_aabb(state)


func _state_to_aabb(state: Dictionary) -> AABB:
    if not bool(state.get("found", false)):
        return AABB()
    var min_v: Vector3 = state["min"]
    var max_v: Vector3 = state["max"]
    return AABB(min_v, max_v - min_v)


func _collect_bounds(node: Node, current_transform: Transform3D, state: Dictionary) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.visible and mesh_instance.mesh != null:
            var bounds := mesh_instance.get_aabb()
            var origin := bounds.position
            var size := bounds.size
            var corners: Array[Vector3] = [
                origin,
                origin + Vector3(size.x, 0.0, 0.0),
                origin + Vector3(0.0, size.y, 0.0),
                origin + Vector3(0.0, 0.0, size.z),
                origin + Vector3(size.x, size.y, 0.0),
                origin + Vector3(size.x, 0.0, size.z),
                origin + Vector3(0.0, size.y, size.z),
                origin + size,
            ]
            for corner: Vector3 in corners:
                _include_point(state, current_transform * corner)
    for child: Node in node.get_children():
        var child_transform := current_transform
        if child is Node3D:
            child_transform = current_transform * (child as Node3D).transform
        _collect_bounds(child, child_transform, state)


func _include_point(state: Dictionary, point: Vector3) -> void:
    if not bool(state.get("found", false)):
        state["found"] = true
        state["min"] = point
        state["max"] = point
        return
    var min_v: Vector3 = state["min"]
    var max_v: Vector3 = state["max"]
    min_v.x = minf(min_v.x, point.x)
    min_v.y = minf(min_v.y, point.y)
    min_v.z = minf(min_v.z, point.z)
    max_v.x = maxf(max_v.x, point.x)
    max_v.y = maxf(max_v.y, point.y)
    max_v.z = maxf(max_v.z, point.z)
    state["min"] = min_v
    state["max"] = max_v


func _log_foot_bones(body: Node3D, surface_y: float, agent_name: String) -> void:
    var skeletons: Array[Skeleton3D] = []
    _collect_skeletons(body, skeletons)
    for skeleton: Skeleton3D in skeletons:
        for bone_index: int in range(skeleton.get_bone_count()):
            var bone_name := skeleton.get_bone_name(bone_index)
            var lower := str(bone_name).to_lower()
            if not ("foot" in lower or "toe" in lower or "ankle" in lower):
                continue
            var bone_pose := skeleton.get_bone_global_pose(bone_index)
            var bone_world := skeleton.global_transform * bone_pose.origin
            print("BELGIAN_POLICE_FOOT_BONE agent=%s bone=%s world_y=%.4f surface_delta=%.4f" % [
                agent_name,
                bone_name,
                bone_world.y,
                bone_world.y - surface_y,
            ])


func _collect_skeletons(node: Node, output: Array[Skeleton3D]) -> void:
    if node is Skeleton3D:
        output.append(node as Skeleton3D)
    for child: Node in node.get_children():
        _collect_skeletons(child, output)