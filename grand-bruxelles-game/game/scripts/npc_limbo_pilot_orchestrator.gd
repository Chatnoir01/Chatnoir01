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

@export var perception_sync_hz: float = 10.0

var agent: NpcAgent = null
var contract = CONTRACT_SCRIPT.new()
var extension_available: bool = false
var active_branch: StringName = &"unbound"
var transition_count: int = 0
var last_action_request: Dictionary = {}
var _hsm: Node = null
var _states: Dictionary = {}
var _sync_accumulator_s: float = 0.0


func bind_agent(new_agent: NpcAgent) -> bool:
    agent = new_agent
    if agent == null:
        contract.bind_model(null)
        return false
    contract.bind_model(agent.behavior)
    active_branch = contract.limbo_branch()
    extension_available = _build_limbo_hsm()
    last_action_request = contract.action_request()
    return extension_available


func _ready() -> void:
    if agent == null and get_parent() is NpcAgent:
        bind_agent(get_parent() as NpcAgent)


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
    if not ClassDB.class_exists(&"LimboHSM") or not ClassDB.class_exists(&"LimboState"):
        return false

    var hsm_value: Variant = ClassDB.instantiate(&"LimboHSM")
    if not hsm_value is Node:
        return false
    _hsm = hsm_value as Node
    _hsm.name = "GrandBruxellesPilotHSM"
    # MANUAL mode: Grand Bruxelles owns update cadence and authoritative state.
    _hsm.set("update_mode", 2)
    add_child(_hsm)

    for branch: StringName in BRANCHES:
        var state_value: Variant = ClassDB.instantiate(&"LimboState")
        if not state_value is Node:
            _free_hsm()
            return false
        var state := state_value as Node
        state.name = String(branch)
        _hsm.add_child(state)
        _states[branch] = state

    var initial_branch := contract.limbo_branch()
    if not _states.has(initial_branch):
        initial_branch = &"routine"
    _hsm.set("initial_state", _states[initial_branch])
    _hsm.call("initialize", agent)
    _hsm.call("set_active", true)
    active_branch = initial_branch
    return hsm_active_state_name() == active_branch


func _activate_branch(branch: StringName) -> void:
    if not BRANCHES.has(branch):
        branch = &"routine"
    if extension_available and _hsm != null and _states.has(branch):
        _hsm.call("change_active_state", _states[branch])
        var hsm_branch := hsm_active_state_name()
        if hsm_branch != branch:
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
