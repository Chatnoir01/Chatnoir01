extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/midi_realistic_authored_npc_runtime.gd")
const DT := 1.0 / 60.0

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var failures: Array[String] = []
    var scene := Node3D.new()
    root.add_child(scene)
    var runtime := RUNTIME_SCRIPT.new()
    scene.add_child(runtime)
    var person := _make_person_with_two_players()
    scene.add_child(person)

    if not runtime.bind_person(person):
        failures.append("failed to select locomotion-capable AnimationPlayer when an earlier facial player exists")
    else:
        var clips := runtime.resolved_locomotion_for(person)
        if String(clips.get("idle", "")) != "Body_Idle" or String(clips.get("walk", "")) != "Body_Walk" or String(clips.get("run", "")) != "Body_Run":
            failures.append("resolved clips from wrong AnimationPlayer: %s" % clips)
        if not runtime.update_person_from_observed_speed(person, 1.90, DT):
            failures.append("run update failed after multi-player bind")
        elif runtime.current_animation_for(person) != "Body_Run":
            failures.append("wrong run animation after multi-player bind: %s" % runtime.current_animation_for(person))

    scene.free()
    if failures.is_empty():
        print("MIDI_REALISTIC_AUTHORED_NPC_MULTI_PLAYER_OK")
        quit(0)
        return
    for failure in failures:
        push_error("MIDI_REALISTIC_AUTHORED_NPC_MULTI_PLAYER_FAIL: %s" % failure)
    quit(1)

func _make_person_with_two_players() -> Node3D:
    var person := Node3D.new()
    person.name = "MultiAnimationPlayerProbe"
    person.add_to_group("ambient_pedestrian")
    var proxy := Node3D.new()
    proxy.name = "ProfiledNpcProxy"
    person.add_child(proxy)
    var authored := Node3D.new()
    authored.name = "AuthoredCharacter"
    authored.set_meta("production_authorized", true)
    authored.set_meta("source_asset", "res://assets/characters/civilians/civ1.glb")
    proxy.add_child(authored)

    var facial := AnimationPlayer.new()
    facial.name = "A_FacialAnimationPlayer"
    facial.add_animation_library("", AnimationLibrary.new())
    authored.add_child(facial)
    _add_animation(facial, "Face_Blink")
    _add_animation(facial, "Face_Talk")

    var body_container := Node3D.new()
    body_container.name = "Rig"
    authored.add_child(body_container)
    var body := AnimationPlayer.new()
    body.name = "BodyAnimationPlayer"
    body.add_animation_library("", AnimationLibrary.new())
    body_container.add_child(body)
    _add_animation(body, "Body_Idle")
    _add_animation(body, "Body_Walk")
    _add_animation(body, "Body_Run")
    return person

func _add_animation(player: AnimationPlayer, name: String) -> void:
    var animation := Animation.new()
    animation.length = 1.0
    player.get_animation_library("").add_animation(name, animation)
