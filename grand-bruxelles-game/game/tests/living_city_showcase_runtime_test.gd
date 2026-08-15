extends SceneTree

var _failed := false

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene missing")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    current_scene = scene
    for _frame: int in range(8):
        await process_frame

    var visible_runtime := root.get_node_or_null("VisibleCityRuntime")
    var showcase := root.get_node_or_null("LivingCityShowcaseRuntime")
    if visible_runtime == null or showcase == null:
        _fail("living-city autoloads missing")
        return

    visible_runtime.call("ensure_zone_for_test", "midi")
    for _frame: int in range(6):
        await process_frame

    if not bool(showcase.call("trigger_showcase_for_test", "midi")):
        _fail("showcase could not trigger on the shipped Midi population")
        return
    for _frame: int in range(4):
        await process_frame
        await physics_frame

    var state: Dictionary = showcase.call("showcase_state_for_test")
    if not bool(state.get("bound", false)):
        _fail("showcase runtime did not bind to the real scene")
        return
    if int(state.get("trigger_count", 0)) != 1:
        _fail("showcase did not trigger exactly once")
        return
    if str(state.get("zone", "")) != "midi":
        _fail("showcase did not remain scoped to Midi")
        return
    if not bool(state.get("subject_valid", false)) or bool(state.get("subject_is_player", true)):
        _fail("street incident subject must be a real civilian NPC, never the player")
        return
    if int(state.get("subject_state", -1)) != NpcBehaviorModel.State.FLEEING:
        _fail("showcase subject did not visibly flee")
        return
    if int(state.get("responding_police", 0)) < 1:
        _fail("showcase did not activate a visible police response")
        return
    if int(state.get("reacting_civilians", 0)) < 1:
        _fail("showcase did not produce a bystander reaction")
        return

    var hud_text := str(visible_runtime.call("status_text_for_test"))
    if not hud_text.contains("INCIDENT DE RUE"):
        _fail("existing player-facing status did not expose the street intervention")
        return

    var subject_nodes := get_nodes_in_group("behavioral_civilian")
    var tagged_subjects := 0
    for node: Node in subject_nodes:
        if node.has_meta("living_city_showcase_subject"):
            tagged_subjects += 1
    if tagged_subjects != 1:
        _fail("showcase must mark exactly one civilian subject")
        return

    print("LIVING_CITY_SHOWCASE_OK: zone=%s fleeing_subject=true bystanders=%d responders=%d" % [
        str(state.get("zone", "")),
        int(state.get("reacting_civilians", 0)),
        int(state.get("responding_police", 0)),
    ])
    quit(0)

func _fail(message: String) -> void:
    if _failed:
        return
    _failed = true
    push_error(message)
    print("LIVING_CITY_SHOWCASE_FAIL: %s" % message)
    quit(1)
