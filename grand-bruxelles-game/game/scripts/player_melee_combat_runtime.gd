extends Node

const ATTACK_DAMAGE := 34.0
const ATTACK_RADIUS := 0.92
const ATTACK_REACH := 1.45
const ATTACK_HEIGHT := 0.95
const ATTACK_COOLDOWN_MS := 430
const DEFEND_HOLD_MS := 650
const FIGHT_WINDOW_MS := 5200
const COUNTER_COOLDOWN_MS := 900
const COUNTER_DAMAGE := 8
const GUARDED_COUNTER_DAMAGE := 2
const WORLD_REACTION_RADIUS_M := 14.0
const LOOT_REACH_M := 2.20
const LOOT_MIN_EUR := 8
const LOOT_VARIATION_EUR := 23

var _attack_serial := 0
var _next_attack_allowed_ms := 0
var _feedback_hide_ms := 0
var _feedback_label: Label = null
var _reaction_states: Dictionary = {}
var _guarding := false
var _guard_visual_base_x := 0.0
var _guard_visual_bound := false

func _ready() -> void:
    set_process(true)
    set_process_input(true)

func _input(event: InputEvent) -> void:
    var player := _current_player()
    if player == null:
        return

    if event is InputEventMouseButton:
        var mouse_event := event as InputEventMouseButton
        if mouse_event.button_index == MOUSE_BUTTON_RIGHT:
            set_guarding(player, mouse_event.pressed)
            return
        if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
            request_attack(player)
            return
    elif event is InputEventKey:
        var key_event := event as InputEventKey
        if key_event.keycode == KEY_G and not key_event.echo:
            set_guarding(player, key_event.pressed)
            return
        if key_event.keycode == KEY_F and key_event.pressed and not key_event.echo:
            request_attack(player)
            return
        if key_event.keycode == KEY_E and key_event.pressed and not key_event.echo:
            request_loot(player)

func _process(_delta: float) -> void:
    var now := Time.get_ticks_msec()
    if _feedback_label != null and now >= _feedback_hide_ms:
        _feedback_label.visible = false
    _tick_reactions(now)

func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    return scene.get_node_or_null("Player") as CharacterBody3D

func set_guarding(player: CharacterBody3D, enabled: bool) -> void:
    if player == null or not is_instance_valid(player):
        return
    _guarding = enabled
    player.set_meta("combat_guarding", enabled)
    var visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if visual != null:
        if enabled and not _guard_visual_bound:
            _guard_visual_base_x = visual.rotation.x
            _guard_visual_bound = true
        visual.rotation.x = _guard_visual_base_x + (0.11 if enabled else 0.0)
    if enabled:
        _show_feedback("GARDE", 180)

func is_guarding(player: CharacterBody3D) -> bool:
    return player != null and bool(player.get_meta("combat_guarding", false))

func request_attack(player: CharacterBody3D) -> Dictionary:
    if is_guarding(player):
        return {"hit": false, "reason": "guarding"}
    var now := Time.get_ticks_msec()
    if now < _next_attack_allowed_ms:
        return {"hit": false, "reason": "cooldown"}
    _next_attack_allowed_ms = now + ATTACK_COOLDOWN_MS
    _animate_player_swing(player)
    var result := perform_attack(player)
    if bool(result.get("hit", false)):
        if StringName(result.get("reaction", &"")) == &"ko":
            _show_feedback("K.O.   E : FOUILLER", 520)
        else:
            _show_feedback("TOUCHÉ  -%d" % int(ATTACK_DAMAGE), 280)
    else:
        _show_feedback("COUP", 150)
    return result

func perform_attack(player: CharacterBody3D) -> Dictionary:
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        return {"hit": false, "reason": "player_unavailable"}
    if not player.has_meta("combat_health"):
        player.set_meta("combat_health", 100)
    _attack_serial += 1

    var forward := -player.global_transform.basis.z.normalized()
    var origin := player.global_position + forward * ATTACK_REACH + Vector3.UP * ATTACK_HEIGHT
    var sphere := SphereShape3D.new()
    sphere.radius = ATTACK_RADIUS
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = sphere
    query.transform = Transform3D(Basis.IDENTITY, origin)
    query.collision_mask = 0xFFFFFFFF
    query.collide_with_bodies = true
    query.collide_with_areas = true
    query.exclude = [player.get_rid()]

    var hits := player.get_world_3d().direct_space_state.intersect_shape(query, 32)
    var target: NpcAgent = null
    var best_distance := INF
    for hit: Dictionary in hits:
        var npc := _npc_from_collider(hit.get("collider"))
        if npc == null or npc == player or bool(npc.get_meta("melee_knocked_out", false)):
            continue
        var to_target := npc.global_position - player.global_position
        to_target.y = 0.0
        if to_target.length_squared() <= 0.0001:
            continue
        if forward.dot(to_target.normalized()) < 0.20:
            continue
        var distance := to_target.length()
        if distance < best_distance:
            best_distance = distance
            target = npc

    if target == null:
        return {
            "hit": false,
            "reason": "no_target",
            "attack_origin": origin,
            "attack_radius": ATTACK_RADIUS,
        }

    var reaction := _apply_hit(target, player, ATTACK_DAMAGE)
    _notify_nearby_world(target.global_position, player, target)
    return {
        "hit": true,
        "target": target,
        "damage": ATTACK_DAMAGE,
        "reaction": reaction,
        "attack_origin": origin,
        "attack_radius": ATTACK_RADIUS,
    }

func request_loot(player: CharacterBody3D) -> Dictionary:
    if player == null or not is_instance_valid(player) or not player.is_inside_tree():
        return {"looted": false, "reason": "player_unavailable"}
    if is_guarding(player):
        return {"looted": false, "reason": "guarding"}

    var root_node: Node = get_tree().current_scene
    if root_node == null:
        root_node = player.get_parent()
    if root_node == null:
        return {"looted": false, "reason": "no_target"}

    var forward := -player.global_transform.basis.z.normalized()
    var target: NpcAgent = null
    var best_distance := INF
    var nearby_already_looted := false
    for node: Node in root_node.find_children("*", "", true, false):
        if not node is NpcAgent:
            continue
        var npc := node as NpcAgent
        if not bool(npc.get_meta("melee_knocked_out", false)):
            continue
        var offset := npc.global_position - player.global_position
        offset.y = 0.0
        var distance := offset.length()
        if distance > LOOT_REACH_M:
            continue
        if distance > 0.001 and forward.dot(offset.normalized()) < -0.20:
            continue
        if bool(npc.get_meta("melee_looted", false)):
            nearby_already_looted = true
            continue
        if distance < best_distance:
            best_distance = distance
            target = npc

    if target == null:
        var reason := "already_looted" if nearby_already_looted else "no_target"
        if nearby_already_looted:
            _show_feedback("DÉJÀ FOUILLÉ", 220)
        return {"looted": false, "reason": reason}

    var amount := LOOT_MIN_EUR + posmod(target.variation_seed * 11 + 7, LOOT_VARIATION_EUR)
    var cash := int(player.get_meta("combat_cash_eur", 0)) + amount
    player.set_meta("combat_cash_eur", cash)
    player.set_meta("combat_loot_count", int(player.get_meta("combat_loot_count", 0)) + 1)
    target.set_meta("melee_looted", true)
    target.set_meta("melee_loot_eur", amount)
    _show_feedback("FOUILLÉ  +€%d   €%d" % [amount, cash], 420)
    return {
        "looted": true,
        "target": target,
        "amount_eur": amount,
        "cash_eur": cash,
    }

func _npc_from_collider(value: Variant) -> NpcAgent:
    if not value is Node:
        return null
    var current := value as Node
    while current != null:
        if current is NpcAgent:
            return current as NpcAgent
        current = current.get_parent()
    return null

func _apply_hit(npc: NpcAgent, player: CharacterBody3D, damage: float) -> StringName:
    var health := float(npc.get_meta("melee_health", 100.0))
    health = maxf(0.0, health - maxf(damage, 0.0))
    npc.set_meta("melee_health", health)
    npc.set_meta("melee_hit_count", int(npc.get_meta("melee_hit_count", 0)) + 1)
    npc.set_meta("melee_hurt_feedback", true)
    npc.set_meta("last_melee_attacker_id", player.get_instance_id())

    if health <= 0.0:
        _knock_out(npc)
        _spawn_hurt_feedback(npc, &"ko")
        return &"ko"

    var reaction := _reaction_for(npc, health)
    npc.set_meta("melee_reaction", reaction)
    var now := Time.get_ticks_msec()
    var state := {
        "npc": weakref(npc),
        "player": weakref(player),
        "reaction": reaction,
        "expires_ms": now + (DEFEND_HOLD_MS if reaction == &"defend" else FIGHT_WINDOW_MS),
        "next_counter_ms": now + 450,
    }
    _reaction_states[npc.get_instance_id()] = state

    if reaction == &"flee":
        npc.movement_held = false
        npc.behavior.apply_stimulus(90.0, player.global_position)
    elif reaction == &"fight":
        npc.movement_held = false
        npc.behavior.set_destination(player.global_position)
    else:
        npc.movement_held = true
        npc.velocity.x = 0.0
        npc.velocity.z = 0.0

    _spawn_hurt_feedback(npc, reaction)
    return reaction

func _knock_out(npc: NpcAgent) -> void:
    _reaction_states.erase(npc.get_instance_id())
    npc.set_meta("melee_knocked_out", true)
    npc.set_meta("melee_reaction", &"ko")
    npc.set_meta("melee_hurt_feedback", false)
    npc.set_meta("melee_looted", false)
    npc.movement_held = true
    npc.velocity = Vector3.ZERO
    npc.active = false

    var visual: Node3D = npc.get_node_or_null("ProfiledNpcProxy") as Node3D
    if visual == null:
        visual = npc.get_node_or_null("VisualUpgrade") as Node3D
    if visual != null:
        var tween := create_tween()
        tween.tween_property(visual, "rotation:z", deg_to_rad(72.0), 0.20)

func _reaction_for(npc: NpcAgent, health: float) -> StringName:
    if npc.role == NpcBehaviorModel.Role.POLICE:
        return &"fight"
    if health <= 32.0:
        return &"flee"
    var bucket := posmod(npc.variation_seed * 31 + _attack_serial * 17, 100)
    if bucket < 34:
        return &"defend"
    if bucket < 70:
        return &"fight"
    return &"flee"

func resolve_counter_hit(player: CharacterBody3D) -> int:
    if player == null or not is_instance_valid(player):
        return 0
    var guarded := is_guarding(player)
    var damage := GUARDED_COUNTER_DAMAGE if guarded else COUNTER_DAMAGE
    var player_health := maxi(0, int(player.get_meta("combat_health", 100)) - damage)
    player.set_meta("combat_health", player_health)
    player.set_meta("combat_last_counter_damage", damage)
    if guarded:
        _show_feedback("BLOQUÉ  -%d   PV %d" % [damage, player_health], 300)
    else:
        _show_feedback("RIPOSTE  -%d   PV %d" % [damage, player_health], 350)
    return damage

func _tick_reactions(now: int) -> void:
    var expired: Array[int] = []
    for raw_id: Variant in _reaction_states.keys():
        var instance_id := int(raw_id)
        var state: Dictionary = _reaction_states[instance_id]
        var npc_ref: WeakRef = state.get("npc")
        var player_ref: WeakRef = state.get("player")
        var npc := npc_ref.get_ref() as NpcAgent if npc_ref != null else null
        var player := player_ref.get_ref() as CharacterBody3D if player_ref != null else null
        if npc == null or not is_instance_valid(npc) or bool(npc.get_meta("melee_knocked_out", false)):
            expired.append(instance_id)
            continue
        var reaction := StringName(state.get("reaction", &""))
        if now >= int(state.get("expires_ms", 0)):
            if reaction == &"defend":
                npc.movement_held = false
            npc.set_meta("melee_hurt_feedback", false)
            expired.append(instance_id)
            continue
        if reaction != &"fight" or player == null or not is_instance_valid(player):
            continue
        npc.behavior.set_destination(player.global_position)
        var planar_distance := Vector2(
            npc.global_position.x - player.global_position.x,
            npc.global_position.z - player.global_position.z
        ).length()
        if planar_distance <= 2.05 and now >= int(state.get("next_counter_ms", 0)):
            resolve_counter_hit(player)
            state["next_counter_ms"] = now + COUNTER_COOLDOWN_MS
            _reaction_states[instance_id] = state
    for instance_id: int in expired:
        _reaction_states.erase(instance_id)

func _notify_nearby_world(position: Vector3, player: CharacterBody3D, struck: NpcAgent) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        scene = player.get_parent()
    if scene == null:
        return
    var incident_id := _attack_serial
    for node: Node in scene.find_children("*", "", true, false):
        if not node is NpcAgent:
            continue
        var npc := node as NpcAgent
        if npc == struck:
            continue
        if npc.global_position.distance_to(position) > WORLD_REACTION_RADIUS_M:
            continue
        if npc.role == NpcBehaviorModel.Role.POLICE:
            npc.report_police_incident(position, 0.78, incident_id)
            npc.update_police_threat(true, 0.82, 0.1)
        else:
            npc.apply_local_crowd_stimulus(position, 0.72, false)

func _animate_player_swing(player: CharacterBody3D) -> void:
    var visual := player.get_node_or_null("VisualUpgrade") as Node3D
    if visual == null:
        return
    var base_x := visual.rotation.x
    var tween := create_tween()
    tween.tween_property(visual, "rotation:x", base_x - 0.18, 0.07)
    tween.tween_property(visual, "rotation:x", base_x, 0.12)

func _spawn_hurt_feedback(npc: NpcAgent, reaction: StringName) -> void:
    var marker := Label3D.new()
    marker.name = "MeleeHurtFeedback"
    if reaction == &"ko":
        marker.text = "K.O."
    else:
        marker.text = "HIT  -%d\n%s" % [int(ATTACK_DAMAGE), String(reaction).to_upper()]
    marker.position = Vector3(0.0, 2.15, 0.0)
    marker.font_size = 36
    marker.outline_size = 8
    npc.add_child(marker)
    var tween := create_tween()
    tween.tween_property(marker, "position:y", 2.65, 0.42)
    tween.tween_callback(marker.queue_free)

func _show_feedback(text: String, duration_ms: int) -> void:
    if _feedback_label == null:
        var layer := CanvasLayer.new()
        layer.name = "CombatFeedbackLayer"
        add_child(layer)
        _feedback_label = Label.new()
        _feedback_label.name = "CombatFeedback"
        _feedback_label.position = Vector2(520.0, 335.0)
        _feedback_label.size = Vector2(320.0, 52.0)
        _feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        _feedback_label.add_theme_font_size_override("font_size", 24)
        layer.add_child(_feedback_label)
    _feedback_label.text = text
    _feedback_label.visible = true
    _feedback_hide_ms = Time.get_ticks_msec() + duration_ms
