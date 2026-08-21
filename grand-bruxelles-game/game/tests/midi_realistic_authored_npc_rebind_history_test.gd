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
    var person := _make_person()
    scene.add_child(person)

    if not runtime.bind_person(person):
        failures.append("failed to bind rebind-motion-history probe")
    else:
        runtime._update_all(DT)
        var authored := person.get_node("ProfiledNpcProxy/AuthoredCharacter") as Node3D
        authored.set_meta("production_authorized", false)
        runtime._update_all(DT)
        person.position.x += 0.50
        runtime._update_all(DT)
        authored.set_meta("production_authorized", true)
        runtime._update_all(DT)
        var state := runtime.current_locomotion_state_for(person)
        if state != "idle": failures.append("stale pre-rebind position produced false locomotion after reauthorization: %s" % state)

    if not bool(runtime.locomotion_stats().get("rebind_resets_motion_history", false)):
        failures.append("rebind motion-history reset contract missing")
    scene.free()
    if failures.is_empty(): print("MIDI_REALISTIC_AUTHORED_NPC_REBIND_HISTORY_OK"); quit(0); return
    for failure in failures: push_error("MIDI_REALISTIC_AUTHORED_NPC_REBIND_HISTORY_FAIL: %s" % failure)
    quit(1)

func _make_person() -> Node3D:
    var person := Node3D.new(); person.name = "RebindMotionHistoryProbe"; person.add_to_group("ambient_pedestrian")
    var proxy := Node3D.new(); proxy.name = "ProfiledNpcProxy"; person.add_child(proxy)
    var authored := Node3D.new(); authored.name = "AuthoredCharacter"; authored.set_meta("production_authorized", true); authored.set_meta("source_asset", "res://assets/characters/civilians/civ1.glb"); proxy.add_child(authored)
    var player := AnimationPlayer.new(); player.name = "AnimationPlayer"; player.add_animation_library("", AnimationLibrary.new()); authored.add_child(player)
    var library := player.get_animation_library("")
    for clip_name: String in ["Probe_Idle", "Probe_Walk", "Probe_Run"]:
        var animation := Animation.new(); animation.length = 1.0; library.add_animation(clip_name, animation)
    return person
