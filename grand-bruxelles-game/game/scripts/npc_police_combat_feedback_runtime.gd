extends Node

const SIGNATURE := "police_combat_feedback_v1"
const POLICE_GROUPS: Array[StringName] = [&"police_officer", &"police_npc"]
const RANGED_AFTERGLOW_MS := 110
const HIT_PULSE_MS := 125

var _last_attack_counts: Dictionary = {}
var _last_stagger_until: Dictionary = {}
var _last_player_hit_count := -1


func _ready() -> void:
    process_priority = 240
    set_meta("police_combat_feedback_signature", SIGNATURE)
    set_process(true)


func _process(_delta: float) -> void:
    var player := _current_player()
    _boost_existing_ranged_fx()
    if player != null:
        _process_player_hit_feedback(player)

    var seen: Dictionary = {}
    for group_name: StringName in POLICE_GROUPS:
        for node: Node in get_tree().get_nodes_in_group(group_name):
            if not node is NpcAgent:
                continue
            var officer := node as NpcAgent
            if officer.role != NpcBehaviorModel.Role.POLICE:
                continue
            var instance_id := officer.get_instance_id()
            if seen.has(instance_id):
                continue
            seen[instance_id] = true
            _process_officer_feedback(officer, player)
    _prune(seen)


func _process_officer_feedback(officer: NpcAgent, player: CharacterBody3D) -> void:
    var instance_id := officer.get_instance_id()
    var attack_count := int(officer.get_meta("police_combat_attack_count", 0))
    var previous_attack_count := int(_last_attack_counts.get(instance_id, attack_count))
    if attack_count > previous_attack_count:
        var action_name := StringName(officer.get_meta("police_combat_last_attack", &"none"))
        _emit_attack_feedback(officer, player, action_name)
    _last_attack_counts[instance_id] = attack_count

    var stagger_until := int(officer.get_meta("police_combat_stagger_until_ms", 0))
    var previous_stagger := int(_last_stagger_until.get(instance_id, 0))
    if stagger_until > previous_stagger:
        _spawn_hit_pulse(officer)
        officer.set_meta("police_combat_feedback_hit_pulse_ms", Time.get_ticks_msec())
    _last_stagger_until[instance_id] = stagger_until
    officer.set_meta("police_combat_feedback_signature", SIGNATURE)


func _emit_attack_feedback(officer: NpcAgent, player: CharacterBody3D, action_name: StringName) -> void:
    var audio := get_node_or_null("/root/CombatAudioFeedbackRuntime")
    if audio != null and audio.has_method("_play"):
        if action_name == &"ranged_attack":
            audio.call("_play", &"gun_light", -4.8, 0.93)
        elif action_name == &"melee_attack":
            audio.call("_play", &"melee_swing", -7.8, 0.88)
    officer.set_meta("police_combat_feedback_audio_event", action_name)
    officer.set_meta("police_combat_feedback_audio_count", int(officer.get_meta("police_combat_feedback_audio_count", 0)) + 1)

    if action_name == &"ranged_attack" and player != null:
        _spawn_ranged_afterglow(officer, player)


func _boost_existing_ranged_fx() -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    for node: Node in scene.find_children("PoliceCombatTracer", "MeshInstance3D", true, false):
        var tracer := node as MeshInstance3D
        if tracer == null or bool(tracer.get_meta("police_feedback_boosted", false)):
            continue
        tracer.scale.x *= 1.9
        tracer.scale.y *= 1.9
        tracer.set_meta("police_feedback_boosted", true)
    for node: Node in scene.find_children("PoliceMuzzleFlash", "MeshInstance3D", true, false):
        var flash := node as MeshInstance3D
        if flash == null or bool(flash.get_meta("police_feedback_boosted", false)):
            continue
        flash.scale *= 1.8
        flash.set_meta("police_feedback_boosted", true)


func _spawn_ranged_afterglow(officer: NpcAgent, player: CharacterBody3D) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var origin := officer.global_position + Vector3.UP * 1.42 \
        - officer.global_transform.basis.z.normalized() * 0.30 \
        + officer.global_transform.basis.x.normalized() * 0.20
    var target := player.global_position + Vector3.UP * 1.02
    var delta := target - origin
    var distance := delta.length()
    if distance <= 0.05:
        return

    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.84, 0.28, 1.0)
    material.emission_enabled = true
    material.emission = Color(1.0, 0.28, 0.035, 1.0)
    material.emission_energy_multiplier = 5.0

    var tracer := MeshInstance3D.new()
    tracer.name = "PoliceCombatTracerAfterglow"
    var mesh := BoxMesh.new()
    mesh.size = Vector3(0.05, 0.05, distance)
    mesh.material = material
    tracer.mesh = mesh
    scene.add_child(tracer)
    tracer.global_position = origin.lerp(target, 0.5)
    tracer.look_at(target, Vector3.UP)

    var flash := MeshInstance3D.new()
    flash.name = "PoliceMuzzleFlashAfterglow"
    var flash_mesh := SphereMesh.new()
    flash_mesh.radius = 0.12
    flash_mesh.height = 0.24
    flash_mesh.radial_segments = 10
    flash_mesh.rings = 5
    flash_mesh.material = material
    flash.mesh = flash_mesh
    scene.add_child(flash)
    flash.global_position = origin

    var tracer_tween := create_tween()
    tracer_tween.tween_interval(float(RANGED_AFTERGLOW_MS) / 1000.0)
    tracer_tween.tween_callback(tracer.queue_free)
    var flash_tween := create_tween()
    flash_tween.tween_property(flash, "scale", Vector3(2.0, 2.0, 2.0), 0.045)
    flash_tween.tween_interval(0.035)
    flash_tween.tween_callback(flash.queue_free)


func _spawn_hit_pulse(officer: NpcAgent) -> void:
    var scene := get_tree().current_scene
    if scene == null:
        return
    var pulse := MeshInstance3D.new()
    pulse.name = "PoliceBodyHitPulse"
    var mesh := SphereMesh.new()
    mesh.radius = 0.14
    mesh.height = 0.28
    mesh.radial_segments = 10
    mesh.rings = 5
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(1.0, 0.16, 0.06, 1.0)
    material.emission_enabled = true
    material.emission = Color(1.0, 0.045, 0.01, 1.0)
    material.emission_energy_multiplier = 3.8
    mesh.material = material
    pulse.mesh = mesh
    scene.add_child(pulse)
    pulse.global_position = officer.global_position + Vector3.UP * 1.30
    pulse.scale = Vector3(0.65, 0.65, 0.65)
    var tween := create_tween()
    tween.tween_property(pulse, "scale", Vector3(1.9, 1.9, 1.9), float(HIT_PULSE_MS) / 1000.0)
    tween.tween_callback(pulse.queue_free)


func _process_player_hit_feedback(player: CharacterBody3D) -> void:
    var hit_count := int(player.get_meta("combat_police_hit_count", 0))
    if _last_player_hit_count < 0:
        _last_player_hit_count = hit_count
        return
    if hit_count <= _last_player_hit_count:
        return
    _last_player_hit_count = hit_count
    _spawn_player_damage_flash()


func _spawn_player_damage_flash() -> void:
    var layer := CanvasLayer.new()
    layer.name = "PoliceDamageFlashLayer"
    layer.layer = 90
    add_child(layer)
    var rect := ColorRect.new()
    rect.name = "PoliceDamageFlash"
    rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    rect.color = Color(0.72, 0.02, 0.01, 0.18)
    layer.add_child(rect)
    var tween := create_tween()
    tween.tween_property(rect, "color:a", 0.0, 0.13)
    tween.tween_callback(layer.queue_free)


func _current_player() -> CharacterBody3D:
    var scene := get_tree().current_scene
    if scene == null:
        return null
    var direct := scene.get_node_or_null("Player") as CharacterBody3D
    if direct != null:
        return direct
    return scene.find_child("Player", true, false) as CharacterBody3D


func _prune(seen: Dictionary) -> void:
    var stale: Array[int] = []
    for raw_id: Variant in _last_attack_counts.keys():
        var instance_id := int(raw_id)
        if not seen.has(instance_id):
            stale.append(instance_id)
    for instance_id: int in stale:
        _last_attack_counts.erase(instance_id)
        _last_stagger_until.erase(instance_id)
