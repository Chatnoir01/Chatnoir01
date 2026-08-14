extends Node

## Player-facing bridge for systems that already exist in code but were previously
## hard to perceive in the shipped scene. This runtime mounts a small, bounded
## set of real NpcAgent actors onto source-anchored production geography.
##
## Geography discipline:
## - Midi agents reuse the existing Fonsny axis + sidewalk offsets already used by
##   midi_urban_life.gd. No new street geometry is authored here.
## - Bourse agents derive every spawn/destination from centroids of the already
##   integrated official Brussels Mobility / Paradigm sidewalk polygons.
##
## The runtime intentionally does not replace the lightweight ambient crowd. It
## adds a smaller behavioral layer that can flee, avoid, patrol, investigate and
## pursue, so existing NPC systems become visible to the player.

const HUMANOID_VISUAL_SCRIPT := preload("res://game/scripts/humanoid_visual.gd")
const BOURSE_SIDEWALKS_PATH := "res://data/urbis/bourse_official_sidewalks.game.json"

const MIDI := Vector3(-668.5, 0.16, 627.84)
const FONSNY_AXIS := Vector3(-0.627, 0.0, 0.779)
const ROAD_SIDE := Vector3(0.779, 0.0, 0.627)
const MIDI_SIDEWALK_A := -12.6
const MIDI_SIDEWALK_B := 8.8
const BOURSE_CENTER := Vector3(114.0, 0.18, -722.0)

@export var midi_civilian_count: int = 8
@export var midi_police_count: int = 2
@export var bourse_civilian_count: int = 6
@export var bourse_police_count: int = 2
@export var zone_activation_radius_m: float = 155.0
@export var dangerous_vehicle_speed_mps: float = 8.5
@export var dangerous_near_miss_radius_m: float = 4.2
@export var incident_crowd_radius_m: float = 28.0
@export var active_threat_hold_seconds: float = 8.0

var _scene: Node3D = null
var _player: CharacterBody3D = null
var _director: NpcPopulationDirector = null
var _bound := false
var _midi_spawned := false
var _bourse_spawned := false
var _bourse_points: Array[Vector3] = []

var _civilians: Array[NpcAgent] = []
var _police: Array[NpcAgent] = []
var _routes: Dictionary = {}
var _route_indices: Dictionary = {}

var _danger_elapsed_s := 0.0
var _incident_cooldown_s := 0.0
var _incident_id := -1
var _incident_serial := 0
var _threat_hold_s := 0.0
var _detention_hold_s := 0.0
var _last_incident_position := Vector3.ZERO

var _hud_layer: CanvasLayer = null
var _hud_panel: Panel = null
var _hud_label: Label = null
var _status_text := ""

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

    var safe_delta := maxf(0.0, delta)
    _incident_cooldown_s = maxf(0.0, _incident_cooldown_s - safe_delta)
    _threat_hold_s = maxf(0.0, _threat_hold_s - safe_delta)

    _ensure_nearby_zone()
    _update_routes()
    _update_dangerous_driving(safe_delta)
    _update_police_response(safe_delta)
    _update_status_hud()

func _try_bind() -> void:
    var current := get_tree().current_scene
    if current == null or not current is Node3D:
        return
    var player_node := current.get_node_or_null("Player")
    var director_node := current.get_node_or_null("NpcPopulationDirector")
    if not player_node is CharacterBody3D or not director_node is NpcPopulationDirector:
        return
    _scene = current as Node3D
    _player = player_node as CharacterBody3D
    _director = director_node as NpcPopulationDirector
    _bourse_points = _load_bourse_sidewalk_centroids()
    _build_hud()
    _bound = true
    _ensure_nearby_zone()
    print("VISIBLE_CITY_RUNTIME_READY")

func _reset_binding() -> void:
    _bound = false
    _scene = null
    _player = null
    _director = null
    _midi_spawned = false
    _bourse_spawned = false
    _civilians.clear()
    _police.clear()
    _routes.clear()
    _route_indices.clear()
    _incident_id = -1
    _threat_hold_s = 0.0
    if is_instance_valid(_hud_layer):
        _hud_layer.queue_free()
    _hud_layer = null
    _hud_panel = null
    _hud_label = null

func _ensure_nearby_zone() -> void:
    if not is_instance_valid(_player):
        return
    var observer_position := _active_player_position()
    if not _midi_spawned and observer_position.distance_to(MIDI) <= zone_activation_radius_m:
        _spawn_midi_zone()
    if not _bourse_spawned and not _bourse_points.is_empty() and observer_position.distance_to(BOURSE_CENTER) <= zone_activation_radius_m:
        _spawn_bourse_zone()

func ensure_zone_for_test(zone_name: String) -> void:
    if not _bound:
        _try_bind()
    match zone_name:
        "midi":
            if not _midi_spawned:
                _spawn_midi_zone()
        "bourse":
            if not _bourse_spawned:
                _spawn_bourse_zone()

func _spawn_midi_zone() -> void:
    if _midi_spawned or not is_instance_valid(_scene):
        return
    _midi_spawned = true

    for index in range(maxi(midi_civilian_count, 0)):
        var side := MIDI_SIDEWALK_A if index % 2 == 0 else MIDI_SIDEWALK_B
        var lane_a := MIDI + FONSNY_AXIS * (-84.0 + float(index % 4) * 8.0) + ROAD_SIDE * side
        var lane_b := MIDI + FONSNY_AXIS * (84.0 - float(index % 4) * 8.0) + ROAD_SIDE * side
        lane_a.y = MIDI.y
        lane_b.y = MIDI.y
        var start := lane_a.lerp(lane_b, float(index + 1) / float(maxi(midi_civilian_count + 1, 2)))
        _spawn_behavior_agent(
            NpcBehaviorModel.Role.CIVILIAN,
            3100 + index,
            start,
            [lane_a, lane_b],
            "midi_fonsny_existing_sidewalk_alignment"
        )

    for index in range(maxi(midi_police_count, 0)):
        var side := MIDI_SIDEWALK_B
        var patrol_a := MIDI + FONSNY_AXIS * (-56.0 + float(index) * 18.0) + ROAD_SIDE * side
        var patrol_b := MIDI + FONSNY_AXIS * (48.0 - float(index) * 14.0) + ROAD_SIDE * side
        patrol_a.y = MIDI.y
        patrol_b.y = MIDI.y
        _spawn_behavior_agent(
            NpcBehaviorModel.Role.POLICE,
            7100 + index,
            patrol_a,
            [patrol_a, patrol_b],
            "midi_fonsny_existing_sidewalk_alignment"
        )

func _spawn_bourse_zone() -> void:
    if _bourse_spawned or not is_instance_valid(_scene) or _bourse_points.size() < 2:
        return
    _bourse_spawned = true
    var point_count := _bourse_points.size()

    for index in range(maxi(bourse_civilian_count, 0)):
        var a := _bourse_points[index % point_count]
        var b := _bourse_points[(index + 1) % point_count]
        var start := a.lerp(b, 0.25 + 0.12 * float(index % 4))
        _spawn_behavior_agent(
            NpcBehaviorModel.Role.CIVILIAN,
            4100 + index,
            start,
            [a, b],
            "official_bourse_sidewalk_centroids"
        )

    for index in range(maxi(bourse_police_count, 0)):
        var a := _bourse_points[(index * 2) % point_count]
        var b := _bourse_points[(index * 2 + 2) % point_count]
        _spawn_behavior_agent(
            NpcBehaviorModel.Role.POLICE,
            8100 + index,
            a,
            [a, b],
            "official_bourse_sidewalk_centroids"
        )

func _spawn_behavior_agent(role_value: int, seed_value: int, spawn_position: Vector3, route: Array[Vector3], source_anchor: String) -> NpcAgent:
    var agent := NpcAgent.new()
    agent.name = ("BehaviorPolice_%d" if role_value == NpcBehaviorModel.Role.POLICE else "BehaviorCivilian_%d") % seed_value
    agent.role = role_value
    agent.variation_seed = seed_value
    agent.position = spawn_position
    agent.add_to_group("living_city_agent")
    if role_value == NpcBehaviorModel.Role.POLICE:
        agent.add_to_group("police_officer")
    else:
        agent.add_to_group("behavioral_civilian")
    agent.set_meta("source_anchor", source_anchor)
    agent.set_meta("source_bounded_runtime", true)

    var visual := HUMANOID_VISUAL_SCRIPT.new() as Node3D
    visual.name = "VisibleHumanoid"
    if role_value == NpcBehaviorModel.Role.POLICE:
        visual.set("force_police_uniform", true)
    else:
        # humanoid_visual's civilian authored origin is centered around the player
        # capsule; this local lift makes it ground-based on NpcAgent without
        # changing the shared visual implementation.
        visual.position.y = 0.90
    agent.add_child(visual)

    _scene.add_child(agent)
    agent.set_observer_position(_active_player_position())

    var agent_id := agent.get_instance_id()
    _routes[agent_id] = route.duplicate()
    _route_indices[agent_id] = 1 if route.size() > 1 else 0
    if route.size() > 1:
        agent.set_destination(route[1])

    if role_value == NpcBehaviorModel.Role.POLICE:
        _police.append(agent)
    else:
        _civilians.append(agent)
    return agent

func _update_routes() -> void:
    _civilians = _civilians.filter(func(agent: NpcAgent) -> bool: return is_instance_valid(agent))
    _police = _police.filter(func(agent: NpcAgent) -> bool: return is_instance_valid(agent))

    for agent: NpcAgent in _civilians:
        if not agent.active or agent.transit_state != NpcAgent.TransitState.NONE:
            continue
        if agent.behavior.alert_level > 5.0 or agent.civilian_recovery.is_active():
            continue
        _advance_route_if_needed(agent, false)

    for agent: NpcAgent in _police:
        if not agent.active or agent.police_response.phase != NpcPoliceResponse.Phase.PATROL:
            continue
        _advance_route_if_needed(agent, true)

func _advance_route_if_needed(agent: NpcAgent, police_patrol: bool) -> void:
    var agent_id := agent.get_instance_id()
    if not _routes.has(agent_id):
        return
    var route: Array = _routes[agent_id]
    if route.size() < 2:
        return
    var target_index := int(_route_indices.get(agent_id, 0)) % route.size()
    var target_value: Variant = route[target_index]
    if not target_value is Vector3:
        return
    var target := target_value as Vector3
    var planar_distance := Vector2(target.x - agent.get_world_position().x, target.z - agent.get_world_position().z).length()
    if planar_distance > maxf(agent.arrival_radius + 0.35, 0.9):
        if agent.behavior.alert_level <= 5.0 and not _same_planar(agent.behavior.target_position, target):
            agent.set_destination(target)
        return

    target_index = (target_index + 1) % route.size()
    _route_indices[agent_id] = target_index
    var next_value: Variant = route[target_index]
    if not next_value is Vector3:
        return
    var next_target := next_value as Vector3
    if police_patrol and is_instance_valid(_director):
        var plan := _director.assign_police_patrol_segment(agent, str(agent.get_meta("source_anchor", "patrol")), target_index, next_target, 1.0)
        if plan.is_empty():
            agent.set_destination(next_target)
    else:
        agent.set_destination(next_target)

func _update_dangerous_driving(delta: float) -> void:
    _danger_elapsed_s += delta
    if _danger_elapsed_s < 0.12:
        return
    _danger_elapsed_s = 0.0
    if _incident_cooldown_s > 0.0:
        return

    var vehicle := _driven_vehicle()
    if not is_instance_valid(vehicle):
        return
    var speed := _vehicle_speed_mps(vehicle)
    if speed < dangerous_vehicle_speed_mps:
        return

    var vehicle_position := vehicle.global_position
    var trigger_radius_sq := dangerous_near_miss_radius_m * dangerous_near_miss_radius_m
    for civilian: NpcAgent in _civilians:
        if not is_instance_valid(civilian) or not civilian.active:
            continue
        var delta_to_agent := civilian.get_world_position() - vehicle_position
        delta_to_agent.y = 0.0
        if delta_to_agent.length_squared() <= trigger_radius_sq:
            _trigger_incident(vehicle_position, 0.92)
            _incident_cooldown_s = 2.0
            return

func _trigger_incident(world_position: Vector3, severity: float) -> void:
    _incident_serial += 1
    _incident_id = _incident_serial
    _last_incident_position = world_position
    _threat_hold_s = active_threat_hold_seconds
    _detention_hold_s = 0.0

    for civilian: NpcAgent in _civilians:
        if not is_instance_valid(civilian) or not civilian.active:
            continue
        var delta_to_incident := civilian.get_world_position() - world_position
        delta_to_incident.y = 0.0
        if delta_to_incident.length() <= incident_crowd_radius_m:
            civilian.apply_local_crowd_stimulus(world_position, severity, false)

    for officer: NpcAgent in _police:
        if is_instance_valid(officer) and officer.active:
            officer.report_police_incident(world_position, severity, _incident_id)

    _set_status("INTERVENTION POLICE · conduite dangereuse détectée")

func trigger_incident_for_test(world_position: Vector3) -> void:
    if not _bound:
        _try_bind()
    _trigger_incident(world_position, 0.92)

func _update_police_response(delta: float) -> void:
    if _incident_id < 0:
        return
    var target := _active_threat_target()
    var target_position := _last_incident_position
    if is_instance_valid(target):
        target_position = target.global_position
        _last_incident_position = target_position

    var threat_active := _threat_hold_s > 0.0
    var closest_distance := INF
    var any_response_active := false

    for officer: NpcAgent in _police:
        if not is_instance_valid(officer) or not officer.active:
            continue
        var distance := Vector2(
            officer.get_world_position().x - target_position.x,
            officer.get_world_position().z - target_position.z
        ).length()
        closest_distance = minf(closest_distance, distance)

        if threat_active:
            officer.report_police_incident(target_position, 0.92, _incident_id)
            any_response_active = true
        else:
            var phase := officer.update_police_threat(false, 0.0, delta)
            any_response_active = any_response_active or phase != NpcPoliceResponse.Phase.PATROL

    if threat_active and closest_distance <= 2.2 and _active_target_speed_mps(target) <= 1.1:
        _detention_hold_s += delta
        _set_status("CONTRÔLE POLICE · restez sur place")
        if _detention_hold_s >= 2.0:
            _threat_hold_s = 0.0
            _set_status("INTERPELLATION TERMINÉE · les unités se désengagent")
    else:
        _detention_hold_s = 0.0

    if not threat_active and not any_response_active:
        _incident_id = -1
        _set_status("")

func _active_threat_target() -> Node3D:
    var vehicle := _driven_vehicle()
    if is_instance_valid(vehicle):
        return vehicle
    return _player

func _active_target_speed_mps(target: Node3D) -> float:
    if not is_instance_valid(target):
        return 0.0
    if target is RigidBody3D:
        var rigid := target as RigidBody3D
        return Vector2(rigid.linear_velocity.x, rigid.linear_velocity.z).length()
    if target is CharacterBody3D:
        var character := target as CharacterBody3D
        return Vector2(character.velocity.x, character.velocity.z).length()
    return 0.0

func _driven_vehicle() -> Node3D:
    if get_tree() == null:
        return null
    for candidate: Node in get_tree().get_nodes_in_group("vehicle"):
        if candidate is Node3D and candidate.has_method("has_driver") and bool(candidate.call("has_driver")):
            return candidate as Node3D
    return null

func _vehicle_speed_mps(vehicle: Node3D) -> float:
    return _active_target_speed_mps(vehicle)

func _active_player_position() -> Vector3:
    var vehicle := _driven_vehicle()
    if is_instance_valid(vehicle):
        return vehicle.global_position
    if is_instance_valid(_player):
        return _player.global_position
    return Vector3.ZERO

func _load_bourse_sidewalk_centroids() -> Array[Vector3]:
    var points: Array[Vector3] = []
    if not FileAccess.file_exists(BOURSE_SIDEWALKS_PATH):
        push_warning("Visible city: Bourse sidewalk source missing")
        return points
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(BOURSE_SIDEWALKS_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        return points
    var data: Dictionary = parsed
    if str(data.get("schema", "")) != "grand-bruxelles-bourse-official-sidewalk-runtime-v1":
        return points
    for raw_sidewalk: Variant in data.get("sidewalks", []):
        if typeof(raw_sidewalk) != TYPE_DICTIONARY:
            continue
        var sidewalk: Dictionary = raw_sidewalk
        var rings: Array = sidewalk.get("world_rings_xz", [])
        if rings.is_empty() or not rings[0] is Array:
            continue
        var ring: Array = rings[0]
        var sum := Vector2.ZERO
        var count := 0
        for index in range(ring.size()):
            var raw_point: Variant = ring[index]
            if not raw_point is Array or raw_point.size() < 2:
                continue
            if index == ring.size() - 1 and ring.size() > 2:
                var first_value: Variant = ring[0]
                if first_value is Array and first_value.size() >= 2:
                    if is_equal_approx(float(raw_point[0]), float(first_value[0])) and is_equal_approx(float(raw_point[1]), float(first_value[1])):
                        continue
            sum += Vector2(float(raw_point[0]), float(raw_point[1]))
            count += 1
        if count > 0:
            var centroid := sum / float(count)
            points.append(Vector3(centroid.x, 0.18, centroid.y))
    return points

func _build_hud() -> void:
    if is_instance_valid(_hud_layer) or not is_instance_valid(_scene):
        return
    _hud_layer = CanvasLayer.new()
    _hud_layer.name = "VisibleCityHudLayer"
    _hud_layer.layer = 15
    _scene.add_child(_hud_layer)

    _hud_panel = Panel.new()
    _hud_panel.name = "VisibleCityStatus"
    _hud_panel.anchor_left = 0.5
    _hud_panel.anchor_top = 1.0
    _hud_panel.anchor_right = 0.5
    _hud_panel.anchor_bottom = 1.0
    _hud_panel.offset_left = -235.0
    _hud_panel.offset_top = -118.0
    _hud_panel.offset_right = 235.0
    _hud_panel.offset_bottom = -72.0
    _hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
    var style := StyleBoxFlat.new()
    style.bg_color = Color(0.025, 0.035, 0.05, 0.82)
    style.border_color = Color(0.72, 0.80, 0.88, 0.34)
    style.set_border_width_all(1)
    style.corner_radius_top_left = 12
    style.corner_radius_top_right = 12
    style.corner_radius_bottom_left = 12
    style.corner_radius_bottom_right = 12
    _hud_panel.add_theme_stylebox_override("panel", style)
    _hud_layer.add_child(_hud_panel)

    _hud_label = Label.new()
    _hud_label.name = "StatusLabel"
    _hud_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    _hud_label.offset_left = 12.0
    _hud_label.offset_right = -12.0
    _hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _hud_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    _hud_label.add_theme_font_size_override("font_size", 15)
    _hud_label.add_theme_color_override("font_color", Color(0.93, 0.95, 0.97, 1.0))
    _hud_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
    _hud_label.add_theme_constant_override("shadow_offset_x", 2)
    _hud_label.add_theme_constant_override("shadow_offset_y", 2)
    _hud_panel.add_child(_hud_label)

func _update_status_hud() -> void:
    if not is_instance_valid(_hud_label):
        return
    if not _status_text.is_empty():
        _hud_label.text = _status_text
        return
    var active_civilians := 0
    var active_police := 0
    for civilian: NpcAgent in _civilians:
        if is_instance_valid(civilian) and civilian.active:
            active_civilians += 1
    for officer: NpcAgent in _police:
        if is_instance_valid(officer) and officer.active:
            active_police += 1
    _hud_label.text = "VILLE VIVANTE · %d civils actifs · %d policiers" % [active_civilians, active_police]

func _set_status(text_value: String) -> void:
    _status_text = text_value
    if is_instance_valid(_hud_label):
        _hud_label.text = text_value

func status_text_for_test() -> String:
    if is_instance_valid(_hud_label):
        return _hud_label.text
    return _status_text

func visible_population_counts() -> Dictionary:
    var civilian_count := 0
    var police_count := 0
    for civilian: NpcAgent in _civilians:
        if is_instance_valid(civilian):
            civilian_count += 1
    for officer: NpcAgent in _police:
        if is_instance_valid(officer):
            police_count += 1
    return {
        "civilians": civilian_count,
        "police": police_count,
        "midi_spawned": _midi_spawned,
        "bourse_spawned": _bourse_spawned,
        "incident_active": _incident_id >= 0,
    }

func _same_planar(a: Vector3, b: Vector3) -> bool:
    return Vector2(a.x - b.x, a.z - b.z).length() <= 0.08
