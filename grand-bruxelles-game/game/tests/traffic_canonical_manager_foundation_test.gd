extends SceneTree

const ROAD_GRAPH := preload("res://game/scripts/traffic_road_graph.gd")
const CONTROL_SYSTEM := preload("res://game/scripts/traffic_control_system.gd")
const INTERSECTION_SYSTEM := preload("res://game/scripts/traffic_intersection_system.gd")
const CROSSING_SYSTEM := preload("res://game/scripts/traffic_crossing_system.gd")
const DENSITY_MODEL := preload("res://game/scripts/traffic_density_model.gd")
const PARKING_MODEL := preload("res://game/scripts/traffic_parking_model.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_MANAGER_FOUNDATION_FAIL: %s" % message)
    quit(1)

func _road(points: Array, osm_id: int, road_class: String = "residential", oneway: Variant = 0, width: float = 6.0, lanes: int = 2) -> Dictionary:
    return {
        "points": points,
        "osm_id": osm_id,
        "class": road_class,
        "drivable": true,
        "oneway": oneway,
        "width": width,
        "lanes": lanes,
        "name": "Synthetic %d" % osm_id,
    }

func _run() -> void:
    var roads: Array[Dictionary] = [
        _road([[-40.0, 0.0], [0.0, 0.0], [40.0, 0.0]], 1001),
        _road([[0.0, -40.0], [0.0, 0.0], [0.0, 40.0]], 1002),
        _road([[60.0, 0.0], [100.0, 0.0]], 1003, "secondary", 1, 7.0, 2),
        _road([[0.0, 70.0], [60.0, 70.0]], 1004, "residential", 0, 6.0, 2),
    ]
    var controls: Array = [
        {"kind": "traffic_signals", "osm_id": 2001, "point": [0.0, 0.0]},
        {"kind": "crossing", "osm_id": 2002, "point": [30.0, 70.0], "crossing_signals": false},
    ]

    var graph: RefCounted = ROAD_GRAPH.new()
    graph.call("rebuild", roads)
    if int(graph.call("get_node_count")) < 8:
        _fail("road graph lost canonical nodes")
        return
    if int(graph.call("get_edge_count")) != 11:
        _fail("one-way/two-way edge semantics drifted: %d" % int(graph.call("get_edge_count")))
        return

    var control_system: RefCounted = CONTROL_SYSTEM.new()
    control_system.call("rebuild", controls)
    if int(control_system.call("get_control_count")) != 2 or int(control_system.call("get_signal_count")) != 1:
        _fail("control inventory drifted")
        return
    var route := PackedVector3Array([Vector3(-40.0, 0.68, 0.0), Vector3(0.0, 0.68, 0.0), Vector3(40.0, 0.68, 0.0)])
    var route_controls: Array = control_system.call("controls_for_route", route)
    if route_controls.is_empty():
        _fail("traffic signal did not snap to route")
        return
    var signal_control: Dictionary = route_controls[0]
    for raw_now_seconds in [0.0, 28.0, 35.0, 40.0, 63.0, 69.9, 140.0]:
        var state := str(control_system.call("signal_state_for", signal_control, Vector3.RIGHT, float(raw_now_seconds)))
        if state != "unknown":
            _fail("unsourced traffic signal phase became %s at %.1f s" % [state, float(raw_now_seconds)])
            return

    var no_priority_controls: Array = [controls[1]]
    var intersection_system: RefCounted = INTERSECTION_SYSTEM.new()
    intersection_system.call("rebuild", roads, no_priority_controls)
    if int(intersection_system.call("get_intersection_count")) < 1:
        _fail("four-way intersection was not detected")
        return
    if int(intersection_system.call("get_right_priority_count")) < 1:
        _fail("uncontrolled Brussels intersection lost priority-to-right classification")
        return

    var crossing_system: RefCounted = CROSSING_SYSTEM.new()
    crossing_system.call("rebuild", roads, controls)
    if int(crossing_system.call("get_crossing_count")) != 1 or int(crossing_system.call("get_unsignalized_crossing_count")) != 1:
        _fail("crossing inventory drifted")
        return
    if not bool(crossing_system.call("register_waiting", 2002, 5001)):
        _fail("pedestrian could not register at mapped crossing")
        return
    if not bool(crossing_system.call("crossing_requires_stop", 2002)):
        _fail("waiting pedestrian no longer requests vehicle stop")
        return
    crossing_system.call("clear_pedestrian", 2002, 5001)
    if bool(crossing_system.call("crossing_requires_stop", 2002)):
        _fail("crossing occupancy did not clear deterministically")
        return

    var density: RefCounted = DENSITY_MODEL.new()
    var night_factor: float = float(density.call("time_factor", 3.0))
    var evening_peak: float = float(density.call("time_factor", 17.0))
    if evening_peak <= night_factor:
        _fail("time-of-day density no longer distinguishes peak from deep night")
        return
    var peak_target: int = int(density.call("target_vehicle_count", 20, 17.0, roads, Vector3.ZERO))
    var night_target: int = int(density.call("target_vehicle_count", 20, 3.0, roads, Vector3.ZERO))
    if peak_target <= night_target:
        _fail("density target did not increase at peak hour")
        return

    var parking: RefCounted = PARKING_MODEL.new()
    var unsourced_candidates: Array = parking.call("build_candidates", roads, controls)
    if not unsourced_candidates.is_empty():
        _fail("unsourced road classes manufactured parking candidates")
        return

    var approved_roads: Array[Dictionary] = []
    for source_road: Dictionary in roads:
        var approved := source_road.duplicate(true)
        approved["parking_evidence"] = {
            "runtime_approved": true,
            "source": "synthetic_test_fixture",
        }
        approved_roads.append(approved)
    var parking_candidates: Array = parking.call("build_candidates", approved_roads, controls)
    if parking_candidates.is_empty():
        _fail("explicitly approved parking evidence produced no safe curb candidates")
        return
    for candidate_variant: Variant in parking_candidates:
        var candidate: Dictionary = candidate_variant
        if str(candidate.get("parking_evidence_source", "")) != "synthetic_test_fixture":
            _fail("parking candidate lost evidence provenance")
            return
        var position: Vector3 = candidate.get("road_point", Vector3.ZERO)
        if position.distance_to(Vector3(0.0, 0.68, 0.0)) < 11.9:
            _fail("parking candidate violated control clearance")
            return

    print("TRAFFIC_MANAGER_FOUNDATION_OK: graph, controls, priority, crossings, density and source-gated parking")
    quit(0)
