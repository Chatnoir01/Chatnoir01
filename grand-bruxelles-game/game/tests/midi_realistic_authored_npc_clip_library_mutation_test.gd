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
        failures.append("failed to bind clip-library mutation probe")
    else:
        var initial := runtime.resolved_locomotion_for(person)
        if String(initial.get("run", "")) != "Probe_Run": failures.append("unexpected initial run clip")
        var player := person.get_node("ProfiledNpcProxy/AuthoredCharacter/AnimationPlayer") as AnimationPlayer
        var library := player.get_animation_library("")
        library.remove_animation("Probe_Run")
        var replacement := Animation.new(); replacement.length = 1.0; library.add_animation("Fresh_Run", replacement)
        runtime._update_all(DT)
        var resolved := runtime.resolved_locomotion_for(person)
        if String(resolved.get("run", "")) != "Fresh_Run": failures.append("stale binding did not re-resolve mutated run clip")
        if not runtime.update_person_from_observed_speed(person, 1.90, DT): failures.append("runtime stayed frozen after replacement run clip")
        elif runtime.current_animation_for(person) != "Fresh_Run": failures.append("replacement run clip was not selected")

    scene.free()
    if failures.is_empty(): print("MIDI_REALISTIC_AUTHORED_NPC_CLIP_LIBRARY_MUTATION_OK"); quit(0); return
    for failure in failures: push_error("MIDI_REALISTIC_AUTHORED_NPC_CLIP_LIBRARY_MUTATION_FAIL: %s" % failure)
    quit(1)

func _make_person() -> Node3D:
    var person := Node3D.new(); person.name = "ClipLibraryMutationProbe"; person.add_to_group("ambient_pedestrian")
    var proxy := Node3D.new(); proxy.name = "ProfiledNpcProxy"; person.add_child(proxy)
    var authored := Node3D.new(); authored.name = "AuthoredCharacter"; authored.set_meta("production_authorized", true); authored.set_meta("source_asset", "res://assets/characters/civilians/civ1.glb"); proxy.add_child(authored)
    var player := AnimationPlayer.new(); player.name = "AnimationPlayer"; player.add_animation_library("", AnimationLibrary.new()); authored.add_child(player)
    var library := player.get_animation_library("")
    for clip_name: String in ["Probe_Idle", "Probe_Walk", "Probe_Run"]:
        var animation := Animation.new(); animation.length = 1.0; library.add_animation(clip_name, animation)
    return person
