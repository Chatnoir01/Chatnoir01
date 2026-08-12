class_name NpcRuntimeIntegration
extends Node

@export var population_director_path: NodePath = NodePath("../NpcPopulationDirector")
@export var traffic_manager_path: NodePath = NodePath("../TrafficManager")
@export var observer_path: NodePath = NodePath("../Player")
@export var observer_refresh_interval_s: float = 0.25

var _director: NpcPopulationDirector = null
var _traffic_manager: Node = null
var _observer: Node3D = null
var _observer_elapsed_s: float = 0.0
var _configured: bool = false

func _ready() -> void:
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
    _observer_elapsed_s += maxf(0.0, delta)
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
            _director.register_agent(current as NpcAgent)
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
        _director.unregister_agent(node as NpcAgent)

func _register_agent_if_valid(node: Node) -> void:
    if not _configured or _director == null or not is_instance_valid(node) or not node is NpcAgent:
        return
    _director.register_agent(node as NpcAgent)
