extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_realistic_authored_npc_runtime.gd")
const BANNED_PLAYER_ASSET := "res://assets/characters/player_character.glb"

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var failures: Array[String] = []
    var scene := Node3D.new()
    root.add_child(scene)
    var runtime := RUNTIME_SCRIPT.new()
    scene.add_child(runtime)

    var unauthorized := _make_person("Unauthorized", false, ["Civil_Idle", "Civil_Walk", "Civil_Run"])
    scene.add_child(unauthorized)
    if runtime.bind_person(unauthorized):
        failures.append("accepted production_authorized=false")
    var unauthorized_authored := unauthorized.get_node("ProfiledNpcProxy/AuthoredCharacter") as Node3D
    unauthorized_authored.set_meta("production_authorized", true)
    runtime._update_all(1.0 / 60.0)
    if runtime.current_locomotion_state_for(unauthorized) != "idle":
        failures.append("did not recover after production authorization became valid")

    var player_reuse := _make_person("PlayerReuse", true, ["Civil_Idle", "Civil_Walk", "Civil_Run"], BANNED_PLAYER_ASSET)
    scene.add_child(player_reuse)
    if runtime.bind_person(player_reuse):
        failures.append("accepted player character as civilian source")
    var reused_authored := player_reuse.get_node("ProfiledNpcProxy/AuthoredCharacter") as Node3D
    reused_authored.set_meta("source_asset", "res://assets/characters/civilians/civ1.glb")
    runtime._update_all(1.0 / 60.0)
    if runtime.current_locomotion_state_for(player_reuse) != "idle":
        failures.append("player-reuse rejection stayed sticky after source was replaced")

    var action_only_run := _make_person("ActionRun", true, ["Civil_Idle", "Civil_Walk", "Attack_Run"])
    scene.add_child(action_only_run)
    if runtime.bind_person(action_only_run):
        failures.append("accepted combat/action run fallback")

    var ambiguous := _make_person("Ambiguous", true, [
        "A_Catwalk_Pose", "A_IdleHands", "A_Runway_Look",
        "A_Idle_To_Walk", "A_Walk_Backward", "A_Run_Start",
        "Z_Idle", "Z_Walk", "Z_Run"
    ])
    scene.add_child(ambiguous)
    if not runtime.bind_person(ambiguous):
        failures.append("rejected valid locomotion set when misleading clip names were also present")
    else:
        var ambiguous_clips := runtime.resolved_locomotion_for(ambiguous)
        if String(ambiguous_clips.get("idle", "")) != "Z_Idle":
            failures.append("selected non-token idle substring/transition as loop: %s" % String(ambiguous_clips.get("idle", "")))
        if String(ambiguous_clips.get("walk", "")) != "Z_Walk":
            failures.append("selected catwalk/backward walk as forward loop: %s" % String(ambiguous_clips.get("walk", "")))
        if String(ambiguous_clips.get("run", "")) != "Z_Run":
            failures.append("selected runway/run-start as loop: %s" % String(ambiguous_clips.get("run", "")))

    var backpack_walk := _make_person("BackpackWalk", true, ["Civil_Idle", "Civil_Backpack_Walk", "Civil_Run"])
    scene.add_child(backpack_walk)
    if not runtime.bind_person(backpack_walk):
        failures.append("rejected valid Civil_Backpack_Walk because directional filter matched lexical substring")
    else:
        var backpack_clips := runtime.resolved_locomotion_for(backpack_walk)
        if String(backpack_clips.get("walk", "")) != "Civil_Backpack_Walk":
            failures.append("failed to preserve valid lexical-overlap walk clip: %s" % String(backpack_clips.get("walk", "")))

    var firefighter := _make_person("Firefighter", true, ["Firefighter_Idle", "Firefighter_Walk", "Firefighter_Run"])
    scene.add_child(firefighter)
    if not runtime.bind_person(firefighter):
        failures.append("rejected valid firefighter locomotion because action filter matched lexical substring 'fire'")

    var vertical_probe := _make_person("VerticalGroundingProbe", true, ["Probe_Idle", "Probe_Walk", "Probe_Run"], "res://assets/characters/civilians/civ1.glb")
    scene.add_child(vertical_probe)
    if not runtime.bind_person(vertical_probe):
        failures.append("failed to bind vertical grounding probe")
    else:
        runtime._update_all(1.0 / 60.0)
        vertical_probe.position.y += 0.10
        runtime._update_all(1.0 / 60.0)
        if runtime.current_locomotion_state_for(vertical_probe) != "idle":
            failures.append("vertical-only grounding correction triggered locomotion/foot-slide: %s" % runtime.current_locomotion_state_for(vertical_probe))

    var incomplete := _make_person("Incomplete", true, ["Civil_Idle", "Civil_Walk"])
    scene.add_child(incomplete)
    if runtime.bind_person(incomplete):
        failures.append("accepted missing run clip")
    _add_clip(incomplete, "Civil_Run")
    runtime._update_all(1.0 / 60.0)
    if runtime.current_locomotion_state_for(incomplete) != "idle":
        failures.append("missing-clip rejection stayed sticky after run clip was added")

    var person := _make_person("Authorized", true, ["Civil_Idle", "Civil_Walk", "Civil_Run"], "res://assets/characters/civilians/civ1.glb")
    scene.add_child(person)
    if not runtime.bind_person(person):
        failures.append("failed to bind valid authored civilian")
    else:
        _assert_state(runtime, person, 0.0, "idle", "Civil_Idle", failures)
        _assert_state(runtime, person, 0.95, "walk", "Civil_Walk", failures)
        var walk_scale := runtime.current_playback_speed_scale_for(person)
        if walk_scale < 0.68 or walk_scale > 1.45:
            failures.append("walk playback scale escaped safe range: %.4f" % walk_scale)
        _assert_state(runtime, person, 0.15, "walk", "Civil_Walk", failures)
        _assert_state(runtime, person, 0.05, "idle", "Civil_Idle", failures)
        _assert_state(runtime, person, 1.90, "run", "Civil_Run", failures)
        _assert_state(runtime, person, 1.50, "run", "Civil_Run", failures)
        _assert_state(runtime, person, 1.30, "walk", "Civil_Walk", failures)
        var authored := person.get_node_or_null("ProfiledNpcProxy/AuthoredCharacter") as Node3D
        authored.set_meta("production_authorized", false)
        if runtime.update_person_from_observed_speed(person, 0.9):
            failures.append("kept animating after authorization revocation")

    var swap_person := _make_person("Swap", true, ["Civil_Idle", "Civil_Walk", "Civil_Run"], "res://assets/characters/civilians/civ1.glb")
    scene.add_child(swap_person)
    if not runtime.bind_person(swap_person):
        failures.append("failed to bind swap baseline")
    else:
        var swap_proxy := swap_person.get_node("ProfiledNpcProxy") as Node3D
        var old_authored := swap_proxy.get_node("AuthoredCharacter") as Node3D
        var replacement_template := _make_person("ReplacementTemplate", true, ["Fresh_Idle", "Fresh_Walk", "Fresh_Run"], "res://assets/characters/civilians/civ2.glb")
        var replacement_proxy := replacement_template.get_node("ProfiledNpcProxy") as Node3D
        var replacement_authored := replacement_proxy.get_node("AuthoredCharacter") as Node3D
        replacement_proxy.remove_child(replacement_authored)
        swap_proxy.remove_child(old_authored)
        swap_proxy.add_child(replacement_authored)
        runtime._update_all(1.0 / 60.0)
        var swapped_clips := runtime.resolved_locomotion_for(swap_person)
        if String(swapped_clips.get("idle", "")) != "Fresh_Idle" or String(swapped_clips.get("walk", "")) != "Fresh_Walk" or String(swapped_clips.get("run", "")) != "Fresh_Run":
            failures.append("kept stale authored binding after AuthoredCharacter node replacement")
        old_authored.free()
        replacement_template.free()

    var detached_runtime := RUNTIME_SCRIPT.new()
    detached_runtime._update_all(1.0 / 60.0)

    var stats := runtime.locomotion_stats()
    if bool(stats.get("changes_movement_owner", true)):
        failures.append("adapter claims movement ownership")
    if bool(stats.get("changes_navigation", true)):
        failures.append("adapter claims navigation changes")
    if not bool(stats.get("speed_sync", false)):
        failures.append("speed synchronization contract missing")
    if not bool(stats.get("state_hysteresis", false)):
        failures.append("hysteresis contract missing")
    if bool(stats.get("action_clip_fallback_allowed", true)):
        failures.append("action fallback unexpectedly allowed")
    if bool(stats.get("directional_transition_clip_fallback_allowed", true)):
        failures.append("directional/transition fallback unexpectedly allowed")
    if not bool(stats.get("exact_locomotion_token_matching", false)):
        failures.append("exact locomotion token matching contract missing")
    if not bool(stats.get("exact_rejection_token_matching", false)):
        failures.append("exact rejection token matching contract missing")
    if bool(stats.get("player_character_reuse_allowed", true)):
        failures.append("player reuse unexpectedly allowed")
    if not bool(stats.get("dynamic_rejection_recovery", false)):
        failures.append("dynamic rejection recovery contract missing")
    if int(stats.get("player_reuse_rejections", 0)) < 1:
        failures.append("player reuse rejection was not counted")
    if int(stats.get("incomplete_clip_rejections", 0)) < 2:
        failures.append("incomplete/action clip rejections were not counted")
    if not bool(stats.get("multi_animation_player_selection", false)):
        failures.append("multi AnimationPlayer selection contract missing")

    scene.free()
    detached_runtime.free()
    if failures.is_empty():
        print("MIDI_REALISTIC_AUTHORED_NPC_RUNTIME_OK")
        quit(0)
        return
    for failure in failures:
        push_error("MIDI_REALISTIC_AUTHORED_NPC_RUNTIME_FAIL: %s" % failure)
    quit(1)

func _assert_state(runtime: Node, person: Node3D, speed: float, expected_state: String, expected_animation: String, failures: Array[String]) -> void:
    if not runtime.update_person_from_observed_speed(person, speed, 1.0 / 60.0):
        failures.append("update failed at speed %.2f" % speed)
        return
    var actual_state := str(runtime.current_locomotion_state_for(person))
    var actual_animation := str(runtime.current_animation_for(person))
    if actual_state != expected_state:
        failures.append("speed %.2f state=%s expected=%s" % [speed, actual_state, expected_state])
    if actual_animation != expected_animation:
        failures.append("speed %.2f animation=%s expected=%s" % [speed, actual_animation, expected_animation])

func _make_person(person_name: String, authorized: bool, clip_names: Array[String], source_asset: String = "") -> Node3D:
    var person := Node3D.new()
    person.name = person_name
    person.add_to_group("ambient_pedestrian")
    var proxy := Node3D.new()
    proxy.name = "ProfiledNpcProxy"
    person.add_child(proxy)
    var authored := Node3D.new()
    authored.name = "AuthoredCharacter"
    authored.set_meta("production_authorized", authorized)
    if not source_asset.is_empty():
        authored.set_meta("source_asset", source_asset)
    proxy.add_child(authored)
    var player := AnimationPlayer.new()
    player.name = "AnimationPlayer"
    player.add_animation_library("", AnimationLibrary.new())
    authored.add_child(player)
    for clip_name: String in clip_names:
        _add_clip(person, clip_name)
    return person

func _add_clip(person: Node3D, clip_name: String) -> void:
    var player := person.get_node("ProfiledNpcProxy/AuthoredCharacter/AnimationPlayer") as AnimationPlayer
    var library := player.get_animation_library("")
    var animation := Animation.new()
    animation.length = 1.0
    library.add_animation(clip_name, animation)
