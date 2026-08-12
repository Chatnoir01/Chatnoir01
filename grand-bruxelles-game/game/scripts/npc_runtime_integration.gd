class_name NpcRuntimeIntegration
extends Node

@export var population_director_path: NodePath = NodePath("../NpcPopulationDirector")
@export var traffic_manager_path: NodePath = NodePath("../TrafficManager")
@export var observer_path: NodePath = NodePath("../Player")
@export var observer_refresh_interval_s: float = 0.25
@export var crowd_spacing_interval_s: float = 0.20
@export var crowd_personal_space_m: float = 0.95
@export var crowd_release_space_m: float = 1.25

var _director: NpcPopulationDirector = null
var _traffic_manager: Node = null
var _observer: Node3D = null
var _observer_elapsed_s: float = 0.0
var _crowd_elapsed_s: float = 0.0
var _configured: bool = false
var _agents: Array[NpcAgent] = []
var _crowd_spacing := NpcCrowdSpacing.new()
var _crowd_detours: Dictionary = {}
var _ambient_elapsed_s: Dictionary = {}
var _ambient_holds: Dictionary = {}

func _ready() -> void:
    _crowd_spacing.personal_space_m = crowd_personal_space_m
    _crowd_spacing.release_space_m = crowd_release_space_m
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)
    if not get_tree().node_removed.is_connected(_on_node_removed):
        get_tree().node_removed.connect(_on_node_removed)
    call_deferred("_bootstrap")

func _exit_tree() -> void:
    if get_tree() == null:
        return
    if get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.disconnect(_on_node_added)
    if get_tree().node_removed.is_connected(_on_node_removed):
        get_tree().node_removed.disconnect(_on_node_removed)

func _process(delta: float) -> void:
    if not _configured or _director == null:
        return
    var safe_delta := maxf(0.0, delta)
    _observer_elapsed_s += safe_delta
    _crowd_elapsed_s += safe_delta
    _update_ambient_cadence(safe_delta)
    if _crowd_elapsed_s >= maxf(0.05, crowd_spacing_interval_s):
        _crowd_elapsed_s = 0.0
        _update_crowd_spacing()
    if _observer_elapsed_s < maxf(0.05, observer_refresh_interval_s):
        return
    _observer_elapsed_s = 0.0
    if is_instance_valid(_observer):
        _director.set_observer_position(_observer.global_position)

func _bootstrap() -> void:
    _director = get_node_or_null(population_director_path) as NpcPopulationDirector
    _traffic_manager = get_node_or_null(traffic_manager_path)
    _observer = get_node_or_null(observer_path) as Node3D
    _configured = _director != null and is_instance_valid(_traffic_manager) and _director.configure_traffic_crossing_runtime(_traffic_manager)
    if not _configured:
        push_warning("NPC runtime integration could not bind population director to traffic crossing runtime")
        return
    if is_instance_valid(_observer):
        _director.set_observer_position(_observer.global_position)
    _register_existing_agents(get_tree().root)

func is_runtime_configured() -> bool:
    return _configured

func _register_existing_agents(root_node: Node) -> void:
    if _director == null or root_node == null:
        return
    var pending: Array[Node] = [root_node]
    while not pending.is_empty():
        var current: Node = pending.pop_back()
        if current is NpcAgent:
            _register_agent(current as NpcAgent)
        for child: Node in current.get_children():
            pending.append(child)

func _on_node_added(node: Node) -> void:
    if not _configured or not node is NpcAgent:
        return
    call_deferred("_register_agent_if_valid", node)

func _on_node_removed(node: Node) -> void:
    if _director == null or not node is NpcAgent:
        return
    if is_instance_valid(node):
        var agent := node as NpcAgent
        _cancel_crowd_detour(agent, false)
        _release_ambient_hold(agent)
        _ambient_elapsed_s.erase(agent.get_instance_id())
        _agents.erase(agent)
        _director.unregister_agent(agent)

func _register_agent_if_valid(node: Node) -> void:
    if not _configured or _director == null or not is_instance_valid(node) or not node is NpcAgent:
        return
    _register_agent(node as NpcAgent)

func _register_agent(agent: NpcAgent) -> void:
    if not is_instance_valid(agent) or _director == null:
        return
    var accepted := _director.register_agent(agent)
    if accepted and not _agents.has(agent):
        _agents.append(agent)

func _update_ambient_cadence(delta_seconds: float) -> void:
    _agents = _agents.filter(func(agent: NpcAgent) -> bool: return is_instance_valid(agent))
    for agent: NpcAgent in _agents:
        update_ambient_cadence_for_agent(agent, delta_seconds, _crowd_is_dense(agent))

func update_ambient_cadence_for_agent(agent: NpcAgent, delta_seconds: float, crowd_is_dense: bool = false) -> int:
    if not is_instance_valid(agent):
        return NpcAmbientState.State.WALK
    var agent_id := agent.get_instance_id()
    if not _eligible_for_ambient_cadence(agent):
        _release_ambient_hold(agent)
        _ambient_elapsed_s.erase(agent_id)
        return agent.ambient_state.current_state

    var elapsed := float(_ambient_elapsed_s.get(agent_id, 0.0)) + maxf(0.0, delta_seconds)
    var duration := maxf(0.25, agent.ambient_state.state_duration_seconds(agent.ambient_state.sequence_index))
    if elapsed < duration:
        _ambient_elapsed_s[agent_id] = elapsed
        return agent.ambient_state.current_state

    _ambient_elapsed_s[agent_id] = 0.0
    var state := agent.advance_ambient_state(crowd_is_dense)
    if agent.ambient_state.movement_scale() <= 0.0:
        _ambient_holds[agent_id] = true
        agent.movement_held = true
    else:
        _release_ambient_hold(agent)
    return state

func _eligible_for_ambient_cadence(agent: NpcAgent) -> bool:
    if not is_instance_valid(agent) or not agent.active or agent.role != NpcBehaviorModel.Role.CIVILIAN:
        return false
    if agent.transit_state != NpcAgent.TransitState.NONE:
        return false
    if agent.pedestrian_intent != NpcPedestrianContext.PedestrianIntent.CONTINUE:
        return false
    if agent.civilian_recovery.is_active() or agent.behavior.alert_level > 0.01:
        return false
    var agent_id := agent.get_instance_id()
    if agent.movement_held and not _ambient_holds.has(agent_id):
        return false
    if _director != null and _director.has_crossing_assignment(agent):
        return false
    return true

func _release_ambient_hold(agent: NpcAgent) -> void:
    if not is_instance_valid(agent):
        return
    var agent_id := agent.get_instance_id()
    if not _ambient_holds.has(agent_id):
        return
    _ambient_holds.erase(agent_id)
    if agent.transit_state == NpcAgent.TransitState.NONE and agent.pedestrian_intent == NpcPedestrianContext.PedestrianIntent.CONTINUE:
        agent.movement_held = false

func _crowd_is_dense(agent: NpcAgent) -> bool:
    var origin := agent.get_world_position()
    var nearby := 0
    for peer: NpcAgent in _agents:
        if peer == agent or not is_instance_valid(peer) or not peer.active:
            continue
        var delta := peer.get_world_position() - origin
        delta.y = 0.0
        if delta.length_squared() <= 6.25:
            nearby += 1
            if nearby >= 3:
                return true
    return false

func _update_crowd_spacing() -> void:
    _crowd_spacing.personal_space_m = maxf(0.4, crowd_personal_space_m)
    _crowd_spacing.release_space_m = maxf(_crowd_spacing.personal_space_m, crowd_release_space_m)
    _agents = _agents.filter(func(agent: NpcAgent) -> bool: return is_instance_valid(agent))

    for agent: NpcAgent in _agents:
        if not _eligible_for_crowd_spacing(agent):
            _cancel_crowd_detour(agent, true)
            continue
        if _crowd_detours.has(agent.get_instance_id()) and not _has_nearby_peer(agent, _crowd_spacing.release_space_m):
            _cancel_crowd_detour(agent, true)

    for i in range(_agents.size()):
        var agent: NpcAgent = _agents[i]
        if not _eligible_for_crowd_spacing(agent):
            continue
        for j in range(i + 1, _agents.size()):
            var peer: NpcAgent = _agents[j]
            if not _eligible_for_crowd_spacing(peer):
                continue
            if not _crowd_spacing.needs_spacing(agent.get_world_position(), peer.get_world_position()):
                continue
            _apply_crowd_detour(agent, peer)
            _apply_crowd_detour(peer, agent)

func _eligible_for_crowd_spacing(agent: NpcAgent) -> bool:
    if not is_instance_valid(agent) or not agent.active or agent.role != NpcBehaviorModel.Role.CIVILIAN:
        return false
    if agent.movement_held or agent.transit_state != NpcAgent.TransitState.NONE:
        return false
    if _director != null and _director.has_crossing_assignment(agent):
        return false
    return true

func _has_nearby_peer(agent: NpcAgent, distance_m: float) -> bool:
    var origin := agent.get_world_position()
    var threshold_sq := distance_m * distance_m
    for peer: NpcAgent in _agents:
        if peer == agent or not _eligible_for_crowd_spacing(peer):
            continue
        var delta := peer.get_world_position() - origin
        delta.y = 0.0
        if delta.length_squared() < threshold_sq:
            return true
    return false

func _apply_crowd_detour(agent: NpcAgent, peer: NpcAgent) -> void:
    var agent_id := agent.get_instance_id()
    var current_target := agent.behavior.target_position
    var original_target := current_target
    if _crowd_detours.has(agent_id):
        var saved: Dictionary = _crowd_detours[agent_id]
        var saved_detour_value: Variant = saved.get("detour", current_target)
        if saved_detour_value is Vector3 and not _same_planar_target(current_target, saved_detour_value as Vector3):
            _crowd_detours.erase(agent_id)
        else:
            var original_value: Variant = saved.get("original", current_target)
            if original_value is Vector3:
                original_target = original_value as Vector3
    var detour := _crowd_spacing.detour_target(
        agent.get_world_position(),
        original_target,
        peer.get_world_position(),
        agent.variation_seed,
        peer.variation_seed
    )
    _crowd_detours[agent_id] = {"original": original_target, "detour": detour}
    agent.behavior.set_destination(detour)

func _cancel_crowd_detour(agent: NpcAgent, restore_target: bool) -> void:
    if not is_instance_valid(agent):
        return
    var agent_id := agent.get_instance_id()
    if not _crowd_detours.has(agent_id):
        return
    var saved: Dictionary = _crowd_detours[agent_id]
    _crowd_detours.erase(agent_id)
    if not restore_target:
        return
    var detour_value: Variant = saved.get("detour", null)
    var original_value: Variant = saved.get("original", null)
    if not detour_value is Vector3 or not original_value is Vector3:
        return
    if _same_planar_target(agent.behavior.target_position, detour_value as Vector3):
        agent.behavior.set_destination(original_value as Vector3)

func _same_planar_target(a: Vector3, b: Vector3) -> bool:
    return Vector2(a.x - b.x, a.z - b.z).length() <= 0.05
