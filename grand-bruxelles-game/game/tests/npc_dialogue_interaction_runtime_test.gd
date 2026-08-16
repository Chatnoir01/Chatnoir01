extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("NPC_DIALOGUE_VISIBLE_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _calm_blackboard() -> Dictionary:
    return {
        "threat": 0.0,
        "health": 100.0,
        "police_nearby": false,
        "distance_to_player": 2.0,
        "zone": "midi",
        "event_serial": 41,
    }

func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("main scene could not be loaded")
        return
    var main := packed.instantiate()
    root.add_child(main)
    current_scene = main
    for _frame: int in range(8):
        await process_frame

    var runtime := root.get_node_or_null("NpcDialogueInteractionRuntime")
    if not _expect(runtime != null, "dialogue autoload missing"):
        return
    if not _expect(runtime.has_method("nearest_talkable") and runtime.has_method("open_for_npc"), "dialogue runtime API incomplete"):
        return

    var pedestrians := get_nodes_in_group("ambient_pedestrian")
    if not _expect(not pedestrians.is_empty(), "production main spawned no ambient pedestrians"):
        return
    var pedestrian := pedestrians[0] as Node3D
    if not _expect(pedestrian != null, "ambient pedestrian is not Node3D"):
        return

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if not _expect(player != null, "production player missing"):
        return
    player.global_position = pedestrian.global_position + Vector3(0.0, 0.0, 2.0)
    player.velocity = Vector3.ZERO
    for _frame: int in range(3):
        await process_frame

    var nearest := runtime.call("nearest_talkable") as Node3D
    if not _expect(nearest != null, "nearby production pedestrian was not talkable"):
        return
    if not _expect(player.global_position.distance_to(nearest.global_position) <= 6.0, "talkable pedestrian escaped interaction range"):
        return

    if not _expect(bool(runtime.call("open_for_npc", nearest)), "dialogue panel refused production pedestrian"):
        return
    if not _expect(bool(runtime.call("is_dialogue_open")), "dialogue panel did not open"):
        return
    if not _expect(bool(nearest.get_meta("dialogue_hold", false)), "target pedestrian did not pause for conversation"):
        return
    if not _expect(str(runtime.call("displayed_source")) == "BAKE OFFLINE", "opening line did not prove baked fallback"):
        return
    if not _expect(not str(runtime.call("displayed_line")).is_empty(), "baked opening line is empty"):
        return

    var llm: Dictionary = runtime.call(
        "inject_model_text_for_test",
        "Salut, ça va ?",
        "action: idle\nline: Salut, tu vas bien ?",
        _calm_blackboard()
    )
    if not _expect(bool(llm.get("accepted", false)), "valid model proposal was rejected by visible interaction"):
        return
    if not _expect(str(runtime.call("displayed_source")) == "LLM LOCAL", "visible source did not switch to local LLM"):
        return
    if not _expect(str(runtime.call("displayed_line")) == "Salut, tu vas bien ?", "visible LLM line changed"):
        return

    var illegal: Dictionary = runtime.call(
        "inject_model_text_for_test",
        "Tu veux te battre ?",
        "action: fight\nline: Viens te battre.",
        _calm_blackboard()
    )
    if not _expect(not bool(illegal.get("accepted", true)), "fight escaped calm blackboard rules"):
        return
    if not _expect(str(illegal.get("source", "")) == "fallback", "illegal fight did not use baked fallback"):
        return
    if not _expect(str(runtime.call("displayed_source")) == "BAKE OFFLINE", "illegal fight did not visibly fall back"):
        return

    var walk: Dictionary = runtime.call(
        "inject_model_text_for_test",
        "Tu dois y aller ?",
        "action: walk\nline: Oui, je dois y aller.",
        _calm_blackboard()
    )
    if not _expect(bool(walk.get("accepted", false)), "calm walk action was rejected"):
        return
    if not _expect(not bool(nearest.get_meta("dialogue_hold", true)), "walk did not release the pedestrian"):
        return

    runtime.call("close_dialogue")
    if not _expect(not bool(runtime.call("is_dialogue_open")), "dialogue panel did not close"):
        return
    if not _expect(not bool(nearest.get_meta("dialogue_hold", true)), "pedestrian remained frozen after close"):
        return

    if "capture=1" in OS.get_cmdline_user_args():
        player.global_position = nearest.global_position + Vector3(0.0, 0.0, 2.0)
        player.velocity = Vector3.ZERO
        await process_frame
        runtime.call("open_for_npc", nearest)
        runtime.call(
            "inject_model_text_for_test",
            "Salut, ça va ?",
            "action: idle\nline: Salut, tu vas bien ?",
            _calm_blackboard()
        )
        for _frame: int in range(10):
            await process_frame
        DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/visual"))
        var image := root.get_viewport().get_texture().get_image()
        var save_result := image.save_png("res://artifacts/visual/npc_dialogue_visible_1280x720.png")
        if save_result != OK:
            _fail("dialogue witness save failed: %s" % save_result)
            return
        print("NPC_DIALOGUE_VISIBLE_WITNESS_OK: 1280x720")

    print("NPC_DIALOGUE_VISIBLE_OK: production_pedestrian=true bake=true llm=true illegal_fight_fallback=true")
    quit(0)
