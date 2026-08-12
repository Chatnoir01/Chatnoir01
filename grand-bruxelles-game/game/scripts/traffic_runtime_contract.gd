extends RefCounted
class_name TrafficRuntimeContract

const MANAGER_METHODS: PackedStringArray = [
    "get_route_count",
    "get_graph_node_count",
    "get_graph_edge_count",
    "get_intersection_count",
    "get_right_priority_count",
    "get_traffic_control_count",
    "get_signal_count",
    "get_crossing_count",
    "get_unsignalized_crossing_count",
    "get_active_crossing_pedestrian_count",
    "get_parking_candidate_count",
    "get_parked_vehicle_count",
    "get_delivery_vehicle_count",
    "get_reserved_parking_candidate_count",
    "get_active_vehicle_count",
    "get_wreck_count",
    "cleanup_wrecks_at",
]

const OPTIONAL_TOW_METHODS: PackedStringArray = [
    "get_tow_service_count",
    "get_visible_tow_service_count",
    "process_tow_services_at",
]

const VEHICLE_METHODS: PackedStringArray = [
    "get_speed_kmh",
    "get_speed_limit_kmh",
    "get_road_name",
    "get_source_osm_id",
    "get_route_point_count",
    "get_route_edge_count",
    "get_route_control_count",
    "get_route_intersection_count",
    "set_crossing_system",
]

const REQUIRED_MANAGER_ROOTS: PackedStringArray = [
    "TrafficVehicles",
    "CrossingPedestrians",
    "ParkedVehicles",
    "DeliveryVehicles",
]

const ACTIVE_LEGACY_BASELINE := "traffic_manager_core_v8"
const OPTIONAL_LEGACY_EXTENSION := "traffic_manager_core_v9_tow"
const CANONICAL_MANAGER_TARGET := "traffic_manager_core.gd"
const CANONICAL_VEHICLE_TARGET := "traffic_vehicle_core.gd"

static func missing_methods(target: Object, required: PackedStringArray) -> PackedStringArray:
    var missing := PackedStringArray()
    for method_name: String in required:
        if not target.has_method(method_name):
            missing.append(method_name)
    return missing

static func validate_manager(target: Object, require_tow: bool = false) -> PackedStringArray:
    var required := MANAGER_METHODS.duplicate()
    if require_tow:
        required.append_array(OPTIONAL_TOW_METHODS)
    return missing_methods(target, required)

static func validate_vehicle(target: Object) -> PackedStringArray:
    return missing_methods(target, VEHICLE_METHODS)
