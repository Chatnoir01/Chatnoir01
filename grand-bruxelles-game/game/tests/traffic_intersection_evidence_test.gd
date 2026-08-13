extends SceneTree

const INTERSECTION_SCRIPT := preload("res://game/scripts/traffic_intersection_system.gd")
const DENSITY_SCRIPT := preload("res://game/scripts/traffic_density_model.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_INTERSECTION_EVIDENCE_FAIL: %s" % message)
    quit(1)

func _roads() -> Array[Dictionary]:
    return [
        {"points": [[-30.0, 0.0], [0.0, 0.0], [30.0, 0.0]]},
        {"points": [[0.0, -30.0], [0.0, 0.0], [0.0, 30.0]]},
    ]

func _route() -> PackedVector3Array:
    return PackedVector3Array([
        Vector3(-30.0, 0.68, 0.0),
        Vector3(0.0, 0.68, 0.0),
        Vector3(30.0, 0.68, 0.0),
    ])

func _mapped_intersection(controls: Array) -> Dictionary:
    var system := INTERSECTION_SCRIPT.new()
    system.rebuild(_roads(), controls)
    var mapped: Array[Dictionary] = system.intersections_for_route(_route())
    if mapped.is_empty():
        return {}
    return mapped[0]

func _run() -> void:
    var unknown := _mapped_intersection([])
    if unknown.is_empty():
        _fail("synthetic four-way intersection was not mapped")
        return
    if bool(unknown.get("priority_to_right", false)):
        _fail("missing control data was treated as proof of priority to right")
        return

    var signalized := _mapped_intersection([
        {"kind": "traffic_signals", "osm_id": 8101, "point": [0.0, 0.0]},
    ])
    if str(signalized.get("control_kind", "")) != "traffic_signals":
        _fail("known traffic signal control was not preserved")
        return
    if bool(signalized.get("priority_to_right", false)):
        _fail("signalized intersection was incorrectly marked priority to right")
        return

    var density: RefCounted = DENSITY_SCRIPT.new()
    var probe_hours: Array[float] = [0.0, 4.5, 6.0, 8.0, 12.0, 17.0, 20.0, 23.5]
    for hour: float in probe_hours:
        var factor := float(density.call("time_factor", hour))
        if absf(factor - 1.0) > 0.0001:
            _fail("unsourced hour %.2f changes traffic volume with factor %.3f" % [hour, factor])
            return

    print("TRAFFIC_INTERSECTION_EVIDENCE_OK: unknown priorities and unsourced temporal traffic volumes remain neutral")
    quit(0)
