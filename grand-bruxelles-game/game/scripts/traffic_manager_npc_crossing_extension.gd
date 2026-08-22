extends "res://game/scripts/traffic_manager_rgsdev_vehicle_extension.gd"
class_name TrafficManagerNpcCrossingExtension

const AMBULANCE_VEHICLE_SCRIPT := preload("res://game/scripts/ambulance_vehicle.gd")
const AMBULANCE_VISUAL_SCRIPT := preload("res://game/scripts/rgsdev_vehicle_visual.gd")
const DEDICATED_AMBULANCE_BODY_SIZE := Vector3(2.08, 2.12, 5.28)
const AMBULANCE_PARKING_EVIDENCE_FORMAT := "grand-bruxelles-midi-ambulance-parking-evidence-v1"
const POSITIVE_PARKING_VALUES := ["yes", "lane", "street_side", "on_kerb", "half_on_kerb", "shoulder", "separate"]

@export var pedestrian_gap_reaction_s: float = 0.8
@export var pedestrian_gap_min_clearance_m: float = 3.2
@export var pedestrian_gap_max_lookahead_m: float = 22.0
@export var pedestrian_gap_extra_buffer_m: float = 1.5
@export var pedestrian_gap_min_closing_speed_mps: float = 0.35
@export var dedicated_ambulance_count: int = 2
@export_file("*.json") var ambulance_parking_evidence_path: String = "res://data/traffic/midi_ambulance_parking_evidence.json"

var _ambulance_root: Node3D = null
var _dedicated_ambulance_reservations: Array[Dictionary] = []
var _ambulance_parking_evidence_road_count: int = 0

func _load_traffic_data() -> void:
    super._load_traffic_data()
    _apply_ambulance_parking_evidence_registry()

func _apply_ambulance_parking_evidence_registry() -> void:
    _ambulance_parking_evidence_road_count = 0
    if ambulance_parking_evidence_path.strip_edges().is_empty():
        return
    var registry := _read_json_dictionary(ambulance_parking_evidence_path)
    if registry.is_empty():
        return
    if str(registry.get("format", "")) != AMBULANCE_PARKING_EVIDENCE_FORMAT:
        push_warning("Ambulance parking evidence registry rejected: format mismatch")
        return
    if not bool(registry.get("runtime_ready", false)):
        push_warning("Ambulance parking evidence registry is not runtime-ready")
        return
    var raw_candidates: Variant = registry.get("candidates", [])
    if not raw_candidates is Array:
        push_warning("Ambulance parking evidence registry rejected: candidates missing")
        return

    var evidence_by_road: Dictionary = {}
    var duplicate_roads: Dictionary = {}
    for raw_candidate: Variant in raw_candidates:
        if typeof(raw_candidate) != TYPE_DICTIONARY:
            continue
        var candidate: Dictionary = raw_candidate
        if not bool(candidate.get("runtime_approved", false)):
            continue
        var road_osm_id := int(candidate.get("road_osm_id", 0))
        var source_osm_id := int(candidate.get("source_osm_id", 0))
        if road_osm_id <= 0 or source_osm_id != road_osm_id:
            continue
        if str(candidate.get("source_osm_type", "")) != "way":
            continue
        if str(candidate.get("source_license", "")) != "ODbL-1.0":
            continue
        var evidence_id := str(candidate.get("evidence_id", "")).strip_edges()
        if evidence_id.is_empty():
            continue
        var expected_url := "https://www.openstreetmap.org/way/%d" % road_osm_id
        if str(candidate.get("source_url", "")) != expected_url:
            continue
        var source_element_raw: Variant = candidate.get("source_element", {})
        if typeof(source_element_raw) != TYPE_DICTIONARY:
            continue
        var source_element: Dictionary = source_element_raw
        if str(source_element.get("type", "")) != "way" or int(source_element.get("id", 0)) != road_osm_id:
            continue
        if int(source_element.get("version", 0)) <= 0 or str(source_element.get("timestamp", "")).strip_edges().is_empty():
            continue
        var source_digest := str(candidate.get("source_element_sha256", "")).strip_edges()
        if source_digest.length() != 64:
            continue
        var evidence_tags_raw: Variant = candidate.get("evidence_tags", {})
        if typeof(evidence_tags_raw) != TYPE_DICTIONARY:
            continue
        var evidence_tags: Dictionary = evidence_tags_raw
        var positive_semantics := false
        for raw_key: Variant in evidence_tags.keys():
            var key := str(raw_key)
            var value := str(evidence_tags[raw_key]).to_lower()
            if key in ["parking:right", "parking:both"] and value in POSITIVE_PARKING_VALUES:
                if str((source_element.get("tags", {}) as Dictionary).get(key, "")).to_lower() == value:
                    positive_semantics = true
                    break
        if not positive_semantics:
            continue
        if evidence_by_road.has(road_osm_id):
            duplicate_roads[road_osm_id] = true
            continue
        evidence_by_road[road_osm_id] = {
            "runtime_approved": true,
            "source": "midi_ambulance_parking_evidence:%s" % evidence_id,
            "source_osm_id": road_osm_id,
            "source_element_sha256": source_digest,
        }

    for raw_duplicate: Variant in duplicate_roads.keys():
        evidence_by_road.erase(raw_duplicate)
    if evidence_by_road.is_empty():
        return

    for index: int in range(_roads.size()):
        var road := _roads[index].duplicate(true)
        var road_osm_id := int(road.get("osm_id", 0))
        if not evidence_by_road.has(road_osm_id):
            continue
        road["parking_evidence"] = (evidence_by_road[road_osm_id] as Dictionary).duplicate(true)
        _roads[index] = road
        _ambulance_parking_evidence_road_count += 1

func _ready() -> void:
    super._ready()
    call_deferred("_spawn_dedicated_ambulances")

func _replenish_parked_vehicles() -> void:
    _reserve_dedicated_ambulance_parking()
    super._replenish_parked_vehicles()

func _reserve_dedicated_ambulance_parking() -> void:
    if dedicated_ambulance_count <= 0:
        return
    if _dedicated_ambulance_reservations.size() >= dedicated_ambulance_count:
        return

    var candidates := _dedicated_ambulance_parking_candidates()
    for candidate: Dictionary in candidates:
        if _dedicated_ambulance_reservations.size() >= dedicated_ambulance_count:
            break
        var candidate_id := int(candidate.get("id", -1))
        if candidate_id < 0 or _has_dedicated_ambulance_reservation(candidate_id):
            continue
        if not is_parking_candidate_available(candidate_id):
            continue
        var position: Vector3 = candidate.get("position", Vector3.ZERO)
        if not _spawn_position_is_clear(position):
            continue
        var reservation_owner := "dedicated_ambulance_%02d" % [_dedicated_ambulance_reservations.size() + 1]
        if not reserve_parking_candidate(candidate_id, reservation_owner):
            continue
        var reservation := candidate.duplicate(true)
        reservation["reservation_owner"] = reservation_owner
        _dedicated_ambulance_reservations.append(reservation)

func _has_dedicated_ambulance_reservation(candidate_id: int) -> bool:
    for reservation: Dictionary in _dedicated_ambulance_reservations:
        if int(reservation.get("id", -1)) == candidate_id:
            return true
    return false

func _spawn_dedicated_ambulances() -> void:
    if dedicated_ambulance_count <= 0:
        return
    if _ambulance_root == null or not is_instance_valid(_ambulance_root):
        _ambulance_root = get_node_or_null("Ambulances") as Node3D
        if _ambulance_root == null:
            _ambulance_root = Node3D.new()
            _ambulance_root.name = "Ambulances"
            add_child(_ambulance_root)
    if _ambulance_root.get_child_count() > 0:
        return

    _reserve_dedicated_ambulance_parking()
    var spawned := 0
    for reservation: Dictionary in _dedicated_ambulance_reservations:
        if spawned >= dedicated_ambulance_count:
            break
        var candidate_id := int(reservation.get("id", -1))
        var reservation_owner := str(reservation.get("reservation_owner", ""))
        if candidate_id < 0 or reservation_owner.is_empty():
            continue
        if not reserve_parking_candidate(candidate_id, reservation_owner):
            continue
        if not _spawn_dedicated_ambulance_at(reservation, reservation_owner, spawned):
            release_parking_candidate(candidate_id, reservation_owner)
            continue
        spawned += 1

    if spawned < dedicated_ambulance_count:
        push_warning("Dedicated ambulances source-backed parking exhausted: spawned=%d requested=%d" % [spawned, dedicated_ambulance_count])

func _dedicated_ambulance_parking_candidates() -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    if _parking_model == null or _parking_candidates.is_empty():
        return result
    var anchor := _anchor_position()
    var nearby: Array = _parking_model.call("candidates_near", _parking_candidates, anchor, parking_spawn_radius_m)
    if nearby.is_empty():
        nearby = _parking_model.call("candidates_near", _parking_candidates, anchor, 100000.0)
    for raw_candidate: Variant in nearby:
        if typeof(raw_candidate) != TYPE_DICTIONARY:
            continue
        var candidate: Dictionary = raw_candidate
        if int(candidate.get("osm_id", 0)) <= 0:
            continue
        if not bool(candidate.get("parking_evidence_runtime_approved", false)):
            continue
        if str(candidate.get("parking_evidence_source", "")).strip_edges().is_empty():
            continue
        result.append(candidate)
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var a_position: Vector3 = a.get("position", Vector3.ZERO)
        var b_position: Vector3 = b.get("position", Vector3.ZERO)
        var a_distance := a_position.distance_squared_to(anchor)
        var b_distance := b_position.distance_squared_to(anchor)
        if absf(a_distance - b_distance) > 0.0001:
            return a_distance < b_distance
        return int(a.get("id", -1)) < int(b.get("id", -1))
    )
    return result

func _spawn_dedicated_ambulance_at(candidate: Dictionary, reservation_owner: String, spawn_index: int) -> bool:
    var candidate_id := int(candidate.get("id", -1))
    var source_osm_id := int(candidate.get("osm_id", 0))
    if candidate_id < 0 or source_osm_id <= 0 or reservation_owner.is_empty():
        return false
    var ambulance := AMBULANCE_VEHICLE_SCRIPT.new() as AmbulanceVehicle
    if ambulance == null:
        return false
    ambulance.name = "Ambulance_%02d" % [spawn_index + 1]
    ambulance.collision_layer = 1
    ambulance.collision_mask = 1
    ambulance.add_to_group("vehicle")
    ambulance.add_to_group("ambulance")
    ambulance.add_to_group("emergency_vehicle")

    var collision := CollisionShape3D.new()
    collision.name = "CollisionShape3D"
    var box := BoxShape3D.new()
    box.size = DEDICATED_AMBULANCE_BODY_SIZE
    collision.shape = box
    ambulance.add_child(collision)

    var visual := AMBULANCE_VISUAL_SCRIPT.new()
    visual.name = "RgsdevVisual"
    visual.call("configure_model", "ambulance")
    ambulance.add_child(visual)

    ambulance.configure_archetype("car")
    ambulance.set_meta("dedicated_special_vehicle", true)
    ambulance.set_meta("special_vehicle_kind", "ambulance")
    ambulance.set_meta("parking_candidate_id", candidate_id)
    ambulance.set_meta("reservation_owner", reservation_owner)
    ambulance.set_meta("simulated_occupancy", true)
    ambulance.set_meta("road_name", str(candidate.get("road_name", "")))
    ambulance.set_meta("source_osm_id", source_osm_id)
    ambulance.set_meta("parking_evidence_source", str(candidate.get("parking_evidence_source", "")))
    ambulance.set_meta("parking_evidence_runtime_approved", bool(candidate.get("parking_evidence_runtime_approved", false)))
    _ambulance_root.add_child(ambulance)
    ambulance.global_position = candidate.get("position", Vector3.ZERO)
    ambulance.rotation.y = float(candidate.get("yaw", 0.0))
    ambulance.call("configure_as_parked")
    return true

func get_ambulance_count() -> int:
    if _ambulance_root == null:
        return 0
    var count := 0
    for child: Node in _ambulance_root.get_children():
        if not child.is_queued_for_deletion():
            count += 1
    return count

func get_ambulance_parking_evidence_road_count() -> int:
    return _ambulance_parking_evidence_road_count

func get_npc_crossing_system() -> RefCounted:
    return _crossing_system

func is_crossing_gap_safe(crossing_id: int, pedestrian_position: Vector3 = Vector3.ZERO) -> bool:
    if _crossing_system == null or _traffic_root == null:
        return false
    var crossing: Dictionary = _crossing_system.call("get_crossing", crossing_id)
    if crossing.is_empty():
        return false
    var crossing_position: Vector3 = crossing.get("position", pedestrian_position)
    var minimum_clearance := maxf(1.0, pedestrian_gap_min_clearance_m)
    var maximum_lookahead := maxf(minimum_clearance, pedestrian_gap_max_lookahead_m)

    for child: Node in _traffic_root.get_children():
        if child.is_queued_for_deletion() or not child is Node3D:
            continue
        var vehicle := child as Node3D
        var offset := crossing_position - vehicle.global_position
        offset.y = 0.0
        var distance := offset.length()
        if distance <= minimum_clearance:
            return false
        if distance > maximum_lookahead:
            continue
        if bool(child.get_meta("traffic_wrecked", false)):
            continue

        var planar_velocity := Vector3.ZERO
        if child is CharacterBody3D:
            planar_velocity = (child as CharacterBody3D).velocity
            planar_velocity.y = 0.0
        var speed := planar_velocity.length()
        if speed < maxf(0.05, pedestrian_gap_min_closing_speed_mps):
            continue
        var closing_speed := planar_velocity.dot(offset.normalized())
        if closing_speed < pedestrian_gap_min_closing_speed_mps:
            continue

        var braking_mps2 := 7.5
        if child is TrafficVehicleCore:
            braking_mps2 = maxf(1.0, (child as TrafficVehicleCore).braking_mps2)
        var stopping_distance := (
            closing_speed * maxf(0.0, pedestrian_gap_reaction_s)
            + (closing_speed * closing_speed) / (2.0 * braking_mps2)
            + maxf(0.0, pedestrian_gap_extra_buffer_m)
        )
        if distance <= maxf(minimum_clearance, stopping_distance):
            return false
    return true
