extends Node

# Visual-only grounding for authored Belgian police models.
# NpcAgent remains the owner of movement, navigation, collision and police AI.
# We derive the visual foot plane from real mesh bounds, then keep that plane on
# the nearest static walk surface instead of trusting a model-specific Y guess.
const SOURCE_GROUP := "police_officer"
const VISUAL_NODE_NAME := "BelgianPoliceVisual"
const BODY_NODE_NAME := "CC0PoliceBody"
const PUBLIC_VISUAL_SOURCE := "public_cc0_authored"
const LOCAL_VISUAL_SOURCE := "local_gta_derived"
const MIN_VALID_BODY_HEIGHT_M := 0.20
const FOOT_CLEARANCE_M := 0.02
const RAY_UP_M := 2.5
const RAY_DOWN_M := 3.5
const MAX_RAY_SKIPS := 8
const GROUNDING_VERSION := "mesh-surface-v3"


func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    get_tree().node_added.connect(_on_node_added)
    call_deferred("_ground_existing_police")


func _physics_process(_delta: float) -> void:
    # Only a handful of behavioral police exist per active zone. Re-snapping their
    # visual wrapper keeps feet on ramps/sidewalks while leaving the CharacterBody
    # and its navigation route untouched.
    for node: Node in get_tree().get_nodes_in_group(SOURCE_GROUP):
        if node is NpcAgent:
            var agent := node as NpcAgent
            var visual := agent.get_node_or_null(VISUAL_NODE_NAME) as Node3D
            if visual == null:
                continue
            if str(visual.get_meta("grounding_version", "")) != GROUNDING_VERSION:
                _ground_visual(visual, str(agent.name))
            _snap_visual_to_surface(agent, visual)


func _on_node_added(node: Node) -> void:
    if node is NpcAgent and node.is_in_group(SOURCE_GROUP):
        call_deferred("_ground_agent", node)
        return
    if node is Node3D and str(node.name) == VISUAL_NODE_NAME:
        call_deferred("_ground_existing_police")


func _ground_existing_police() -> void:
    for node: Node in get_tree().get_nodes_in_group(SOURCE_GROUP):
        if node is NpcAgent:
            _ground_agent(node as NpcAgent)


func _ground_agent(agent: NpcAgent) -> void:
    if agent == null or not is_instance_valid(agent):
        return
    var visual := agent.get_node_or_null(VISUAL_NODE_NAME) as Node3D
    if visual == null:
        return
    if _ground_visual(visual, str(agent.name)):
        _snap_visual_to_surface(agent, visual)


func _ground_visual_for_test(visual: Node3D) -> bool:
    return _ground_visual(visual, "test")


func _ground_visual(visual: Node3D, agent_name: String) -> bool:
    if visual == null or not is_instance_valid(visual):
        return false
    if str(visual.get_meta("grounding_version", "")) == GROUNDING_VERSION:
        return true

    var visual_source := str(visual.get_meta("visual_source", ""))
    var bounds_root: Node3D = null
    if visual_source == PUBLIC_VISUAL_SOURCE:
        bounds_root = visual.get_node_or_null(BODY_NODE_NAME) as Node3D
    elif visual_source == LOCAL_VISUAL_SOURCE:
        # The ignored Belgian model can have any authoring pivot. Measure its real
        # visible geometry and replace the legacy hard-coded wrapper offset.
        bounds_root = visual
    else:
        return false

    if bounds_root == null:
        return false
    var bounds := _visible_mesh_bounds(bounds_root)
    if bounds.size.y < MIN_VALID_BODY_HEIGHT_M:
        push_warning("Belgian police grounding skipped: %s mesh bounds are not measurable" % visual_source)
        return false

    # Preserve authored size. This bug is vertical placement, not character scale.
    # For a positive wrapper scale, p_world = wrapper_y + p_mesh * scale_y.
    var scale_y := visual.scale.y
    var base_lift := -bounds.position.y * scale_y
    visual.position.y = base_lift + FOOT_CLEARANCE_M
    visual.set_meta("grounding_version", GROUNDING_VERSION)
    visual.set_meta("grounding_source", visual_source)
    visual.set_meta("source_body_height_m", bounds.size.y)
    visual.set_meta("source_body_min_y", bounds.position.y)
    visual.set_meta("grounding_base_lift_y", base_lift)
    visual.set_meta("grounding_clearance_m", FOOT_CLEARANCE_M)
    visual.set_meta("grounding_surface_y", NAN)

    print("BELGIAN_POLICE_MESH_GROUNDED agent=%s source=%s source_height=%.4f source_min_y=%.4f scale_y=%.4f base_lift=%.4f" % [
        agent_name,
        visual_source,
        bounds.size.y,
        bounds.position.y,
        scale_y,
        base_lift,
    ])
    return true


func _snap_visual_to_surface(agent: NpcAgent, visual: Node3D) -> void:
    if agent == null or visual == null or not is_instance_valid(agent) or not is_instance_valid(visual):
        return
    if str(visual.get_meta("grounding_version", "")) != GROUNDING_VERSION:
        return

    var base_lift := float(visual.get_meta("grounding_base_lift_y", visual.position.y - FOOT_CLEARANCE_M))
    var hit := _static_surface_below(agent)
    if hit.is_empty():
        visual.position.y = base_lift + FOOT_CLEARANCE_M
        return

    var surface_position: Vector3 = hit.get("position", agent.global_position)
    var surface_delta := surface_position.y - agent.global_position.y
    visual.position.y = base_lift + surface_delta + FOOT_CLEARANCE_M
    visual.set_meta("grounding_surface_y", surface_position.y)
    visual.set_meta("grounding_surface_delta_y", surface_delta)


func _static_surface_below(agent: NpcAgent) -> Dictionary:
    var world := agent.get_world_3d()
    if world == null:
        return {}

    var origin := agent.global_position
    var exclusions: Array[RID] = [agent.get_rid()]
    for _attempt: int in range(MAX_RAY_SKIPS):
        var query := PhysicsRayQueryParameters3D.create(
            origin + Vector3(0.0, RAY_UP_M, 0.0),
            origin - Vector3(0.0, RAY_DOWN_M, 0.0)
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


func _visible_mesh_bounds(root_node: Node3D) -> AABB:
    var state := {
        "found": false,
        "min": Vector3.ZERO,
        "max": Vector3.ZERO,
    }
    _collect_visible_mesh_bounds(root_node, root_node, Transform3D.IDENTITY, state)
    if not bool(state.get("found", false)):
        return AABB()
    var min_v: Vector3 = state["min"]
    var max_v: Vector3 = state["max"]
    return AABB(min_v, max_v - min_v)


func _collect_visible_mesh_bounds(root_node: Node3D, node: Node, parent_transform: Transform3D, state: Dictionary) -> void:
    var current := parent_transform
    if node != root_node and node is Node3D:
        current = parent_transform * (node as Node3D).transform

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
                _include_point(state, current * corner)

    for child: Node in node.get_children():
        _collect_visible_mesh_bounds(root_node, child, current, state)


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