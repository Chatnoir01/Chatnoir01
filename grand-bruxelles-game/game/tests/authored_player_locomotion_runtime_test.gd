extends SceneTree

const HUMANOID_VISUAL := preload("res://game/scripts/humanoid_visual.gd")
const LOCOMOTION_RUNTIME := preload("res://game/scripts/authored_player_locomotion_runtime.gd")

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AUTHORED_PLAYER_LOCOMOTION_FAIL: %s" % message)
    quit(1)

func _animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child: Node in node.get_children():
        var found := _animation_player(child)
        if found != null:
            return found
    return null

func _run() -> void:
    var actor := CharacterBody3D.new()
    actor.name = "Player"
    root.add_child(actor)

    var visual := HUMANOID_VISUAL.new()
    visual.name = "VisualUpgrade"
    actor.add_child(visual)
    await process_frame

    if not visual.is_using_authored_character():
        _fail("production Player did not load the authored fallback")
        return

    var player := _animation_player(visual)
    if player == null:
        _fail("authored Player has no AnimationPlayer")
        return

    var driver := LOCOMOTION_RUNTIME.new()
    root.add_child(driver)

    actor.velocity = Vector3.ZERO
    var idle := driver.drive_player(actor)
    if idle.is_empty() or "idle" not in idle.to_lower():
        _fail("idle velocity did not select an idle clip: %s" % idle)
        return

    actor.velocity = Vector3(2.4, 0.0, 0.0)
    var walk := driver.drive_player(actor)
    if walk.is_empty() or "walk" not in walk.to_lower():
        _fail("walking velocity did not select a walk clip: %s" % walk)
        return

    actor.velocity = Vector3(7.0, 0.0, 0.0)
    var run := driver.drive_player(actor)
    var run_lower := run.to_lower()
    if run.is_empty() or ("run" not in run_lower and "sprint" not in run_lower):
        _fail("running velocity did not select a run/sprint clip: %s" % run)
        return

    if idle == walk or walk == run or idle == run:
        _fail("locomotion states did not resolve distinct clips: idle=%s walk=%s run=%s" % [idle, walk, run])
        return

    if player.current_animation != run:
        _fail("AnimationPlayer did not actually enter the resolved run clip")
        return

    print("AUTHORED_PLAYER_LOCOMOTION_OK idle=%s walk=%s run=%s" % [idle, walk, run])
    quit(0)
