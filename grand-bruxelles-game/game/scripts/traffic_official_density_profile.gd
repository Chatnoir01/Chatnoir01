extends RefCounted
class_name TrafficOfficialDensityProfile

const EXPECTED_FORMAT := "grand-bruxelles-brussels-mobility-traffic-v1"
const DEFAULT_MAX_RADIUS_M := 1800.0
const DEFAULT_NEAREST_LIMIT := 4
const MIN_WEIGHT_DISTANCE_M := 90.0
const MIN_SAMPLE_FACTOR := 0.58
const MAX_SAMPLE_FACTOR := 1.48
const RATE_WEIGHT := 0.82
const OCCUPANCY_WEIGHT := 0.18

var _samples: Array[Dictionary] = []
var _median_rate: float = 0.0
var _median_occupancy: float = 0.0
var _captured_at_utc: String = ""
var _source_name: String = ""
var _source_license: String = ""

func configure(snapshot: Dictionary) -> bool:
    clear()
    if str(snapshot.get("format", "")) != EXPECTED_FORMAT:
        return false
    var source: Dictionary = snapshot.get("source", {})
    if str(source.get("geometry_crs", "")) != "EPSG:31370":
        return false
    var stats: Dictionary = snapshot.get("stats", {})
    _median_rate = maxf(0.0, float(stats.get("fresh_rate_median_vehicles_per_minute", 0.0)))
    _median_occupancy = maxf(0.0, float(stats.get("fresh_occupancy_median_pct", 0.0)))
    _captured_at_utc = str(snapshot.get("captured_at_utc", ""))
    _source_name = str(source.get("name", ""))
    _source_license = str(source.get("license", ""))

    var raw_sensors: Variant = snapshot.get("sensors", [])
    if not raw_sensors is Array:
        clear()
        return false
    for raw_sensor: Variant in raw_sensors:
        if typeof(raw_sensor) != TYPE_DICTIONARY:
            continue
        var sensor: Dictionary = raw_sensor
        var measurement: Dictionary = sensor.get("measurement", {})
        # "fresh" means fresh at capture time. Once committed, the snapshot is a
        # calibration profile, never represented as current live traffic.
        if not bool(measurement.get("fresh", false)):
            continue
        var raw_game: Variant = sensor.get("game", null)
        if not raw_game is Array or raw_game.size() < 2:
            continue
        var rate := _safe_float(measurement.get("vehicles_per_minute", null), -1.0)
        if rate < 0.0:
            continue
        var occupancy := _safe_float(measurement.get("occupancy_pct", null), -1.0)
        _samples.append({
            "id": str(sensor.get("id", "")),
            "position": Vector3(float(raw_game[0]), 0.0, float(raw_game[1])),
            "vehicles_per_minute": rate,
            "occupancy_pct": occupancy,
            "active_at_capture": bool(sensor.get("active", false)),
            "source": str(measurement.get("source", "")),
        })

    if _samples.is_empty():
        clear()
        return false
    if _median_rate <= 0.0:
        _median_rate = _median_of_samples("vehicles_per_minute")
    if _median_occupancy <= 0.0:
        _median_occupancy = _median_of_samples("occupancy_pct", true)
    return _median_rate > 0.0

func clear() -> void:
    _samples.clear()
    _median_rate = 0.0
    _median_occupancy = 0.0
    _captured_at_utc = ""
    _source_name = ""
    _source_license = ""

func is_configured() -> bool:
    return not _samples.is_empty() and _median_rate > 0.0

func get_sensor_count() -> int:
    return _samples.size()

func get_captured_at_utc() -> String:
    return _captured_at_utc

func get_source_name() -> String:
    return _source_name

func get_source_license() -> String:
    return _source_license

func get_median_rate() -> float:
    return _median_rate

func get_median_occupancy() -> float:
    return _median_occupancy

func calibration_for(
    position: Vector3,
    max_radius_m: float = DEFAULT_MAX_RADIUS_M,
    nearest_limit: int = DEFAULT_NEAREST_LIMIT
) -> Dictionary:
    if not is_configured() or max_radius_m <= 0.0 or nearest_limit <= 0:
        return _empty_calibration()
    var candidates: Array[Dictionary] = []
    var radius := maxf(1.0, max_radius_m)
    for sample: Dictionary in _samples:
        var sample_position: Vector3 = sample.get("position", Vector3.ZERO)
        var flat_position := Vector3(position.x, 0.0, position.z)
        var distance := flat_position.distance_to(sample_position)
        if distance <= radius:
            candidates.append({"sample": sample, "distance_m": distance})
    if candidates.is_empty():
        return _empty_calibration()
    candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a.get("distance_m", INF)) < float(b.get("distance_m", INF))
    )

    var used := mini(nearest_limit, candidates.size())
    var weighted_factor := 0.0
    var total_weight := 0.0
    var nearest_distance := INF
    var ids := PackedStringArray()
    for index: int in range(used):
        var candidate: Dictionary = candidates[index]
        var sample: Dictionary = candidate["sample"]
        var distance := float(candidate["distance_m"])
        nearest_distance = minf(nearest_distance, distance)
        var weight := 1.0 / maxf(MIN_WEIGHT_DISTANCE_M, distance)
        var factor := _sample_factor(sample)
        weighted_factor += factor * weight
        total_weight += weight
        ids.append(str(sample.get("id", "")))
    if total_weight <= 0.0:
        return _empty_calibration()
    return {
        "available": true,
        "factor": clampf(weighted_factor / total_weight, MIN_SAMPLE_FACTOR, MAX_SAMPLE_FACTOR),
        "sample_count": used,
        "nearest_distance_m": nearest_distance,
        "sensor_ids": ids,
        "captured_at_utc": _captured_at_utc,
        "source_name": _source_name,
        "source_license": _source_license,
    }

func local_factor(position: Vector3, max_radius_m: float = DEFAULT_MAX_RADIUS_M) -> float:
    var result := calibration_for(position, max_radius_m)
    if not bool(result.get("available", false)):
        return 1.0
    return float(result.get("factor", 1.0))

func _sample_factor(sample: Dictionary) -> float:
    var rate := maxf(0.0, float(sample.get("vehicles_per_minute", 0.0)))
    var rate_ratio := rate / maxf(0.001, _median_rate)
    var occupancy := float(sample.get("occupancy_pct", -1.0))
    var occupancy_ratio := 1.0
    if occupancy >= 0.0 and _median_occupancy > 0.0:
        occupancy_ratio = occupancy / _median_occupancy
    var factor := rate_ratio * RATE_WEIGHT + occupancy_ratio * OCCUPANCY_WEIGHT
    return clampf(factor, MIN_SAMPLE_FACTOR, MAX_SAMPLE_FACTOR)

func _median_of_samples(key: String, ignore_negative: bool = false) -> float:
    var values: Array[float] = []
    for sample: Dictionary in _samples:
        var value := float(sample.get(key, -1.0))
        if ignore_negative and value < 0.0:
            continue
        values.append(value)
    if values.is_empty():
        return 0.0
    values.sort()
    var middle := values.size() / 2
    if values.size() % 2 == 1:
        return values[middle]
    return (values[middle - 1] + values[middle]) * 0.5

func _empty_calibration() -> Dictionary:
    return {
        "available": false,
        "factor": 1.0,
        "sample_count": 0,
        "nearest_distance_m": INF,
        "sensor_ids": PackedStringArray(),
        "captured_at_utc": _captured_at_utc,
        "source_name": _source_name,
        "source_license": _source_license,
    }

func _safe_float(raw: Variant, fallback: float) -> float:
    if raw == null:
        return fallback
    if typeof(raw) in [TYPE_INT, TYPE_FLOAT]:
        return float(raw)
    if typeof(raw) == TYPE_STRING and str(raw).is_valid_float():
        return float(str(raw))
    return fallback
