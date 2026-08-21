extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_realistic_authored_npc_runtime.gd")

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var failures: Array[String] = []
    var scene := Node3D.new()
    root.add_child(scene)
    var runtime := RUNTIME_SCRIPT.new()
    scene.add_child(runtime)

    var shared_library := AnimationLibrary.new()
    for clip_name: String in ["Shared_Idle", "Shared_Walk", "Shared_Run", "Shared_Wave"]:
        var animation := Animation.new()
        animation.length = 1.0
        animation.loop_mode = Animation.LOOP_NONE
        shared_library.add_animation(clip_name, animation)

    var bound_person := _make_person("BoundProbe", shared_library)
    var untouched_person := _make_person("UntouchedProbe", shared_library)
    scene.add_child(bound_person)
    scene.add_child(untouched_person)

    var untouched_player := untouched_person.get_node("ProfiledNpcProxy/AuthoredCharacter/AnimationPlayer") as AnimationPlayer
    var untouched_wave_before := untouched_player.get_animation("Shared_Wave")
    if not runtime.bind_person(bound_person):
        failures.append("failed to bind shared-resource probe")
    else:
        var bound_player := bound_person.get_node("ProfiledNpcProxy/AuthoredCharacter/AnimationPlayer") as AnimationPlayer
        for clip_name: String in ["Shared_Idle", "Shared_Walk", "Shared_Run"]:
            var untouched_animation := untouched_player.get_animation(clip_name)
            var bound_animation := bound_player.get_animation(clip_name)
            if untouched_animation == null:
                failures.append("unbound player lost shared animation %s" % clip_name)
            elif untouched_animation.loop_mode != Animation.LOOP_NONE:
                failures.append("binding one NPC mutated shared animation loop mode on unbound NPC: %s" % clip_name)
            if bound_animation == null or bound_animation.loop_mode != Animation.LOOP_LINEAR:
                failures.append("bound NPC locomotion animation was not configured to loop: %s" % clip_name)
            elif untouched_animation != null and bound_animation.get_instance_id() == untouched_animation.get_instance_id():
                failures.append("bound locomotion animation remained shared instead of localized: %s" % clip_name)

        var bound_wave := bound_player.get_animation("Shared_Wave")
        var untouched_wave_after := untouched_player.get_animation("Shared_Wave")
        if bound_wave == null or untouched_wave_after == null:
            failures.append("non-locomotion animation was lost during localization")
        else:
            if bound_wave.get_instance_id() != untouched_wave_after.get_instance_id():
                failures.append("non-locomotion animation was needlessly duplicated per NPC")
            if untouched_wave_before != null and bound_wave.get_instance_id() != untouched_wave_before.get_instance_id():
                failures.append("non-locomotion resource identity changed during bind")
            if bound_wave.loop_mode != Animation.LOOP_NONE or untouched_wave_after.loop_mode != Animation.LOOP_NONE:
                failures.append("non-locomotion animation loop mode was modified")

        var stats := runtime.locomotion_stats()
        if not bool(stats.get("localized_locomotion_only", false)):
            failures.append("selective locomotion localization contract missing")

    scene.free()
    if failures.is_empty():
        print("MIDI_REALISTIC_AUTHORED_NPC_SHARED_ANIMATION_RESOURCE_OK")
        quit(0)
        return
    for failure in failures:
        push_error("MIDI_REALISTIC_AUTHORED_NPC_SHARED_ANIMATION_RESOURCE_FAIL: %s" % failure)
    quit(1)

func _make_person(person_name: String, shared_library: AnimationLibrary) -> Node3D:
    var person := Node3D.new()
    person.name = person_name
    person.add_to_group("ambient_pedestrian")
    var proxy := Node3D.new()
    proxy.name = "ProfiledNpcProxy"
    person.add_child(proxy)
    var authored := Node3D.new()
    authored.name = "AuthoredCharacter"
    authored.set_meta("production_authorized", true)
    authored.set_meta("source_asset", "res://assets/characters/civilians/civ1.glb")
    proxy.add_child(authored)
    var player := AnimationPlayer.new()
    player.name = "AnimationPlayer"
    player.add_animation_library("", shared_library)
    authored.add_child(player)
    return person
