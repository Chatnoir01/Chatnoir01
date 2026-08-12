extends RefCounted

const MIN_SEGMENT_LENGTH_M := 18.0
const END_CLEARANCE_M := 8.0
const CONTROL_CLEARANCE_M := 12.0
const DEFAULT_ROAD_WIDTH_M := 5.6
const CURB_MARGIN_M := 1.25
const CANDIDATE_SPACING_M := 26.0

const PARKING_CLASSES := {
    "residential": true,
    "tertiary": true,
    "secondary": true,
    "unclassified": true,
    "service": true,
    "living_street": true,
}

func build_candidates(roads: Array[Dictionary], controls: Array) -> Array[Dictionary]:
    var candidates: Array[Dictionary] = []
    var control_positions := _control_positions(controls)
    var serial := 0
    for road: Dictionary in roads:
        var evidence := _approved_parking_evidence(road)
        if evidence.is_empty():
            continue
        var road_class := str(road.get("class", ""))
        if not PARKING_CLASSES.has(road_class):
            continue
        var points: Array = road.get("points", [])
        if points.size() < 2:
            continue
        var width := maxf(3.0, _safe_float(road.get("width", null), DEFAULT_ROAD_WIDTH_M))
        for index: int in range(points.size() - 1):
            var start := _point(points[index])
            var finish := _point(points[index + 1])
            var segment := finish - start
            segment.y = 0.0
            var length := segment.length()
            if length < MIN_SEGMENT_LENGTH_M:
                continue
            var direction := segment / length
            var right := Vector3(-direction.z, 0.0, direction.x)
            var usable := maxf(0.0, length - END_CLEARANCE_M * 2.0)
            var slot_count := maxi(1, int(floor(usable / CANDIDATE_SPACING_M)) + 1)
            for slot: int in range(slot_count):
                var along := END_CLEARANCE_M
                if slot_count > 1:
                    along += usable * float(slot) / float(slot_count - 1)
                else:
                    along += usable * 0.5
                var road_point := start + direction * along
                if _near_any_control(road_point, control_positions):
                    continue
                var parking_position := road_point + right * (width * 0.5 + CURB_MARGIN_M)
                candidates.append({
                    "id": serial,
                    "position": parking_position,
                    "yaw": atan2(-direction.x, -direction.z),
                    "road_point": road_point,
                    "road_class": road_class,
                    "road_name": str(road.get("name", "")),
                    "osm_id": int(road.get("osm_id", 0)),
                    "simulated_occupancy": true,
                    "parking_evidence_source": str(evidence.get("source", "")),
                    "parking_evidence_runtime_approved": true,
                })
                serial += 1
    return candidates

func candidates_near(candidates: Array[Dictionary], position: Vector3, radius_m: float) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var radius := maxf(0.0, radius_m)
    for candidate: Dictionary in candidates:
        var candidate_position: Vector3 = candidate.get("position", Vector3.ZERO)
        if candidate_position.distance_to(position) <= radius:
            result.append(candidate)
    return result

func _approved_parking_evidence(road: Dictionary) -> Dictionary:
    var raw_evidence: Variant = road.get("parking_evidence", null)
    if typeof(raw_evidence) != TYPE_DICTIONARY:
        return {}
    var evidence: Dictionary = raw_evidence
    if not bool(evidence.get("runtime_approved", false)):
        return {}
    if str(evidence.get("source", "")).strip_edges().is_empty():
        return {}
    return evidence

func _control_positions(controls: Array) -> Array[Vector3]:
    var result: Array[Vector3] = []
    for raw_control: Variant in controls:
        if typeof(raw_control) != TYPE_DICTIONARY:
            continue
        var control: Dictionary = raw_control
        var kind := str(control.get("kind", ""))
        if kind not in ["traffic_signals", "stop", "give_way", "crossing"]:
            continue
        var raw_point: Variant = control.get("point", null)
        if raw_point is Array and raw_point.size() >= 2:
            result.append(Vector3(float(raw_point[0]), 0.68, float(raw_point[1])))
    return result

func _near_any_control(position: Vector3, control_positions: Array[Vector3]) -> bool:
    for control_position: Vector3 in control_positions:
        if position.distance_to(control_position) < CONTROL_CLEARANCE_M:
            return true
    return false

func _point(raw: Variant) -> Vector3:
    return Vector3(float(raw[0]), 0.68, float(raw[1]))

func _safe_float(raw: Variant, fallback: float) -> float:
    if raw == null:
        return fallback
    if typeof(raw) in [TYPE_INT, TYPE_FLOAT]:
        return float(raw)
    if typeof(raw) == TYPE_STRING and str(raw).is_valid_float():
        return float(str(raw))
    return fallback
