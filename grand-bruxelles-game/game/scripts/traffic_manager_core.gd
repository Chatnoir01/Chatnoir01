extends Node3D
class_name TrafficManagerCore

@export_file("*.json") var traffic_manifest_path: String = "res://data/traffic/manifest.json"
@export_file("*.json") var fallback_data_path: String = "res://data/osm/vertical_slice_01.game.json"
@export var max_vehicles: int = 12
@export var spawn_radius_m: float = 520.0
@export var despawn_radius_m: float = 760.0
@export var min_route_length_m: float = 42.0
@export var route_target_length_m: float = 320.0
@export var route_max_length_m: float = 720.0
@export var max_route_edges: int = 28
@export var default_speed_kmh: float = 30.0
@export var traffic_seed: int = 20260812
@export var player_path: NodePath = NodePath("../Player")
@export var maintenance_interval_s: float = 1.5
@export var max_crossing_pedestrians: int = 6
@export var crossing_spawn_radius_m: float = 420.0
@export var crossing_maintenance_interval_s: float = 1.0
@export var density_enabled: bool = true
@export_range(0.0, 23.99, 0.05) var simulation_hour: float = 12.0
@export var auto_advance_simulation_time: bool = false
@export var simulated_minutes_per_real_second: float = 0.0
@export var density_refresh_interval_s: float = 2.0
@export_range(0.0, 1.0, 0.01) var scooter_share: float = 0.18
@export_range(0.0, 1.0, 0.01) var motorcycle_share: float = 0.10
@export var max_parked_vehicles: int = 8
@export var parking_spawn_radius_m: float = 360.0
@export var parking_refresh_interval_s: float = 3.0
@export var max_delivery_vehicles: int = 2
@export var delivery_spawn_radius_m: float = 320.0
@export var delivery_refresh_interval_s: float = 2.0
@export var delivery_duration_min_s: float = 12.0
@export var delivery_duration_max_s: float = 24.0
@export var wreck_clear_delay_s: float = 18.0
@export var wreck_cleanup_interval_s: float = 1.0
@export var max_wrecks_before_fast_clear: int = 3
@export var auto_load_data: bool = true
@export var auto_spawn_runtime: bool = true

const ROAD_GRAPH_SCRIPT := preload("res://game/scripts/traffic_road_graph.gd")
const TRAFFIC_CONTROL_SCRIPT := preload("res://game/scripts/traffic_control_system.gd")
const INTERSECTION_SCRIPT := preload("res://game/scripts/traffic_intersection_system.gd")
const CROSSING_SYSTEM_SCRIPT := preload("res://game/scripts/traffic_crossing_system.gd")
const DENSITY_MODEL_SCRIPT := preload("res://game/scripts/traffic_density_model.gd")
const PARKING_MODEL_SCRIPT := preload("res://game/scripts/traffic_parking_model.gd")

const FALLBACK_ANCHOR := Vector3(-668.5, 0.0, 627.84)
const MIN_SPAWN_CLEARANCE_M := 7.0
const MAX_SPAWN_ATTEMPTS := 64
const CAR_SIZE := Vector3(1.82, 1.16, 4.15)
const SCOOTER_SIZE := Vector3(0.72, 1.22, 2.00)
const MOTORCYCLE_SIZE := Vector3(0.78, 1.18, 2.28)
const PARKED_CAR_SIZE := Vector3(1.82, 1.08, 4.12)
const DELIVERY_VAN_SIZE := Vector3(2.02, 1.82, 5.15)
const DELIVERY_CLASSES := {
    "service": true,
    "tertiary": true,
    "secondary": true,
    "unclassified": true,
}
const MIXED_COLORS: Array[Color] = [
    Color(0.18, 0.20, 0.22, 1.0),
    Color(0.36, 0.39, 0.42, 1.0),
    Color(0.12, 0.24, 0.38, 1.0),
    Color(0.43, 0.12, 0.10, 1.0),
    Color(0.73, 0.73, 0.69, 1.0),
    Color(0.12, 0.31, 0.22, 1.0),
]

var _roads: Array[Dictionary] = []
var _traffic_controls: Array = []
var _road_graph: RefCounted = null
var _control_system: RefCounted = null
var _intersection_system: RefCounted = null
var _crossing_system: RefCounted = null
var _density_model: RefCounted = null
var _parking_model: RefCounted = null
var _traffic_root: Node3D = null
var _crossing_root: Node3D = null
var _parking_root: Node3D = null
var _delivery_root: Node3D = null
var _rng := RandomNumberGenerator.new()
var _parking_rng := RandomNumberGenerator.new()
var _delivery_rng := RandomNumberGenerator.new()
var _spawn_serial: int = 0
var _pedestrian_serial: int = 1
var _delivery_serial: int = 1
var _maintenance_elapsed: float = 0.0
var _crossing_elapsed: float = 0.0
var _density_elapsed: float = 0.0
var _parking_elapsed: float = 0.0
var _delivery_elapsed: float = 0.0
var _wreck_cleanup_elapsed: float = 0.0
var _base_max_vehicles: int = 0
var _corridor_anchors: Array = []
var _current_density_factor: float = 1.0
var _current_sector: String = "corridor"
var _parking_candidates: Array[Dictionary] = []
var _reserved_parking_candidate_ids: Dictionary = {}

func _ready() -> void:
    _ensure_runtime()
    if auto_load_data:
        _load_traffic_data()
        _load_corridor_anchors()
    _base_max_vehicles = max_vehicles
    _rebuild_models()
    if auto_spawn_runtime:
        _apply_density_now()
        _replenish_traffic()
        _replenish_crossing_pedestrians()
        _replenish_parked_vehicles()
        _replenish_deliveries()

func _ensure_runtime() -> void:
    if _road_graph == null:
        _road_graph = ROAD_GRAPH_SCRIPT.new()
    if _control_system == null:
        _control_system = TRAFFIC_CONTROL_SCRIPT.new()
    if _intersection_system == null:
        _intersection_system = INTERSECTION_SCRIPT.new()
    if _crossing_system == null:
        _crossing_system = CROSSING_SYSTEM_SCRIPT.new()
    if _density_model == null:
        _density_model = DENSITY_MODEL_SCRIPT.new()
    if _parking_model == null:
        _parking_model = PARKING_MODEL_SCRIPT.new()
    _rng.seed = traffic_seed
    _parking_rng.seed = traffic_seed + 911
    _delivery_rng.seed = traffic_seed + 1777
    _traffic_root = _ensure_root("TrafficVehicles", _traffic_root)
    _crossing_root = _ensure_root("CrossingPedestrians", _crossing_root)
    _parking_root = _ensure_root("ParkedVehicles", _parking_root)
    _delivery_root = _ensure_root("DeliveryVehicles", _delivery_root)

func _ensure_root(root_name: String, current: Node3D) -> Node3D:
    if current != null and is_instance_valid(current):
        return current
    var existing := get_node_or_null(root_name) as Node3D
    if existing != null:
        return existing
    var root := Node3D.new()
    root.name = root_name
    add_child(root)
    return root

func configure_test_data(raw_roads: Array, raw_controls: Array, anchors: Array = []) -> void:
    _ensure_runtime()
    _roads.clear()
    _traffic_controls.clear()
    _append_roads(raw_roads)
    _append_controls(raw_controls)
    _corridor_anchors = anchors.duplicate(true)
    _base_max_vehicles = max_vehicles
    _rebuild_models()

func _process(delta: float) -> void:
    if auto_advance_simulation_time and simulated_minutes_per_real_second > 0.0:
        simulation_hour = fposmod(simulation_hour + delta * simulated_minutes_per_real_second / 60.0, 24.0)
    _density_elapsed += delta
    if _density_elapsed >= density_refresh_interval_s:
        _density_elapsed = 0.0
        _apply_density_now()
    _maintenance_elapsed += delta
    if _maintenance_elapsed >= maintenance_interval_s:
        _maintenance_elapsed = 0.0
        _despawn_far_vehicles()
        _replenish_traffic()
    _attach_crossing_system_to_vehicles()
    _crossing_elapsed += delta
    if _crossing_elapsed >= crossing_maintenance_interval_s:
        _crossing_elapsed = 0.0
        _despawn_far_crossing_pedestrians()
        _replenish_crossing_pedestrians()
    _parking_elapsed += delta
    if _parking_elapsed >= parking_refresh_interval_s:
        _parking_elapsed = 0.0
        _despawn_far_parked_vehicles()
        _replenish_parked_vehicles()
    expire_deliveries_at(float(Time.get_ticks_msec()) / 1000.0)
    _delivery_elapsed += delta
    if _delivery_elapsed >= delivery_refresh_interval_s:
        _delivery_elapsed = 0.0
        _despawn_far_deliveries()
        _replenish_deliveries()
    _wreck_cleanup_elapsed += delta
    if _wreck_cleanup_elapsed >= wreck_cleanup_interval_s:
        _wreck_cleanup_elapsed = 0.0
        cleanup_wrecks_at(float(Time.get_ticks_msec()) / 1000.0)

func _read_json_dictionary(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Traffic JSON is invalid: %s" % path)
        return {}
    return parsed as Dictionary

func _load_traffic_data() -> void:
    _roads.clear()
    _traffic_controls.clear()
    var loaded_pack := false
    var manifest := _read_json_dictionary(traffic_manifest_path)
    if not manifest.is_empty():
        var base_dir := traffic_manifest_path.get_base_dir()
        for raw_name: Variant in manifest.get("road_chunks", []):
            var chunk := _read_json_dictionary(base_dir.path_join(str(raw_name)))
            _append_roads(chunk.get("roads", []))
        for raw_name: Variant in manifest.get("control_chunks", []):
            var chunk := _read_json_dictionary(base_dir.path_join(str(raw_name)))
            _append_controls(chunk.get("traffic_controls", []))
        loaded_pack = not _roads.is_empty()
    if not loaded_pack:
        var fallback := _read_json_dictionary(fallback_data_path)
        _append_roads(fallback.get("roads", []))
        _append_controls(fallback.get("traffic_controls", []))
        if fallback.is_empty():
            push_warning("No traffic data could be loaded")

func _load_corridor_anchors() -> void:
    _corridor_anchors.clear()
    var fallback := _read_json_dictionary(fallback_data_path)
    var corridor: Dictionary = fallback.get("corridor", {})
    var raw_anchors: Variant = corridor.get("anchors", [])
    if raw_anchors is Array:
        _corridor_anchors = (raw_anchors as Array).duplicate(true)

func _append_roads(raw_roads: Array) -> void:
    for raw_road: Variant in raw_roads:
        if typeof(raw_road) != TYPE_DICTIONARY:
            continue
        var road: Dictionary = raw_road
        if not bool(road.get("drivable", false)):
            continue
        if _road_is_access_restricted(road):
            continue
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
        _roads.append(road.duplicate(true))

func _append_controls(raw_controls: Array) -> void:
    for raw_control: Variant in raw_controls:
        if typeof(raw_control) == TYPE_DICTIONARY:
            _traffic_controls.append((raw_control as Dictionary).duplicate(true))

func _road_is_access_restricted(road: Dictionary) -> bool:
    var access := str(road.get("access", "")).to_lower()
    var motor_vehicle := str(road.get("motor_vehicle", "")).to_lower()
    return access in ["no", "private"] or motor_vehicle in ["no", "private"]

func _rebuild_models() -> void:
    _ensure_runtime()
    _road_graph.call("rebuild", _roads)
    _control_system.call("rebuild", _traffic_controls)
    _intersection_system.call("rebuild", _roads, _traffic_controls)
    _crossing_system.call("rebuild", _roads, _traffic_controls)
    _parking_candidates = _parking_model.call("build_candidates", _roads, _traffic_controls)

func _anchor_position() -> Vector3:
    var player := get_node_or_null(player_path) as Node3D
    if player != null:
        return player.global_position
    return FALLBACK_ANCHOR

func _replenish_traffic() -> void:
    if not auto_spawn_runtime or _traffic_root == null or _road_graph == null or max_vehicles <= 0:
        return
    if get_graph_edge_count() <= 0:
        return
    var safety := 0
    while get_active_vehicle_count() < max_vehicles and safety < max_vehicles * 5:
        safety += 1
        if not _spawn_one_vehicle():
            break

func _spawn_one_vehicle() -> bool:
    if _traffic_root == null or _road_graph == null:
        return false
    var anchor := _anchor_position()
    var candidates: Array = _road_graph.call("find_candidate_edge_ids", anchor, spawn_radius_m)
    if candidates.is_empty():
        candidates = _road_graph.call("find_candidate_edge_ids", anchor, 100000.0)
    if candidates.is_empty():
        return false
    for _attempt: int in range(MAX_SPAWN_ATTEMPTS):
        var start_edge_id := int(candidates[_rng.randi_range(0, candidates.size() - 1)])
        var edge_ids: Array = _road_graph.call("build_random_walk", start_edge_id, _rng, route_target_length_m, route_max_length_m, max_route_edges)
        if edge_ids.size() < 2:
            continue
        var route_bundle := _route_bundle_from_edges(edge_ids)
        var route: PackedVector3Array = route_bundle.get("points", PackedVector3Array())
        if route.size() < 3 or _packed_route_length(route) < min_route_length_m:
            continue
        if not _spawn_position_is_clear(route[0]):
            continue
        var route_controls: Array = _control_system.call("controls_for_route", route)
        var route_intersections: Array = _intersection_system.call("intersections_for_route", route)
        var vehicle := _create_vehicle_node()
        _traffic_root.add_child(vehicle)
        vehicle.global_position = route[0]
        vehicle.route_finished.connect(_on_route_finished)
        vehicle.configure_route_profile(
            route,
            route_bundle.get("speed_limits_kmh", PackedFloat32Array()),
            str(route_bundle.get("road_name", "")),
            int(route_bundle.get("osm_id", 0)),
            edge_ids.size(),
            route_controls,
            _control_system,
            route_intersections,
            _intersection_system
        )
        vehicle.set_crossing_system(_crossing_system)
        return true
    return false

func _route_bundle_from_edges(edge_ids: Array) -> Dictionary:
    var points := PackedVector3Array()
    var speed_limits := PackedFloat32Array()
    var first_road_name := ""
    var first_osm_id := 0
    for raw_edge_id: Variant in edge_ids:
        var edge: Dictionary = _road_graph.call("get_edge", int(raw_edge_id))
        if edge.is_empty():
            continue
        var road: Dictionary = edge.get("road", {})
        var start: Vector3 = edge["from"]
        var finish: Vector3 = edge["to"]
        var direction := finish - start
        direction.y = 0.0
        if direction.length_squared() <= 0.001:
            continue
        direction = direction.normalized()
        var right := Vector3(-direction.z, 0.0, direction.x)
        var lane_offset := _lane_offset_for_road(road)
        var shifted_start := start + right * lane_offset
        var shifted_finish := finish + right * lane_offset
        var speed_limit := _speed_limit_for_road(road)
        if first_osm_id == 0:
            first_osm_id = int(edge.get("osm_id", 0))
            first_road_name = str(road.get("name", ""))
        if points.is_empty():
            points.append(shifted_start)
            speed_limits.append(speed_limit)
        elif points[points.size() - 1].distance_to(shifted_start) > 0.20:
            points.append(shifted_start)
            speed_limits.append(speed_limit)
        points.append(shifted_finish)
        speed_limits.append(speed_limit)
    return {"points": points, "speed_limits_kmh": speed_limits, "road_name": first_road_name, "osm_id": first_osm_id}

func _lane_offset_for_road(road: Dictionary) -> float:
    var width := maxf(3.0, _safe_float(road.get("width", 5.6), 5.6))
    var oneway := _normalized_oneway(road)
    var lanes := _safe_nonnegative_int(road.get("lanes", null))
    if oneway != 0:
        if lanes >= 2:
            return clampf(width * 0.18, 0.7, 1.65)
        return clampf(width * 0.08, 0.25, 0.65)
    return clampf(width * 0.23, 1.0, 2.05)

func _safe_nonnegative_int(raw: Variant) -> int:
    if raw == null:
        return 0
    if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
        return maxi(0, int(raw))
    if typeof(raw) == TYPE_STRING and str(raw).is_valid_int():
        return maxi(0, int(str(raw)))
    return 0

func _safe_float(raw: Variant, fallback: float) -> float:
    if raw == null:
        return fallback
    if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
        return float(raw)
    if typeof(raw) == TYPE_STRING and str(raw).is_valid_float():
        return float(str(raw))
    return fallback

func _normalized_oneway(road: Dictionary) -> int:
    var raw: Variant = road.get("oneway", 0)
    if typeof(raw) == TYPE_INT or typeof(raw) == TYPE_FLOAT:
        var numeric := int(raw)
        if numeric < 0:
            return -1
        if numeric > 0:
            return 1
        return 0
    var text := str(raw).to_lower()
    if text == "-1":
        return -1
    if text in ["1", "yes", "true"]:
        return 1
    if str(road.get("junction", "")).to_lower() == "roundabout":
        return 1
    return 0

func _packed_route_length(route: PackedVector3Array) -> float:
    var total := 0.0
    for index: int in range(route.size() - 1):
        total += route[index].distance_to(route[index + 1])
    return total

func _speed_limit_for_road(road: Dictionary) -> float:
    var raw_limit: Variant = road.get("maxspeed_kmh", null)
    if raw_limit != null and (typeof(raw_limit) == TYPE_INT or typeof(raw_limit) == TYPE_FLOAT):
        var tagged_limit := float(raw_limit)
        if tagged_limit > 0.0:
            return clampf(tagged_limit, 5.0, 90.0)
    var road_class := str(road.get("class", ""))
    if road_class in ["living_street", "service"]:
        return minf(default_speed_kmh, 20.0)
    return default_speed_kmh

func _spawn_position_is_clear(position: Vector3) -> bool:
    var player := get_node_or_null(player_path) as Node3D
    if player != null and player.global_position.distance_to(position) < MIN_SPAWN_CLEARANCE_M:
        return false
    for candidate: Node in get_tree().get_nodes_in_group("vehicle"):
        if candidate is Node3D and (candidate as Node3D).global_position.distance_to(position) < MIN_SPAWN_CLEARANCE_M:
            return false
    if _traffic_root != null:
        for child: Node in _traffic_root.get_children():
            if child is Node3D and not child.is_queued_for_deletion():
                if (child as Node3D).global_position.distance_to(position) < MIN_SPAWN_CLEARANCE_M:
                    return false
    return true

func _create_vehicle_node() -> TrafficVehicleCore:
    var archetype := _choose_archetype()
    var vehicle := TrafficVehicleCore.new()
    vehicle.name = "%s_%03d" % [_archetype_node_prefix(archetype), _spawn_serial]
    vehicle.collision_layer = 1
    vehicle.collision_mask = 1
    vehicle.add_to_group("traffic_vehicle")
    vehicle.add_to_group("traffic_%s" % archetype)
    var body_size := _body_size_for(archetype)
    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var box_shape := BoxShape3D.new()
    box_shape.size = body_size
    collision.shape = box_shape
    vehicle.add_child(collision)
    match archetype:
        "scooter": _add_scooter_visual(vehicle)
        "motorcycle": _add_motorcycle_visual(vehicle)
        _: _add_car_visual(vehicle)
    var obstacle_ray := RayCast3D.new()
    obstacle_ray.name = "ObstacleRay"
    obstacle_ray.position = Vector3(0.0, 0.15, -body_size.z * 0.42)
    obstacle_ray.target_position = Vector3(0.0, 0.0, -9.0)
    obstacle_ray.collision_mask = 1
    obstacle_ray.exclude_parent = true
    obstacle_ray.enabled = true
    vehicle.add_child(obstacle_ray)
    vehicle.configure_archetype(archetype)
    vehicle.set_crossing_system(_crossing_system)
    vehicle.traffic_disabled.connect(_on_traffic_vehicle_disabled)
    _spawn_serial += 1
    return vehicle

func _choose_archetype() -> String:
    var scooter := clampf(scooter_share, 0.0, 1.0)
    var motorcycle := clampf(motorcycle_share, 0.0, 1.0 - scooter)
    var roll := _rng.randf()
    if roll < motorcycle:
        return "motorcycle"
    if roll < motorcycle + scooter:
        return "scooter"
    return "car"

func _body_size_for(archetype: String) -> Vector3:
    match archetype:
        "scooter": return SCOOTER_SIZE
        "motorcycle": return MOTORCYCLE_SIZE
        _: return CAR_SIZE

func _archetype_node_prefix(archetype: String) -> String:
    match archetype:
        "scooter": return "TrafficScooter"
        "motorcycle": return "TrafficMotorcycle"
        _: return "TrafficCar"

func _material(color: Color, roughness: float = 0.5, metallic: float = 0.1) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = roughness
    material.metallic = metallic
    return material

func _box_mesh(size: Vector3, color: Color, position: Vector3) -> MeshInstance3D:
    var mesh_instance := MeshInstance3D.new()
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh_instance.mesh = mesh
    mesh_instance.position = position
    mesh_instance.material_override = _material(color)
    return mesh_instance

func _wheel_mesh(radius: float, width: float, position: Vector3) -> MeshInstance3D:
    var wheel := MeshInstance3D.new()
    var cylinder := CylinderMesh.new()
    cylinder.top_radius = radius
    cylinder.bottom_radius = radius
    cylinder.height = width
    wheel.mesh = cylinder
    wheel.rotation.z = PI * 0.5
    wheel.position = position
    wheel.material_override = _material(Color(0.035, 0.035, 0.04, 1.0), 0.9, 0.0)
    return wheel

func _add_car_visual(vehicle: Node3D) -> void:
    var color := MIXED_COLORS[_spawn_serial % MIXED_COLORS.size()]
    var body := _box_mesh(Vector3(1.82, 0.72, 4.15), color, Vector3(0.0, -0.12, 0.0))
    body.name = "Body"
    vehicle.add_child(body)
    var cabin := _box_mesh(Vector3(1.52, 0.66, 1.95), color.lightened(0.08), Vector3(0.0, 0.48, -0.14))
    cabin.name = "Cabin"
    vehicle.add_child(cabin)

func _add_scooter_visual(vehicle: Node3D) -> void:
    var color := MIXED_COLORS[_spawn_serial % MIXED_COLORS.size()]
    var lower := _box_mesh(Vector3(0.58, 0.42, 1.30), color, Vector3(0.0, 0.18, 0.10))
    lower.name = "ScooterBody"
    vehicle.add_child(lower)
    var fairing := _box_mesh(Vector3(0.52, 0.72, 0.45), color.lightened(0.05), Vector3(0.0, 0.48, -0.58))
    vehicle.add_child(fairing)
    var seat := _box_mesh(Vector3(0.46, 0.14, 0.68), Color(0.07, 0.07, 0.08, 1.0), Vector3(0.0, 0.70, 0.35))
    vehicle.add_child(seat)
    vehicle.add_child(_wheel_mesh(0.27, 0.12, Vector3(0.0, -0.10, -0.72)))
    vehicle.add_child(_wheel_mesh(0.27, 0.12, Vector3(0.0, -0.10, 0.72)))

func _add_motorcycle_visual(vehicle: Node3D) -> void:
    var color := MIXED_COLORS[_spawn_serial % MIXED_COLORS.size()]
    var frame := _box_mesh(Vector3(0.48, 0.42, 1.35), color, Vector3(0.0, 0.20, 0.05))
    vehicle.add_child(frame)
    var tank := _box_mesh(Vector3(0.56, 0.40, 0.62), color.lightened(0.06), Vector3(0.0, 0.55, -0.28))
    vehicle.add_child(tank)
    var seat := _box_mesh(Vector3(0.42, 0.14, 0.72), Color(0.06, 0.06, 0.07, 1.0), Vector3(0.0, 0.62, 0.38))
    vehicle.add_child(seat)
    vehicle.add_child(_wheel_mesh(0.34, 0.14, Vector3(0.0, -0.08, -0.86)))
    vehicle.add_child(_wheel_mesh(0.34, 0.14, Vector3(0.0, -0.08, 0.86)))

func _on_route_finished(vehicle: Node) -> void:
    if is_instance_valid(vehicle):
        _intersection_system.call("release_vehicle", vehicle.get_instance_id())
        vehicle.queue_free()
    if auto_spawn_runtime:
        call_deferred("_replenish_traffic")

func _despawn_far_vehicles() -> void:
    if _traffic_root == null:
        return
    var anchor := _anchor_position()
    for child: Node in _traffic_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion():
            if (child as Node3D).global_position.distance_to(anchor) > despawn_radius_m:
                _intersection_system.call("release_vehicle", child.get_instance_id())
                child.queue_free()

func _attach_crossing_system_to_vehicles() -> void:
    if _traffic_root == null or _crossing_system == null:
        return
    for child: Node in _traffic_root.get_children():
        if child.has_method("set_crossing_system"):
            child.call("set_crossing_system", _crossing_system)

func _replenish_crossing_pedestrians() -> void:
    if not auto_spawn_runtime or _crossing_root == null or _crossing_system == null or max_crossing_pedestrians <= 0:
        return
    var active_crossings: Dictionary = {}
    for child: Node in _crossing_root.get_children():
        if not child.is_queued_for_deletion() and child.has_method("get_crossing_id"):
            active_crossings[int(child.call("get_crossing_id"))] = true
    var candidates: Array = _crossing_system.call("get_crossings_near", _anchor_position(), crossing_spawn_radius_m, true)
    if candidates.is_empty():
        candidates = _crossing_system.call("get_crossings_near", _anchor_position(), 100000.0, true)
    var attempts := 0
    while get_active_crossing_pedestrian_count() < max_crossing_pedestrians and attempts < candidates.size() * 3:
        attempts += 1
        var descriptor: Dictionary = candidates[_rng.randi_range(0, candidates.size() - 1)]
        var crossing_id := int(descriptor.get("id", 0))
        if crossing_id <= 0 or active_crossings.has(crossing_id):
            continue
        _spawn_crossing_pedestrian(descriptor)
        active_crossings[crossing_id] = true

func _spawn_crossing_pedestrian(descriptor: Dictionary) -> void:
    var pedestrian := TrafficCrossingPedestrian.new()
    pedestrian.name = "CrossingPedestrian_%03d" % _pedestrian_serial
    pedestrian.add_to_group("traffic_crossing_pedestrian")
    var body := MeshInstance3D.new()
    var capsule := CapsuleMesh.new()
    capsule.radius = 0.25
    capsule.height = 1.15
    body.mesh = capsule
    body.position.y = 0.78
    body.material_override = _material(Color(0.28 + 0.07 * float(_pedestrian_serial % 5), 0.34, 0.42, 1.0), 0.85, 0.0)
    pedestrian.add_child(body)
    _crossing_root.add_child(pedestrian)
    pedestrian.crossing_finished.connect(_on_crossing_pedestrian_finished)
    pedestrian.configure(descriptor, _crossing_system, _pedestrian_serial, bool(_rng.randi_range(0, 1)), _rng.randf_range(0.7, 2.2))
    _pedestrian_serial += 1

func _on_crossing_pedestrian_finished(pedestrian: Node) -> void:
    if is_instance_valid(pedestrian):
        pedestrian.queue_free()
    if auto_spawn_runtime:
        call_deferred("_replenish_crossing_pedestrians")

func _despawn_far_crossing_pedestrians() -> void:
    if _crossing_root == null:
        return
    var anchor := _anchor_position()
    for child: Node in _crossing_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion():
            if (child as Node3D).global_position.distance_to(anchor) > despawn_radius_m:
                child.queue_free()

func set_simulation_hour(hour: float) -> void:
    simulation_hour = fposmod(hour, 24.0)
    _apply_density_now()

func set_density_enabled(enabled: bool) -> void:
    density_enabled = enabled
    _apply_density_now()

func _apply_density_now() -> void:
    if _density_model == null:
        return
    if not density_enabled:
        max_vehicles = _base_max_vehicles
        _current_density_factor = 1.0
        _current_sector = str(_density_model.call("nearest_sector", _corridor_anchors, _anchor_position()))
        return
    var anchor := _anchor_position()
    var time_factor := float(_density_model.call("time_factor", simulation_hour))
    var capacity_factor := float(_density_model.call("local_capacity_factor", _roads, anchor))
    _current_density_factor = time_factor * capacity_factor
    _current_sector = str(_density_model.call("nearest_sector", _corridor_anchors, anchor))
    max_vehicles = int(_density_model.call("target_vehicle_count", _base_max_vehicles, simulation_hour, _roads, anchor))
    _trim_excess_traffic(max_vehicles)

func _trim_excess_traffic(target: int) -> void:
    if _traffic_root == null:
        return
    var active: Array[Node] = []
    for child: Node in _traffic_root.get_children():
        if not child.is_queued_for_deletion():
            active.append(child)
    if active.size() <= target:
        return
    var anchor := _anchor_position()
    active.sort_custom(func(a: Node, b: Node) -> bool:
        if not a is Node3D or not b is Node3D:
            return false
        return (a as Node3D).global_position.distance_to(anchor) > (b as Node3D).global_position.distance_to(anchor)
    )
    for index: int in range(target, active.size()):
        active[index].queue_free()

func _replenish_parked_vehicles() -> void:
    if not auto_spawn_runtime or _parking_root == null or _parking_model == null or max_parked_vehicles <= 0:
        return
    var nearby: Array = _parking_model.call("candidates_near", _parking_candidates, _anchor_position(), parking_spawn_radius_m)
    if nearby.is_empty():
        nearby = _parking_model.call("candidates_near", _parking_candidates, _anchor_position(), 100000.0)
    var occupied := _occupied_parking_candidate_ids()
    for raw_id: Variant in _reserved_parking_candidate_ids.keys():
        occupied[int(raw_id)] = true
    var attempts := 0
    while get_parked_vehicle_count() < max_parked_vehicles and attempts < nearby.size() * 3:
        attempts += 1
        var candidate: Dictionary = nearby[_parking_rng.randi_range(0, nearby.size() - 1)]
        var candidate_id := int(candidate.get("id", -1))
        if candidate_id < 0 or occupied.has(candidate_id):
            continue
        _spawn_parked_vehicle(candidate)
        occupied[candidate_id] = true

func _occupied_parking_candidate_ids() -> Dictionary:
    var occupied: Dictionary = {}
    if _parking_root == null:
        return occupied
    for child: Node in _parking_root.get_children():
        if not child.is_queued_for_deletion():
            occupied[int(child.get_meta("parking_candidate_id", -1))] = true
    return occupied

func reserve_parking_candidate(candidate_id: int, reservation_owner: String) -> bool:
    if candidate_id < 0 or reservation_owner.is_empty():
        return false
    if _reserved_parking_candidate_ids.has(candidate_id):
        return str(_reserved_parking_candidate_ids[candidate_id]) == reservation_owner
    if _occupied_parking_candidate_ids().has(candidate_id):
        return false
    _reserved_parking_candidate_ids[candidate_id] = reservation_owner
    return true

func release_parking_candidate(candidate_id: int, reservation_owner: String = "") -> void:
    if not _reserved_parking_candidate_ids.has(candidate_id):
        return
    if not reservation_owner.is_empty() and str(_reserved_parking_candidate_ids[candidate_id]) != reservation_owner:
        return
    _reserved_parking_candidate_ids.erase(candidate_id)

func is_parking_candidate_available(candidate_id: int) -> bool:
    if candidate_id < 0 or _reserved_parking_candidate_ids.has(candidate_id):
        return false
    return not _occupied_parking_candidate_ids().has(candidate_id)

func _spawn_parked_vehicle(candidate: Dictionary) -> void:
    var body := StaticBody3D.new()
    body.name = "ParkedCar_%03d" % int(candidate.get("id", 0))
    body.collision_layer = 1
    body.collision_mask = 1
    body.set_meta("parking_candidate_id", int(candidate.get("id", -1)))
    body.set_meta("simulated_occupancy", true)
    body.set_meta("road_name", str(candidate.get("road_name", "")))
    body.set_meta("source_osm_id", int(candidate.get("osm_id", 0)))
    body.position = candidate.get("position", Vector3.ZERO)
    body.rotation.y = float(candidate.get("yaw", 0.0))
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = PARKED_CAR_SIZE
    collision.shape = shape
    body.add_child(collision)
    var color := MIXED_COLORS[int(candidate.get("id", 0)) % MIXED_COLORS.size()].darkened(0.05)
    body.add_child(_box_mesh(Vector3(1.82, 0.70, 4.12), color, Vector3(0.0, -0.10, 0.0)))
    body.add_child(_box_mesh(Vector3(1.48, 0.62, 1.88), color.lightened(0.06), Vector3(0.0, 0.46, -0.12)))
    _parking_root.add_child(body)

func _despawn_far_parked_vehicles() -> void:
    if _parking_root == null:
        return
    var anchor := _anchor_position()
    var limit := maxf(parking_spawn_radius_m * 1.6, 120.0)
    for child: Node in _parking_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion():
            if (child as Node3D).global_position.distance_to(anchor) > limit:
                child.queue_free()

func _replenish_deliveries() -> void:
    if not auto_spawn_runtime or _delivery_root == null or max_delivery_vehicles <= 0:
        return
    var anchor := _anchor_position()
    var eligible: Array[Dictionary] = []
    for candidate: Dictionary in _parking_candidates:
        if not DELIVERY_CLASSES.has(str(candidate.get("road_class", ""))):
            continue
        var position: Vector3 = candidate.get("position", Vector3.ZERO)
        if position.distance_to(anchor) > delivery_spawn_radius_m:
            continue
        var candidate_id := int(candidate.get("id", -1))
        if is_parking_candidate_available(candidate_id):
            eligible.append(candidate)
    var attempts := 0
    while get_delivery_vehicle_count() < max_delivery_vehicles and attempts < eligible.size() * 3:
        attempts += 1
        var candidate: Dictionary = eligible[_delivery_rng.randi_range(0, eligible.size() - 1)]
        var candidate_id := int(candidate.get("id", -1))
        var owner := "delivery:%d" % _delivery_serial
        if not reserve_parking_candidate(candidate_id, owner):
            continue
        _spawn_delivery_vehicle(candidate, owner)
        eligible.erase(candidate)
        if eligible.is_empty():
            break

func _spawn_delivery_vehicle(candidate: Dictionary, reservation_owner: String) -> void:
    var van := StaticBody3D.new()
    van.name = "DeliveryVan_%03d" % _delivery_serial
    van.collision_layer = 1
    van.collision_mask = 1
    van.position = candidate.get("position", Vector3.ZERO)
    van.rotation.y = float(candidate.get("yaw", 0.0))
    van.set_meta("parking_candidate_id", int(candidate.get("id", -1)))
    van.set_meta("reservation_owner", reservation_owner)
    van.set_meta("simulated_delivery", true)
    van.set_meta("road_name", str(candidate.get("road_name", "")))
    van.set_meta("source_osm_id", int(candidate.get("osm_id", 0)))
    var min_duration := maxf(0.1, minf(delivery_duration_min_s, delivery_duration_max_s))
    var max_duration := maxf(min_duration, maxf(delivery_duration_min_s, delivery_duration_max_s))
    van.set_meta("expires_at_s", float(Time.get_ticks_msec()) / 1000.0 + _delivery_rng.randf_range(min_duration, max_duration))
    var collision := CollisionShape3D.new()
    var shape := BoxShape3D.new()
    shape.size = DELIVERY_VAN_SIZE
    collision.shape = shape
    van.add_child(collision)
    van.add_child(_box_mesh(Vector3(2.02, 1.42, 5.15), Color(0.78, 0.79, 0.77, 1.0), Vector3(0.0, 0.12, 0.0)))
    van.add_child(_box_mesh(Vector3(1.88, 0.64, 1.48), Color(0.68, 0.70, 0.71, 1.0), Vector3(0.0, 0.78, -1.48)))
    _delivery_root.add_child(van)
    _delivery_serial += 1

func expire_deliveries_at(now_seconds: float) -> int:
    if _delivery_root == null:
        return 0
    var expired := 0
    for child: Node in _delivery_root.get_children():
        if child.is_queued_for_deletion():
            continue
        if now_seconds < float(child.get_meta("expires_at_s", INF)):
            continue
        _release_delivery_slot(child)
        child.queue_free()
        expired += 1
    return expired

func _despawn_far_deliveries() -> void:
    if _delivery_root == null:
        return
    var anchor := _anchor_position()
    var limit := maxf(delivery_spawn_radius_m * 1.7, 140.0)
    for child: Node in _delivery_root.get_children():
        if child is Node3D and not child.is_queued_for_deletion():
            if (child as Node3D).global_position.distance_to(anchor) > limit:
                _release_delivery_slot(child)
                child.queue_free()

func _release_delivery_slot(delivery: Node) -> void:
    release_parking_candidate(int(delivery.get_meta("parking_candidate_id", -1)), str(delivery.get_meta("reservation_owner", "")))

func _on_traffic_vehicle_disabled(vehicle: Node) -> void:
    if not is_instance_valid(vehicle):
        return
    vehicle.add_to_group("traffic_wreck")
    vehicle.set_meta("traffic_wrecked", true)
    if not vehicle.has_meta("traffic_wrecked_at_s"):
        vehicle.set_meta("traffic_wrecked_at_s", float(Time.get_ticks_msec()) / 1000.0)
    vehicle.set_meta("traffic_wreck_clear_after_s", _effective_wreck_delay())

func _effective_wreck_delay() -> float:
    if get_wreck_count() >= max_wrecks_before_fast_clear:
        return maxf(4.0, wreck_clear_delay_s * 0.45)
    return maxf(1.0, wreck_clear_delay_s)

func cleanup_wrecks_at(now_seconds: float) -> int:
    if _traffic_root == null:
        return 0
    var cleared := 0
    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not bool(child.get_meta("traffic_wrecked", false)):
            continue
        var wrecked_at := float(child.get_meta("traffic_wrecked_at_s", now_seconds))
        var delay := float(child.get_meta("traffic_wreck_clear_after_s", wreck_clear_delay_s))
        if now_seconds < wrecked_at + maxf(0.0, delay):
            continue
        child.queue_free()
        cleared += 1
    if cleared > 0 and auto_spawn_runtime:
        call_deferred("_replenish_traffic")
    return cleared

func get_route_count() -> int:
    return _roads.size()

func get_graph_node_count() -> int:
    return 0 if _road_graph == null else int(_road_graph.call("get_node_count"))

func get_graph_edge_count() -> int:
    return 0 if _road_graph == null else int(_road_graph.call("get_edge_count"))

func get_intersection_count() -> int:
    return 0 if _intersection_system == null else int(_intersection_system.call("get_intersection_count"))

func get_right_priority_count() -> int:
    return 0 if _intersection_system == null else int(_intersection_system.call("get_right_priority_count"))

func get_traffic_control_count() -> int:
    return 0 if _control_system == null else int(_control_system.call("get_control_count"))

func get_signal_count() -> int:
    return 0 if _control_system == null else int(_control_system.call("get_signal_count"))

func get_crossing_count() -> int:
    return 0 if _crossing_system == null else int(_crossing_system.call("get_crossing_count"))

func get_unsignalized_crossing_count() -> int:
    return 0 if _crossing_system == null else int(_crossing_system.call("get_unsignalized_crossing_count"))

func get_active_crossing_count() -> int:
    return 0 if _crossing_system == null else int(_crossing_system.call("get_active_crossing_count"))

func get_active_crossing_pedestrian_count() -> int:
    if _crossing_root == null:
        return 0
    var count := 0
    for child: Node in _crossing_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count

func get_parking_candidate_count() -> int:
    return _parking_candidates.size()

func get_parked_vehicle_count() -> int:
    if _parking_root == null:
        return 0
    var count := 0
    for child: Node in _parking_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count

func get_delivery_vehicle_count() -> int:
    if _delivery_root == null:
        return 0
    var count := 0
    for child: Node in _delivery_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count

func get_reserved_parking_candidate_count() -> int:
    return _reserved_parking_candidate_ids.size()

func get_active_vehicle_count() -> int:
    if _traffic_root == null:
        return 0
    var count := 0
    for child: Node in _traffic_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count

func get_wreck_count() -> int:
    if _traffic_root == null:
        return 0
    var count := 0
    for child: Node in _traffic_root.get_children():
        if not child.is_queued_for_deletion() and bool(child.get_meta("traffic_wrecked", false)):
            count += 1
    return count

func get_default_speed_kmh() -> float:
    return default_speed_kmh

func get_density_factor() -> float:
    return _current_density_factor

func get_density_sector() -> String:
    return _current_sector

func get_density_base_max_vehicles() -> int:
    return _base_max_vehicles

func get_density_target_vehicle_count() -> int:
    return max_vehicles

func get_active_archetype_counts() -> Dictionary:
    var counts := {"car": 0, "scooter": 0, "motorcycle": 0}
    if _traffic_root == null:
        return counts
    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not child.has_method("get_traffic_archetype"):
            continue
        var archetype := str(child.call("get_traffic_archetype"))
        counts[archetype] = int(counts.get(archetype, 0)) + 1
    return counts
