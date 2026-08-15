extends Node

## Small player-facing orchestration layer for the already-shipped Living City.
## It does not invent geography or replace NpcAgent logic. Once per visited zone,
## it reuses existing civilians, crowd reactions and police response to make the
## living-city systems perceptible without forcing the player to cause an incident.

const MIDI := Vector3(-668.5, 0.16, 627.84)
const BOURSE := Vector3(114.0, 0.18, -722.0)
const SHOWCASE_RADIUS_M := 150.0

@export var showcase_delay_seconds := 5.5
@export var incident_duration_seconds := 7.0
@export var recovery_duration_seconds := 5.0

var _scene: Node3D = null
var _player: CharacterBody3D = null
var _visible_runtime: Node = null
var _bound := false
var _zone_elapsed_s := 0.0
var _active_zone := ""
var _triggered_zones: Dictionary = {}
var _subject: NpcAgent = null
var _reacting_civilians: Array[NpcAgent] = []
var _responding_police: Array[NpcAgent] = []
var _incident_id := 9400
var _incident_remaining_s := 0.0
var _recovery_remaining_s := 0.0
var _showcase_trigger_count := 0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    call_deferred("_try_bind")

func _process(delta: float) -> void:
    if not _bound:
        _try_bind()
        return
    if not is_instance_valid(_scene) or get_tree().current_scene != _scene:
        _reset_binding()
        return

    var safe_delta := maxf(delta, 0.0)
    if is_instance_valid(_subject):
        _update_active_showcase(safe_delta)
        return

    var zone := _current_zone()
    if zone.is_empty() or bool(_triggered_zones.get(zone, false)):
        _zone_elapsed_s = 0.0
        _active_zone = zone
        return

    var counts: Dictionary = _visible_runtime.call("visible_population_counts") if is_instance_valid(_visible_runtime) else {}
    if bool(counts.get("incident_active", false)):
        _zone_elapsed_s = 0.0
        return
    if not _zone_population_ready(zone, counts):
        _zone_elapsed_s = 0.0
        return

    if zone != _active_zone:
        _active_zone = zone
        _zone_elapsed_s = 0.0
    _zone_elapsed_s += safe_delta
    if _zone_elapsed_s >= showcase_delay_seconds:
        _trigger_showcase(zone)

func _try_bind() -> void:
    var current := get_tree().current_scene
    if current == null or not current is Node3D:
        return
    var player_node := current.get_node_or_null("Player")
    var runtime := get_tree().root.get_node_or_null("VisibleCityRuntime")
    if not player_node is CharacterBody3D or runtime == null:
        return
    _scene = current as Node3D
    _player = player_node as CharacterBody3D
    _visible_runtime = runtime
    _bound = true
    print("LIVING_CITY_SHOWCASE_READY")

func _reset_binding() -> void:
    _bound = false
    _scene = null
    _player = null
    _visible_runtime = null
    _zone_elapsed_s = 0.0
    _active_zone = ""
    _subject = null
    _reacting_civilians.clear()
    _responding_police.clear()
    _incident_remaining_s = 0.0
    _recovery_remaining_s = 0.0

func _current_zone() -> String:
    if not is_instance_valid(_player):
        return ""
    var observer := _active_player_position()
    if observer.distance_to(MIDI) <= SHOWCASE_RADIUS_M:
        return "midi"
    if observer.distance_to(BOURSE) <= SHOWCASE_RADIUS_M:
        return "bourse"
    return ""

func _zone_population_ready(zone: String, counts: Dictionary) -> bool:
    if int(counts.get("civilians", 0)) < 3 or int(counts.get("police", 0)) < 1:
        return false
    if zone == "midi":
        return bool(counts.get("midi_spawned", false))
    if zone == "bourse":
        return bool(counts.get("bourse_spawned", false))
    return false

func _trigger_showcase(zone: String) -> bool:
    if not _bound:
        _try_bind()
    if not _bound or is_instance_valid(_subject):
        return false

    var subject := _closest_civilian_to_player()
    if not is_instance_valid(subject):
        return false
    var police := _active_police_near(subject.get_world_position(), 90.0)
    if police.is_empty():
        return false

    _incident_id += 1
    _showcase_trigger_count += 1
    _triggered_zones[zone] = true
    _active_zone = zone
    _zone_elapsed_s = 0.0
    _subject = subject
    _responding_police = police
    _reacting_civilians.clear()
    _incident_remaining_s = incident_duration_seconds
    _recovery_remaining_s = recovery_duration_seconds

    var incident_position := subject.get_world_position()
    var stimulus_position := incident_position + _showcase_stimulus_offset(zone)
    subject.react_to_event(82.0, stimulus_position)
    subject.set_meta("living_city_showcase_subject", true)

    for node: Node in get_tree().get_nodes_in_group("behavioral_civilian"):
        if not node is NpcAgent or node == subject:
            continue
        var civilian := node as NpcAgent
        if not civilian.active:
            continue
        var distance := civilian.get_world_position().distance_to(incident_position)
        if distance <= 24.0:
            civilian.apply_local_crowd_stimulus(incident_position, 0.66, false)
            _reacting_civilians.append(civilian)

    for officer: NpcAgent in _responding_police:
        officer.report_police_incident(incident_position, 0.86, _incident_id)

    if is_instance_valid(_visible_runtime):
        _visible_runtime.call("_set_status", "INCIDENT DE RUE · patrouille en intervention")
    print("LIVING_CITY_SHOWCASE_TRIGGERED: zone=%s subject=%s bystanders=%d police=%d" % [zone, subject.name, _reacting_civilians.size(), _responding_police.size()])
    return true

func _update_active_showcase(delta: float) -> void:
    if not is_instance_valid(_subject):
        _finish_showcase()
        return

    if _incident_remaining_s > 0.0:
        _incident_remaining_s = maxf(0.0, _incident_remaining_s - delta)
        var target_position := _subject.get_world_position()
        for officer: NpcAgent in _responding_police:
            if is_instance_valid(officer) and officer.active:
                officer.report_police_incident(target_position, 0.86, _incident_id)
        if _incident_remaining_s <= 0.0:
            _begin_recovery()
        return

    _recovery_remaining_s = maxf(0.0, _recovery_remaining_s - delta)
    for officer: NpcAgent in _responding_police:
        if is_instance_valid(officer) and officer.active:
            officer.update_police_threat(false, 0.0, delta)
    if _recovery_remaining_s <= 0.0:
        _finish_showcase()

func _begin_recovery() -> void:
    _restore_civilian(_subject)
    for civilian: NpcAgent in _reacting_civilians:
        _restore_civilian(civilian)
    if is_instance_valid(_visible_runtime):
        _visible_runtime.call("_set_status", "PATROUILLE · situation sous contrôle")

func _finish_showcase() -> void:
    if is_instance_valid(_subject):
        _subject.remove_meta("living_city_showcase_subject")
    _subject = null
    _reacting_civilians.clear()
    _responding_police.clear()
    _incident_remaining_s = 0.0
    _recovery_remaining_s = 0.0
    if is_instance_valid(_visible_runtime):
        _visible_runtime.call("_set_status", "")
    print("LIVING_CITY_SHOWCASE_RESOLVED: zone=%s" % _active_zone)

func _restore_civilian(civilian: NpcAgent) -> void:
    if not is_instance_valid(civilian) or not civilian.active:
        return
    civilian.behavior.calm_down(100.0)
    civilian.set_destination(civilian.civilian_routine_target)

func _closest_civilian_to_player() -> NpcAgent:
    if not is_instance_valid(_player):
        return null
    var observer := _active_player_position()
    var best: NpcAgent = null
    var best_distance := INF
    for node: Node in get_tree().get_nodes_in_group("behavioral_civilian"):
        if not node is NpcAgent:
            continue
        var civilian := node as NpcAgent
        if not civilian.active or civilian.transit_state != NpcAgent.TransitState.NONE:
            continue
        var distance := civilian.get_world_position().distance_to(observer)
        if distance < best_distance and distance <= 55.0:
            best = civilian
            best_distance = distance
    return best

func _active_police_near(position: Vector3, radius_m: float) -> Array[NpcAgent]:
    var result: Array[NpcAgent] = []
    for node: Node in get_tree().get_nodes_in_group("police_officer"):
        if not node is NpcAgent:
            continue
        var officer := node as NpcAgent
        if officer.active and officer.get_world_position().distance_to(position) <= radius_m:
            result.append(officer)
    return result

func _showcase_stimulus_offset(zone: String) -> Vector3:
    if zone == "midi":
        return Vector3(2.5, 0.0, -3.0)
    return Vector3(-2.8, 0.0, 2.2)

func _active_player_position() -> Vector3:
    for candidate: Node in get_tree().get_nodes_in_group("vehicle"):
        if candidate is Node3D and candidate.has_method("has_driver") and bool(candidate.call("has_driver")):
            return (candidate as Node3D).global_position
    return _player.global_position if is_instance_valid(_player) else Vector3.ZERO

func trigger_showcase_for_test(zone: String = "midi") -> bool:
    if not _bound:
        _try_bind()
    if not _bound:
        return false
    if is_instance_valid(_visible_runtime):
        _visible_runtime.call("ensure_zone_for_test", zone)
    return _trigger_showcase(zone)

func showcase_state_for_test() -> Dictionary:
    var responders := 0
    for officer: NpcAgent in _responding_police:
        if is_instance_valid(officer) and officer.active and officer.police_response.phase != NpcPoliceResponse.Phase.PATROL:
            responders += 1
    var reacting := 0
    for civilian: NpcAgent in _reacting_civilians:
        if is_instance_valid(civilian) and civilian.active and civilian.behavior.alert_level > 5.0:
            reacting += 1
    return {
        "bound": _bound,
        "trigger_count": _showcase_trigger_count,
        "zone": _active_zone,
        "subject_valid": is_instance_valid(_subject),
        "subject_is_player": false,
        "subject_state": _subject.behavior.state if is_instance_valid(_subject) else -1,
        "reacting_civilians": reacting,
        "responding_police": responders,
        "incident_remaining_s": _incident_remaining_s,
    }
