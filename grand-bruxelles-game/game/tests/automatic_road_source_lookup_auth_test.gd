extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const AUTOMATIC_ROAD_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const UNKNOWN_OSM_ID := 2147483647

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_LOOKUP_AUTH_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var resolver := AUTOMATIC_ROAD_SCRIPT.new()
    if resolver.runtime_index_road_count() <= 0:
        _fail("locked source runtime index is unavailable")
        return
    if not resolver.has_method("runtime_index_playable_authorized"):
        _fail("resolver exposes no source-registry authorization diagnostic")
        return
    if bool(resolver.call("runtime_index_playable_authorized")):
        _fail("source_lookup_only index was incorrectly advertised as a playable catalog")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(8):
        await process_frame
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing")
        return
    var before := player.global_position
    if resolver.apply_to_player(player, UNKNOWN_OSM_ID):
        _fail("unknown road bypassed deterministic source/runtime readiness gates")
        return
    if player.global_position.distance_to(before) > 0.001:
        _fail("refused unknown direct-entry request still changed player position")
        return

    print("AUTOMATIC_ROAD_SOURCE_LOOKUP_AUTH_OK: source_lookup_only=true playable_catalog=false unknown_osm_id=%d fail_closed=true player_unchanged=true" % UNKNOWN_OSM_ID)
    quit(0)
