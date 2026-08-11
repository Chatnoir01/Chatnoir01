extends Node3D

@export_file("*.json") var data_path: String = "res://data/osm/vertical_slice_01.game.json"
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

const TRAFFIC_VEHICLE_SCRIPT := preload("res://game/scripts/traffic_vehicle.gd")
const ROAD_GRAPH_SCRIPT := preload("res://game/scripts/traffic_road_graph.gd")
const FALLBACK_ANCHOR := Vector3(-668.5, 0.0, 627.84)
const VEHICLE_BODY_SIZE := Vector3(1.82, 1.16, 4.15)
const MIN_SPAWN_CLEARANCE_M := 7.0
const MAX_SPAWN_ATTEMPTS := 64

const CAR_COLORS: Array[Color] = [
    Color(0.18, 0.20, 0.22, 1.0),
    Color(0.36, 0.39, 0.42, 1.0),
    Color(0.12, 0.24, 0.38, 1.0),
    Color(0.43, 0.12, 0.10, 1.0),
    Color(0.73, 0.73, 0.69, 1.0),
    Color(0.12, 0.31, 0.22, 1.0),
]

var _roads: Array[Dictionary] = []
var _road_graph: RefCounted
var _traffic_root: Node3D
var _rng := RandomNumberGenerator.new()
var _spawn_serial: int = 0
var _maintenance_elapsed: float = 0.0


func _ready() -> void:
    _rng.seed = traffic_seed
    _road_graph = ROAD_GRAPH_SCRIPT.new()

    _traffic_root = Node3D.new()
    _traffic_root.name = "TrafficVehicles"
    add_child(_traffic_root)

    _load_roads()
    _replenish_traffic()
    print(
        "Grand Bruxelles traffic graph: %d OSM ways, %d nodes, %d directed edges, %d intersections, %d AI vehicles" %
        [
            _roads.size(),
            get_graph_node_count(),
            get_graph_edge_count(),
            get_intersection_count(),
            get_active_vehicle_count(),
        ]
    )


func _process(delta: float) -> void:
    _maintenance_elapsed += delta
    if _maintenance_elapsed < maintenance_interval_s:
        return
    _maintenance_elapsed = 0.0
    _despawn_far_vehicles()
    _replenish_traffic()


func _load_roads() -> void:
    _roads.clear()
    if not FileAccess.file_exists(data_path):
        push_warning("Traffic OSM data missing: %s" % data_path)
        return

    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        push_error("Traffic OSM data is invalid JSON: %s" % data_path)
        return

    var root_data: Dictionary = parsed
    var raw_roads: Array = root_data.get("roads", [])
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
        _roads.append(road)

    if _road_graph != null:
        _road_graph.call("rebuild", _roads)


func _road_is_access_restricted(road: Dictionary) -> bool:
    var access := str(road.get("access", "")).to_lower()
    var motor_vehicle := str(road.get("motor_vehicle", "")).to_lower()
    return access in ["no", "private"] or motor_vehicle in ["no", "private"]


func _anchor_position() -> Vector3:
    var player := get_node_or_null(player_path) as Node3D
    if player != null:
        return player.global_position
    return FALLBACK_ANCHOR


func _replenish_traffic() -> void:
    if _traffic_root == null or _road_graph == null or max_vehicles <= 0:
        return
    if get_graph_edge_count() <= 0:
        return

    var safety := 0
    while get_active_vehicle_count() < max_vehicles and safety < max_vehicles * 5:
        safety += 1
        if not _spawn_one_vehicle():
            break


func _spawn_one_vehicle() -> bool:
    var anchor := _anchor_position()
    var candidates: Array = _road_graph.call(
        "find_candidate_edge_ids",
        anchor,
        spawn_radius_m
    )
    if candidates.is_empty():
        candidates = _road_graph.call("find_candidate_edge_ids", anchor, 100000.0)
    if candidates.is_empty():
        return false

    for _attempt: int in range(MAX_SPAWN_ATTEMPTS):
        var start_edge_id := int(candidates[_rng.randi_range(0, candidates.size() - 1)])
        var edge_ids: Array = _road_graph.call(
            "build_random_walk",
            start_edge_id,
            _rng,
            route_target_length_m,
            route_max_length_m,
            max_route_edges
        )
        if edge_ids.size() < 2:
            continue

        var route_bundle := _route_bundle_from_edges(edge_ids)
        var route: PackedVector3Array = route_bundle.get("points", PackedVector3Array())
        if route.size() < 3:
            continue
        if _packed_route_length(route) < min_route_length_m:
            continue
        if not _spawn_position_is_clear(route[0]):
            continue

        var vehicle := _create_vehicle_node()
        _traffic_root.add_child(vehicle)
        vehicle.global_position = route[0]
        vehicle.connect("route_finished", Callable(self, "_on_route_finished"))
        vehicle.call(
            "configure_route_profile",
            route,
            route_bundle.get("speed_limits_kmh", PackedFloat32Array()),
            str(route_bundle.get("road_name", "")),
            int(route_bundle.get("osm_id", 0)),
            edge_ids.size()
        )
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

    return {
        "points": points,
        "speed_limits_kmh": speed_limits,
        "road_name": first_road_name,
        "osm_id": first_osm_id,
    }


func _lane_offset_for_road(road: Dictionary) -> float:
    var width := maxf(3.0, float(road.get("width", 5.6)))
    var oneway := _normalized_oneway(road)
    var lanes := maxi(0, int(road.get("lanes", 0)))

    if oneway != 0:
        if lanes >= 2:
            return clampf(width * 0.18, 0.7, 1.65)
        return clampf(width * 0.08, 0.25, 0.65)
    return clampf(width * 0.23, 1.0, 2.05)


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
        if candidate is Node3D:
            var node := candidate as Node3D
            if node.global_position.distance_to(position) < MIN_SPAWN_CLEARANCE_M:
                return false

    if _traffic_root != null:
        for child: Node in _traffic_root.get_children():
            if child is Node3D and not child.is_queued_for_deletion():
                var node := child as Node3D
                if node.global_position.distance_to(position) < MIN_SPAWN_CLEARANCE_M:
                    return false
    return true


func _create_vehicle_node() -> CharacterBody3D:
    var vehicle := CharacterBody3D.new()
    vehicle.name = "TrafficCar_%03d" % _spawn_serial
    vehicle.set_script(TRAFFIC_VEHICLE_SCRIPT)
    vehicle.collision_layer = 1
    vehicle.collision_mask = 1
    vehicle.add_to_group("traffic_vehicle")

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var box_shape := BoxShape3D.new()
    box_shape.size = VEHICLE_BODY_SIZE
    collision.shape = box_shape
    vehicle.add_child(collision)

    var body_mesh := MeshInstance3D.new()
    body_mesh.name = "Body"
    var body_box := BoxMesh.new()
    body_box.size = Vector3(1.82, 0.72, 4.15)
    body_mesh.mesh = body_box
    var body_material := StandardMaterial3D.new()
    body_material.albedo_color = CAR_COLORS[_spawn_serial % CAR_COLORS.size()]
    body_material.roughness = 0.48
    body_material.metallic = 0.18
    body_mesh.material_override = body_material
    body_mesh.position.y = -0.12
    vehicle.add_child(body_mesh)

    var cabin_mesh := MeshInstance3D.new()
    cabin_mesh.name = "Cabin"
    var cabin_box := BoxMesh.new()
    cabin_box.size = Vector3(1.52, 0.66, 1.95)
    cabin_mesh.mesh = cabin_box
    var cabin_material := StandardMaterial3D.new()
    cabin_material.albedo_color = body_material.albedo_color.lightened(0.08)
    cabin_material.roughness = 0.38
    cabin_material.metallic = 0.12
    cabin_mesh.material_override = cabin_material
    cabin_mesh.position = Vector3(0.0, 0.48, -0.14)
    vehicle.add_child(cabin_mesh)

    var obstacle_ray := RayCast3D.new()
    obstacle_ray.name = "ObstacleRay"
    obstacle_ray.position = Vector3(0.0, 0.15, -1.75)
    obstacle_ray.target_position = Vector3(0.0, 0.0, -9.0)
    obstacle_ray.collision_mask = 1
    obstacle_ray.exclude_parent = true
    obstacle_ray.enabled = true
    vehicle.add_child(obstacle_ray)

    _spawn_serial += 1
    return vehicle


func _on_route_finished(vehicle: Node) -> void:
    if is_instance_valid(vehicle):
        vehicle.queue_free()
    call_deferred("_replenish_traffic")


func _despawn_far_vehicles() -> void:
    if _traffic_root == null:
        return
    var anchor := _anchor_position()
    for child: Node in _traffic_root.get_children():
        if not child is Node3D or child.is_queued_for_deletion():
            continue
        var vehicle := child as Node3D
        if vehicle.global_position.distance_to(anchor) > despawn_radius_m:
            vehicle.queue_free()


func get_route_count() -> int:
    return _roads.size()


func get_graph_node_count() -> int:
    if _road_graph == null:
        return 0
    return int(_road_graph.call("get_node_count"))


func get_graph_edge_count() -> int:
    if _road_graph == null:
        return 0
    return int(_road_graph.call("get_edge_count"))


func get_intersection_count() -> int:
    if _road_graph == null:
        return 0
    return int(_road_graph.call("get_intersection_count"))


func get_active_vehicle_count() -> int:
    if _traffic_root == null:
        return 0
    var count := 0
    for child: Node in _traffic_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count


func get_default_speed_kmh() -> float:
    return default_speed_kmh
