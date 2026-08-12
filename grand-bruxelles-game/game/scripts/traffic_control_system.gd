extends RefCounted

const SIGNAL_CLUSTER_RADIUS_M := 22.0
const ROUTE_CONTROL_SNAP_M := 6.5

var _controls: Array[Dictionary] = []
var _signal_clusters: Array[Dictionary] = []

func rebuild(raw_controls: Array) -> void:
    _controls.clear()
    _signal_clusters.clear()
    for raw_control: Variant in raw_controls:
        if typeof(raw_control) != TYPE_DICTIONARY:
            continue
        var source: Dictionary = raw_control
        var raw_point: Variant = source.get("point", null)
        if raw_point == null or not raw_point is Array or raw_point.size() < 2:
            continue
        var control := source.duplicate(true)
        control["position"] = Vector3(float(raw_point[0]), 0.68, float(raw_point[1]))
        control["cluster_id"] = -1
        _controls.append(control)
    _cluster_signals()

func _cluster_signals() -> void:
    for control_index: int in range(_controls.size()):
        var control: Dictionary = _controls[control_index]
        if str(control.get("kind", "")) != "traffic_signals":
            continue
        var position: Vector3 = control["position"]
        var selected_cluster := -1
        for cluster_index: int in range(_signal_clusters.size()):
            var cluster: Dictionary = _signal_clusters[cluster_index]
            var center: Vector3 = cluster["center"]
            if center.distance_to(position) <= SIGNAL_CLUSTER_RADIUS_M:
                selected_cluster = cluster_index
                break
        if selected_cluster < 0:
            selected_cluster = _signal_clusters.size()
            _signal_clusters.append({"center": position, "count": 1})
        else:
            var cluster: Dictionary = _signal_clusters[selected_cluster]
            var count := int(cluster.get("count", 1))
            var center: Vector3 = cluster["center"]
            cluster["center"] = (center * float(count) + position) / float(count + 1)
            cluster["count"] = count + 1
            _signal_clusters[selected_cluster] = cluster
        control["cluster_id"] = selected_cluster
        _controls[control_index] = control

func controls_for_route(route: PackedVector3Array) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if route.size() < 2:
        return result
    for control: Dictionary in _controls:
        var position: Vector3 = control["position"]
        var nearest := _nearest_route_segment(route, position)
        var distance := float(nearest.get("distance_m", INF))
        if distance > ROUTE_CONTROL_SNAP_M:
            continue
        var segment_index := int(nearest.get("segment_index", -1))
        if segment_index < 0 or segment_index >= route.size() - 1:
            continue
        var route_control := control.duplicate(true)
        var route_index := segment_index + 1
        var direction := route[route_index] - route[segment_index]
        direction.y = 0.0
        if direction.length_squared() > 0.001:
            direction = direction.normalized()
        route_control["route_index"] = route_index
        route_control["route_position"] = route[route_index]
        route_control["approach_direction"] = direction
        route_control["route_distance_m"] = distance
        result.append(route_control)
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("route_index", 0)) < int(b.get("route_index", 0)))
    return result

func _nearest_route_segment(route: PackedVector3Array, point: Vector3) -> Dictionary:
    var best_distance := INF
    var best_index := -1
    for index: int in range(route.size() - 1):
        var distance := _point_segment_distance(point, route[index], route[index + 1])
        if distance < best_distance:
            best_distance = distance
            best_index = index
    return {"segment_index": best_index, "distance_m": best_distance}

func _point_segment_distance(point: Vector3, start: Vector3, finish: Vector3) -> float:
    var segment := finish - start
    segment.y = 0.0
    var length_squared := segment.length_squared()
    if length_squared <= 0.0001:
        var flat_point := point
        flat_point.y = start.y
        return flat_point.distance_to(start)
    var relative := point - start
    relative.y = 0.0
    var t := clampf(relative.dot(segment) / length_squared, 0.0, 1.0)
    var nearest := start + segment * t
    var flat := point
    flat.y = nearest.y
    return flat.distance_to(nearest)

func signal_state_for(control: Dictionary, _approach_direction: Vector3, _now_seconds: float = -1.0) -> String:
    if str(control.get("kind", "")) != "traffic_signals":
        return "green"
    # Canonical controls currently prove signal location, not a source-backed live phase
    # programme or timing. Keep the state unresolved instead of fabricating Brussels
    # priority behaviour. Vehicle control only acts on explicit red/amber states.
    return "unknown"

func get_control_count() -> int:
    return _controls.size()

func get_signal_count() -> int:
    var count := 0
    for control: Dictionary in _controls:
        if str(control.get("kind", "")) == "traffic_signals":
            count += 1
    return count

func get_signal_cluster_count() -> int:
    return _signal_clusters.size()
