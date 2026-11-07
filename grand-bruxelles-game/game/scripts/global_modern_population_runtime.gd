extends Node

# Global migration bridge for legacy ambient city life.
# It runs before the main scene and watches every dynamically loaded/LABO zone.
# Canonical traffic/navigation remain authoritative; this runtime removes legacy
# local vehicle generators, upgrades residual visuals, and raises bounded budgets.
const RGSDEV_VEHICLE_VISUAL_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")
const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")
const NPC_AGENT_SCRIPT := preload("res://game/scripts/npc_agent.gd")

const LEGACY_PEDESTRIAN_VISUALS: Array[String] = [
    "Torso", "LeftLeg", "RightLeg", "LeftArm", "RightArm", "Head", "Bag"
]
const LEGACY_VEHICLE_VISUALS: Array[String] = [
    "ProductionVisual", "VisualUpgrade", "Body", "Cabin", "ABLabel"
]

const MIN_TRAFFIC_VEHICLES := 18
const MIN_PARKED_VEHICLES := 12
const MIN_DELIVERY_VEHICLES := 3
const MIN_CIVILIAN_BUDGET := 64
const MIN_POLICE_BUDGET := 12
const NPC_PROXY_Y_OFFSET := 0.67

var _modernized_pedestrians: Dictionary = {}
var _modernized_vehicles: Dictionary = {}
var _configured_traffic_managers: Dictionary = {}
var _configured_population_directors: Dictionary = {}
var _suppressed_local_vehicle_generators: Dictionary = {}

func _ready() -> void:
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)
    call_deferred("_scan_existing_tree")

func _exit_tree() -> void:
    if get_tree() != null and get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.disconnect(_on_node_added)

func _on_node_added(node: Node) -> void:
    if node == null:
        return
    # node_added is emitted before _ready(). This is the important production
    # gate: legacy local car builders are disabled before they can instantiate.
    _configure_runtime_owner(node)
    call_deferred("_modernize_node_if_valid", node)

func _scan_existing_tree() -> void:
    var tree := get_tree()
    if tree == null:
        return
    _scan_subtree(tree.root)
    _refresh_runtime_population()

func _scan_subtree(root: Node) -> void:
    if root == null:
        return
    var pending: Array[Node] = [root]
    while not pending.is_empty():
        var current: Node = pending.pop_back()
        _configure_runtime_owner(current)
        _modernize_node(current)
        for child: Node in current.get_children():
            pending.append(child)

func _modernize_node_if_valid(node: Node) -> void:
    if not is_instance_valid(node):
        return
    _configure_runtime_owner(node)
    _modernize_node(node)

func _modernize_node(node: Node) -> void:
    if node == null or not node is Node3D:
        return
    var spatial := node as Node3D
    if spatial.is_in_group("ambient_pedestrian"):
        _modernize_ambient_pedestrian(spatial)
    if spatial.is_in_group("ambient_traffic") or _has_legacy_vehicle_visual(spatial):
        _modernize_legacy_vehicle(spatial)

func _configure_runtime_owner(node: Node) -> void:
    if node == null:
        return
    _suppress_legacy_local_vehicle_generator(node)
    if _looks_like_traffic_manager(node):
        _configure_traffic_manager(node)
    if _looks_like_population_director(node):
        _configure_population_director(node)

func _suppress_legacy_local_vehicle_generator(node: Node) -> void:
    var moving_value: Variant = node.get("moving_vehicle_count")
    var parked_value: Variant = node.get("parked_vehicle_count")
    if moving_value == null and parked_value == null:
        return
    var changed := false
    if moving_value != null and int(moving_value) > 0:
        node.set("moving_vehicle_count", 0)
        changed = true
    if parked_value != null and int(parked_value) > 0:
        node.set("parked_vehicle_count", 0)
        changed = true
    if changed:
        node.set_meta("legacy_local_vehicle_generator_suppressed", true)
        _suppressed_local_vehicle_generators[node.get_instance_id()] = true

func _looks_like_traffic_manager(node: Node) -> bool:
    return node.name == "TrafficManager" and node.get("max_vehicles") != null and node.has_method("get_active_vehicle_count")

func _looks_like_population_director(node: Node) -> bool:
    return node.name == "NpcPopulationDirector" and node.get("civilian_budget") != null and node.has_method("get_counts")

func _configure_traffic_manager(manager: Node) -> void:
    var instance_id := manager.get_instance_id()
    manager.set("max_vehicles", maxi(int(manager.get("max_vehicles")), MIN_TRAFFIC_VEHICLES))
    if manager.get("max_parked_vehicles") != null:
        manager.set("max_parked_vehicles", maxi(int(manager.get("max_parked_vehicles")), MIN_PARKED_VEHICLES))
    if manager.get("max_delivery_vehicles") != null:
        manager.set("max_delivery_vehicles", maxi(int(manager.get("max_delivery_vehicles")), MIN_DELIVERY_VEHICLES))
    var base_value: Variant = manager.get("_base_max_vehicles")
    if base_value != null and int(base_value) > 0:
        manager.set("_base_max_vehicles", maxi(int(base_value), MIN_TRAFFIC_VEHICLES))
    _configured_traffic_managers[instance_id] = true

func _configure_population_director(director: Node) -> void:
    var instance_id := director.get_instance_id()
    director.set("civilian_budget", maxi(int(director.get("civilian_budget")), MIN_CIVILIAN_BUDGET))
    director.set("police_budget", maxi(int(director.get("police_budget")), MIN_POLICE_BUDGET))
    if director.has_method("set_population_context"):
        var counts: Dictionary = director.call("get_counts")
        director.call_deferred(
            "set_population_context",
            int(counts.get("urban_context", 0)),
            float(counts.get("hour", 12.0)),
            1.0,
            0.0
        )
    _configured_population_directors[instance_id] = true

func _modernize_ambient_pedestrian(person: Node3D) -> void:
    var instance_id := person.get_instance_id()
    if _modernized_pedestrians.has(instance_id):
        return
    if person.get_node_or_null("ProfiledNpcProxy") == null:
        var proxy := NPC_AGENT_SCRIPT.new()
        proxy.name = "ProfiledNpcProxy"
        proxy.process_mode = Node.PROCESS_MODE_DISABLED
        proxy.collision_layer = 0
        proxy.collision_mask = 0
        proxy.position = Vector3(0.0, NPC_PROXY_Y_OFFSET, 0.0)
        var visual := Node3D.new()
        visual.name = "VisualUpgrade"
        visual.set_script(HUMANOID_VISUAL_SCRIPT)
        proxy.add_child(visual)
        person.add_child(proxy)
    for legacy_name: String in LEGACY_PEDESTRIAN_VISUALS:
        var legacy := person.get_node_or_null(legacy_name)
        if legacy is VisualInstance3D:
            (legacy as VisualInstance3D).visible = false
    person.set_meta("modern_population_visual", "profiled_npc")
    _modernized_pedestrians[instance_id] = true

func _has_legacy_vehicle_visual(vehicle: Node3D) -> bool:
    if vehicle.get_node_or_null("RgsdevVisual") != null:
        return false
    if vehicle.get_node_or_null("ProductionVisual") != null:
        return true
    return vehicle.name.begins_with("AmbientTraffic_") or vehicle.name.begins_with("ParkedCar_")

func _modernize_legacy_vehicle(vehicle: Node3D) -> void:
    var instance_id := vehicle.get_instance_id()
    if _modernized_vehicles.has(instance_id):
        return
    if vehicle.get_node_or_null("RgsdevVisual") == null:
        var visual := RGSDEV_VEHICLE_VISUAL_SCRIPT.new()
        visual.name = "RgsdevVisual"
        visual.call("configure_for_traffic", posmod(instance_id, 100000))
        vehicle.add_child(visual)
    for legacy_name: String in LEGACY_VEHICLE_VISUALS:
        var legacy := vehicle.get_node_or_null(legacy_name)
        if legacy is Node3D and legacy.name != "RgsdevVisual":
            (legacy as Node3D).visible = false
    vehicle.set_meta("modern_vehicle_visual", "rgsdev")
    _modernized_vehicles[instance_id] = true

func _refresh_runtime_population() -> void:
    var tree := get_tree()
    if tree == null:
        return
    for node: Node in tree.get_nodes_in_group("traffic_vehicle"):
        if node is Node3D:
            _modernize_node(node)
    for child: Node in tree.root.find_children("TrafficManager", "Node", true, false):
        if child.has_method("_apply_density_now"):
            child.call_deferred("_apply_density_now")
        if child.has_method("_replenish_traffic"):
            child.call_deferred("_replenish_traffic")

func runtime_stats() -> Dictionary:
    return {
        "modernized_pedestrians": _modernized_pedestrians.size(),
        "modernized_vehicles": _modernized_vehicles.size(),
        "suppressed_local_vehicle_generators": _suppressed_local_vehicle_generators.size(),
        "traffic_managers": _configured_traffic_managers.size(),
        "population_directors": _configured_population_directors.size(),
        "minimum_traffic_vehicles": MIN_TRAFFIC_VEHICLES,
        "minimum_civilian_budget": MIN_CIVILIAN_BUDGET,
    }
