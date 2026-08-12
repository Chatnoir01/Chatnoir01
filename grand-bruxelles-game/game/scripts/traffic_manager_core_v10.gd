extends "res://game/scripts/traffic_manager_core_v9.gd"

@export var npc_crossing_bridge_enabled: bool = true
@export var npc_crossing_scan_interval_s: float = 0.35
@export var max_bridged_npcs: int = 12
@export var suppress_synthetic_while_npc_crosses: bool = true

const NPC_CROSSING_BRIDGE_SCRIPT := preload("res://game/scripts/traffic_npc_crossing_bridge.gd")

var _npc_crossing_bridge: RefCounted
var _npc_crossing_elapsed: float = 0.0
var _npc_crossing_stats := {"assigned": 0, "waiting": 0, "crossing": 0}
var _synthetic_crossing_budget: int = 0


func _ready() -> void:
    _npc_crossing_bridge = NPC_CROSSING_BRIDGE_SCRIPT.new()
    _synthetic_crossing_budget = max_crossing_pedestrians
    super._ready()
    _update_npc_crossing_bridge()


func _process(delta: float) -> void:
    super._process(delta)
    if not npc_crossing_bridge_enabled or _npc_crossing_bridge == null:
        _restore_synthetic_crossing_budget()
        return

    _npc_crossing_elapsed += delta
    if _npc_crossing_elapsed < npc_crossing_scan_interval_s:
        return
    _npc_crossing_elapsed = 0.0
    _update_npc_crossing_bridge()


func _exit_tree() -> void:
    if _npc_crossing_bridge != null and _crossing_system != null:
        _npc_crossing_bridge.call("clear_all", _crossing_system)


func _update_npc_crossing_bridge() -> void:
    if _crossing_system == null or _npc_crossing_bridge == null:
        return

    var agents: Array = _collect_crossing_capable_agents()
    var now_seconds := float(Time.get_ticks_msec()) / 1000.0
    var stats_variant: Variant = _npc_crossing_bridge.call(
        "update_agents",
        agents,
        _crossing_system,
        _traffic_root,
        now_seconds
    )
    if typeof(stats_variant) == TYPE_DICTIONARY:
        _npc_crossing_stats = stats_variant

    if suppress_synthetic_while_npc_crosses and int(_npc_crossing_stats.get("assigned", 0)) > 0:
        max_crossing_pedestrians = 0
        _clear_synthetic_crossing_pedestrians()
    else:
        _restore_synthetic_crossing_budget()


func _collect_crossing_capable_agents() -> Array:
    var result: Array = []
    var tree := get_tree()
    if tree == null or tree.current_scene == null:
        return result
    _collect_crossing_capable_recursive(tree.current_scene, result)
    return result


func _collect_crossing_capable_recursive(node: Node, result: Array) -> void:
    if result.size() >= max_bridged_npcs:
        return
    if node != self and _is_crossing_capable_node(node):
        result.append(node)
        if result.size() >= max_bridged_npcs:
            return
    for child: Node in node.get_children():
        _collect_crossing_capable_recursive(child, result)
        if result.size() >= max_bridged_npcs:
            return


func _is_crossing_capable_node(node: Node) -> bool:
    if not node is Node3D:
        return false
    return (
        node.has_method("set_destination")
        and node.has_method("update_crossing_context")
        and node.has_method("clear_pedestrian_hold")
    )


func _clear_synthetic_crossing_pedestrians() -> void:
    if _crossing_root == null:
        return
    for child: Node in _crossing_root.get_children():
        if not child.is_queued_for_deletion():
            child.queue_free()


func _restore_synthetic_crossing_budget() -> void:
    if max_crossing_pedestrians == _synthetic_crossing_budget:
        return
    max_crossing_pedestrians = _synthetic_crossing_budget
    call_deferred("_replenish_crossing_pedestrians")


func get_npc_crossing_bridge_stats() -> Dictionary:
    return _npc_crossing_stats.duplicate(true)


func get_bridged_npc_count() -> int:
    return int(_npc_crossing_stats.get("assigned", 0))
