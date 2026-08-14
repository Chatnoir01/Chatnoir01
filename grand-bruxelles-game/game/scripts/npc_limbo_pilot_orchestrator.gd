extends Node

const CONTRACT_SCRIPT := preload("res://game/scripts/npc_limbo_contract.gd")
const BRANCHES: Array[StringName] = [
    &"routine",
    &"observe",
    &"avoid",
    &"flee",
    &"investigate",
    &"pursue",
    &"return",
]

@export var agent_path: NodePath
@export var perception_sync_hz: float = 10.0

var agent: NpcAgent = null
var contract = CONTRACT_SCRIPT.new()
var extension_available: bool = false
var active_branch: StringName = &"unbound"
var transition_count: int = 0
var last_action_request: Dictionary = {}
var last_build_error: String = "not_built"
var _hsm: Node = null
var _states: Dictionary = {}
var _sync_accumulator_s: float = 0.0


func bind_agent(new_agent: NpcAgent) -> bool:
    agent = new_agent
    if agent == null:
        contract.bind_model(null)
        last_build_error = "agent_null"
        return false
    contract.bind_model(agent.behavior)
    active_branch = contract.limbo_branch()
    extension_available = _build_limbo_hsm()
    last_action_request = contract.action_request()
    return extension_available


func _ready() -> void:
    # Bind after the whole pilot scene is ready so NpcAgent has already configured
    # its authoritative role/behavior model.
    call_deferred("_bind_exported_agent")


func _bind_exported_agent() -> void:
    if agent != null:
        return
    if not agent_path.is_empty():
        var candidate := get_node_or_null(agent_path)
        if candidate is NpcAgent:
            bind_agent(candidate as NpcAgent)
            return
        last_build_error = "agent_path_unresolved:%s" % agent_path
    if get_parent() is NpcAgent:
        bind_agent(get_parent() as NpcAgent)
        return
    if last_build_error == "not_built":
        last_build_error = "no_agent_binding"


func _physics_process(delta: float) -> void:
    if agent == null:
        return
    var interval := 1.0 / maxf(perception_sync_hz, 1.0)
    _sync_accumulator_s += maxf(delta, 0.0)
    if _sync_accumulator_s < interval:
        return
    var elapsed := _sync_accumulator_s
    _sync_accumulator_s = 0.0
    sync_from_agent(false, INF, agent.behavior.target_position, elapsed)


func sync_from_agent(target_visible: bool, target_distance_m: float, observed_position: Vector3, delta: float) -> StringName:
    if agent == null:
        return &"unbound"
    contract.sync_perception(target_visible, target_distance_m, observed_position, delta)
    var desired := contract.limbo_branch()
    last_action_request = contract.action_request()
    if desired != active_branch:
        _activate_branch(desired)
    return active_branch


func blackboard_snapshot() -> Dictionary:
    var snapshot: Dictionary = contract.blackboard_snapshot()
    snapshot["limbo_extension_available"] = extension_available
    snapshot["limbo_active_branch"] = active_branch
    snapshot["limbo_transition_count"] = transition_count
    snapshot["limbo_build_error"] = last_build_error
    return snapshot


func hsm_active_state_name() -> StringName:
    if _hsm == null or not extension_available:
        return &""
    var state: Variant = _hsm.call("get_active_state")
    if state is Node:
        return StringName((state as Node).name)
    return &""


func _build_limbo_hsm() -> bool:
    _free_hsm()
    last_build_error = "building"
    if not ClassDB.class_exists(&"LimboHSM"):
        last_build_error = "LimboHSM_missing"
        return false
    if not ClassDB.class_exists(&"LimboState"):
        last_build_error = "LimboState_missing"
        return false
    if not ClassDB.can_instantiate(&"LimboHSM"):
        last_build_error = "LimboHSM_not_instantiable"
        return false
    if not ClassDB.can_instantiate(&"LimboState"):
        last_build_error = "LimboState_not_instantiable"
        return false

    var hsm_value: Variant = ClassDB.instantiate(&"LimboHSM")
    if not hsm_value is Node:
        last_build_error = "LimboHSM_instance_not_node:%s" % type_string(typeof(hsm_value))
        return false
    _hsm = hsm_value as Node
    _hsm.name = "GrandBruxellesPilotHSM"
    add_child(_hsm)
    # MANUAL mode: Grand Bruxelles owns update cadence and authoritative state.
    _hsm.call("set_update_mode", 2)

    for branch: StringName in BRANCHES:
        var state_value: Variant = ClassDB.instantiate(&"LimboState")
        if not state_value is Node:
            last_build_error = "LimboState_instance_failed:%s" % branch
            _free_hsm()
            return false
        var state := state_value as Node
        state.name = String(branch)
        _hsm.add_child(state)
        _states[branch] = state

    var initial_branch := contract.limbo_branch()
    if not _states.has(initial_branch):
        initial_branch = &"routine"
    _hsm.call("set_initial_state", _states[initial_branch])
    _hsm.call("initialize", agent)
    _hsm.call("set_active", true)
    active_branch = initial_branch

    var initial_active := _raw_hsm_active_state_name()
    if initial_active != active_branch:
        last_build_error = "initial_state_mismatch:expected=%s actual=%s" % [active_branch, initial_active]
        return false
    extension_available = true
    last_build_error = "ok"
    return true


func _raw_hsm_active_state_name() -> StringName:
    if _hsm == null:
        return &""
    var state: Variant = _hsm.call("get_active_state")
    if state is Node:
        return StringName((state as Node).name)
    return &""


func _activate_branch(branch: StringName) -> void:
    if not BRANCHES.has(branch):
        branch = &"routine"
    if extension_available and _hsm != null and _states.has(branch):
        _hsm.call("change_active_state", _states[branch])
        var hsm_branch := _raw_hsm_active_state_name()
        if hsm_branch != branch:
            last_build_error = "transition_mismatch:%s>%s actual=%s" % [active_branch, branch, hsm_branch]
            push_error("LimboAI pilot HSM failed transition %s -> %s" % [active_branch, branch])
            return
    active_branch = branch
    transition_count += 1


func _free_hsm() -> void:
    extension_available = false
    _states.clear()
    if _hsm != null:
        _hsm.queue_free()
        _hsm = null
