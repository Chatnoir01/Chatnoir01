extends SceneTree

const RUNTIME_SCRIPT := preload("res://game/scripts/anneessens_osm_furniture_runtime.gd")
const MAIN_SCENE := preload("res://game/main.tscn")
const ANNEESSENS := Vector3(-272.04, 0.0, -217.07)

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    var scene := MAIN_SCENE.instantiate() as Node3D
    if scene == null:
        _fail("canonical main scene did not instantiate")
        return
    root.add_child(scene)

    var canonical_player := scene.get_node_or_null("Player") as Node3D
    if canonical_player == null:
        _fail("canonical Main/Player missing")
        return
    canonical_player.position = ANNEESSENS

    var runtime := RUNTIME_SCRIPT.new()
    runtime.name = "AnneessensOsmPlayerPathReconciliationProbe"
    root.add_child(runtime)
    runtime.call("bind_scene", scene)
    for _frame: int in range(4):
        await process_frame

    if int(runtime.call("tree_count")) != 7 or not bool(runtime.call("is_active")):
        _fail("precondition failed: source-backed Anneessens trees were not active")
        return

    # Keep the old Player valid and inside SceneTree, but remove its canonical
    # Main/Player ownership. A cached-instance-only runtime must fail this probe.
    var quarantine := Node3D.new()
    quarantine.name = "PlayerQuarantine"
    root.add_child(quarantine)
    scene.remove_child(canonical_player)
    quarantine.add_child(canonical_player)
    canonical_player.position = ANNEESSENS

    await process_frame
    await process_frame

    if scene.get_node_or_null("Player") != null:
        _fail("canonical Player path unexpectedly survived quarantine")
        return
    if bool(runtime.call("is_active")):
        _fail("runtime consumed stale cached Player after Main/Player ownership was lost")
        return

    var replacement := Node3D.new()
    replacement.name = "Player"
    replacement.position = ANNEESSENS
    scene.add_child(replacement)
    await process_frame
    await process_frame

    if not bool(runtime.call("is_active")):
        _fail("runtime did not reacquire replacement canonical Main/Player")
        return
    if int(runtime.call("tree_count")) != 7:
        _fail("Player reconciliation changed source-backed tree count")
        return

    print("ANNEESSENS_OSM_PLAYER_PATH_RECONCILIATION_OK: stale_cached_player_rejected=true replacement_reacquired=true trees=7")
    quit(0)

func _fail(message: String) -> void:
    push_error(message)
    quit(1)
