extends SceneTree

const PROFILE_SCRIPT := preload("res://game/scripts/traffic_official_density_profile.gd")
const DENSITY_SCRIPT := preload("res://game/scripts/traffic_density_model.gd")
const REAL_SNAPSHOT_PATH := "res://data/traffic/brussels_mobility_snapshot.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("TRAFFIC_OFFICIAL_DENSITY_FAIL: %s" % message)
    quit(1)

func _sensor(sensor_id: String, x: float, z: float, rate: float, occupancy: float, fresh: bool = true, active: bool = true) -> Dictionary:
    return {
        "id": sensor_id,
        "active": active,
        "game": [x, z],
        "measurement": {
            "vehicles_per_minute": rate,
            "occupancy_pct": occupancy,
            "fresh": fresh,
            "source": "counts_api",
        },
    }

func _synthetic_snapshot() -> Dictionary:
    return {
        "format": "grand-bruxelles-brussels-mobility-traffic-v1",
        "captured_at_utc": "2026-08-12T07:10:00Z",
        "source": {
            "name": "Bruxelles Mobilite / Brussels Mobility",
            "license": "CC0-1.0",
            "geometry_crs": "EPSG:31370",
        },
        "stats": {
            "fresh_rate_median_vehicles_per_minute": 15.0,
            "fresh_occupancy_median_pct": 10.0,
        },
        "sensors": [
            _sensor("HIGH", 0.0, 0.0, 30.0, 20.0),
            _sensor("LOW", 1000.0, 0.0, 3.0, 2.0),
            _sensor("STALE", 2000.0, 0.0, 80.0, 80.0, false),
            _sensor("INACTIVE_FRESH", 15.0, 0.0, 90.0, 70.0, true, false),
        ],
    }

func _roads_near_origin() -> Array[Dictionary]:
    return [{
        "points": [[-60.0, 0.0], [60.0, 0.0]],
        "class": "residential",
        "lanes": 2,
        "drivable": true,
    }]

func _run() -> void:
    var snapshot := _synthetic_snapshot()
    var profile: RefCounted = PROFILE_SCRIPT.new()
    if not bool(profile.call("configure", snapshot)):
        _fail("synthetic official profile was rejected")
        return
    if int(profile.call("get_sensor_count")) != 2:
        _fail("stale or officially inactive sensor was not excluded from the calibration profile")
        return
    if str(profile.call("get_source_license")) != "CC0-1.0":
        _fail("official source license provenance was lost")
        return

    var high: Dictionary = profile.call("calibration_for", Vector3.ZERO, 220.0, 4)
    var low: Dictionary = profile.call("calibration_for", Vector3(1000.0, 0.0, 0.0), 220.0, 4)
    var edge: Dictionary = profile.call("calibration_for", Vector3(190.0, 0.0, 0.0), 220.0, 1)
    var uncovered: Dictionary = profile.call("calibration_for", Vector3(5000.0, 0.0, 0.0), 220.0, 4)
    if not bool(high.get("available", false)) or float(high.get("factor", 0.0)) < 1.30:
        _fail("high-flow sensor did not raise the relative spatial factor")
        return
    if not bool(low.get("available", false)) or float(low.get("factor", 1.0)) > 0.75:
        _fail("low-flow sensor did not lower the relative spatial factor")
        return
    if not bool(edge.get("available", false)):
        _fail("near-edge sensor was unexpectedly excluded")
        return
    var edge_confidence := float(edge.get("distance_confidence", 0.0))
    if edge_confidence < 0.30 or edge_confidence > 0.40:
        _fail("distance-confidence taper drifted near coverage edge: %.3f" % edge_confidence)
        return
    if bool(uncovered.get("available", true)) or float(uncovered.get("factor", 0.0)) != 1.0:
        _fail("uncovered area did not return a neutral official factor")
        return

    var nearest: Dictionary = profile.call("nearest_sample", Vector3(5000.0, 0.0, 0.0))
    if not bool(nearest.get("available", false)) or str(nearest.get("id", "")).is_empty():
        _fail("nearest-sensor diagnostic disappeared outside coverage")
        return

    var density: RefCounted = DENSITY_SCRIPT.new()
    var roads := _roads_near_origin()
    var heuristic_high := float(density.call("local_capacity_factor", roads, Vector3.ZERO))
    if not bool(density.call("configure_official_snapshot", snapshot, 220.0, 0.72)):
        _fail("density model rejected a valid official snapshot")
        return
    var calibrated_high := float(density.call("spatial_factor", roads, Vector3.ZERO))
    var calibrated_low := float(density.call("spatial_factor", roads, Vector3(1000.0, 0.0, 0.0)))
    var fallback_position := Vector3(5000.0, 0.0, 0.0)
    var fallback_heuristic := float(density.call("local_capacity_factor", roads, fallback_position))
    var fallback_calibrated := float(density.call("spatial_factor", roads, fallback_position))
    if calibrated_high <= heuristic_high:
        _fail("official high-flow evidence did not influence the blended spatial factor")
        return
    if calibrated_low >= float(density.call("local_capacity_factor", roads, Vector3(1000.0, 0.0, 0.0))):
        _fail("official low-flow evidence did not influence the blended spatial factor")
        return
    if absf(fallback_calibrated - fallback_heuristic) > 0.0001:
        _fail("heuristic fallback changed outside official sensor coverage")
        return

    var neutral_base := 12
    var high_target := int(density.call("target_vehicle_count", neutral_base, 16.0, roads, Vector3.ZERO))
    var low_target := int(density.call("target_vehicle_count", neutral_base, 16.0, roads, Vector3(1000.0, 0.0)))
    var bounded_peak := int(round(float(neutral_base) * 1.42))
    if high_target <= neutral_base:
        _fail("official high-flow evidence is still capped at neutral fleet size")
        return
    if high_target > bounded_peak:
        _fail("official high-flow target exceeded bounded 1.42 spatial ceiling: %d" % high_target)
        return
    if low_target >= neutral_base:
        _fail("official low-flow evidence did not stay below neutral fleet size")
        return

    if not FileAccess.file_exists(REAL_SNAPSHOT_PATH):
        _fail("committed Brussels Mobility snapshot is missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REAL_SNAPSHOT_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("committed Brussels Mobility snapshot is invalid JSON")
        return
    var real_profile: RefCounted = PROFILE_SCRIPT.new()
    if not bool(real_profile.call("configure", parsed as Dictionary)):
        _fail("committed Brussels Mobility snapshot was rejected by runtime profile")
        return
    if int(real_profile.call("get_sensor_count")) < 5:
        _fail("committed snapshot exposes fewer than five active fresh calibration sensors")
        return

    print(
        "TRAFFIC_OFFICIAL_DENSITY_OK: high %.3f low %.3f edge confidence %.3f, targets %d/%d, real active fresh sensors %d" %
        [
            float(high.get("factor", 1.0)),
            float(low.get("factor", 1.0)),
            edge_confidence,
            high_target,
            low_target,
            int(real_profile.call("get_sensor_count")),
        ]
    )
    quit(0)
