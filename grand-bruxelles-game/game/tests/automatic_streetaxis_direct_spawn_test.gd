extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_streetaxis_direct_spawn.gd")
const COLLISION_READY_ID := 70526
const VISUAL_ONLY_ID := 70488
const COLLISION_READY_CELL := "bxl-e149000-n169000-s500"
const VISUAL_ONLY_CELL := "bxl-e149000-n169500-s500"


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_STREETAXIS_DIRECT_SPAWN_FAIL: %s" % message)
    quit(1)


func _find_streamer(node: Node) -> BrusselsWorldStreamingRuntime:
    if node is BrusselsWorldStreamingRuntime:
        return node as BrusselsWorldStreamingRuntime
    for child: Node in node.get_children():
        var found := _find_streamer(child)
        if found != null:
            return found
    return null


func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(12):
        await process_frame
        await physics_frame

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player missing")
        return

    var resolver := RESOLVER_SCRIPT.new() as StreetAxisDestinationResolver
    root.add_child(resolver)
    if resolver.requested_streetaxis_id(PackedStringArray(["spawn=streetaxis-70526"])) != COLLISION_READY_ID:
        _fail("valid StreetAxis request did not parse")
        return
    for malformed: String in ["spawn=streetaxis-", "spawn=streetaxis-zero", "spawn=streetaxis--1", "spawn=streetaxis-0", "spawn=x=827&z=903", "spawn=road-70526"]:
        if resolver.requested_streetaxis_id(PackedStringArray([malformed])) != 0:
            _fail("malformed or foreign request accepted: %s" % malformed)
            return

    var ready_source := resolver.resolve_streetaxis(COLLISION_READY_ID)
    if ready_source.is_empty():
        _fail("collision-ready StreetAxis source did not resolve")
        return
    if str(ready_source.get("cell_id", "")) != COLLISION_READY_CELL:
        _fail("collision-ready StreetAxis mapped to wrong cell")
        return
    if str(ready_source.get("street_fr", "")) != "Rue du Prince Royal" or str(ready_source.get("street_nl", "")) != "Koninklijke-Prinsstraat":
        _fail("collision-ready StreetAxis bilingual identity drifted")
        return
    if not bool(ready_source.get("destination_collision_authorized", false)):
        _fail("collision-ready StreetAxis lost explicit collision authorization")
        return

    var visual_source := resolver.resolve_streetaxis(VISUAL_ONLY_ID)
    if visual_source.is_empty() or str(visual_source.get("cell_id", "")) != VISUAL_ONLY_CELL:
        _fail("visual-only control StreetAxis did not resolve to expected cell")
        return
    if bool(visual_source.get("destination_collision_authorized", true)):
        _fail("visual-only control was incorrectly collision-authorized")
        return

    var original_position := player.global_position
    var rejected := await resolver.apply_streetaxis_to_player(player, VISUAL_ONLY_ID, 1000)
    if bool(rejected.get("ok", false)) or str(rejected.get("reason", "")) != "cell_collision_not_authorized":
        _fail("visual-only StreetAxis did not fail closed")
        return
    if player.global_position.distance_to(original_position) > 0.001:
        _fail("visual-only rejected destination moved player")
        return

    var accepted := await resolver.apply_streetaxis_to_player(player, COLLISION_READY_ID, 60000)
    if not bool(accepted.get("ok", false)):
        _fail("collision-ready StreetAxis failed: %s" % str(accepted.get("reason", "unknown")))
        return
    if player.global_position.distance_to(original_position) < 10.0:
        _fail("accepted streamed destination did not move player")
        return
    if int(player.get_meta("automatic_streetaxis_direct_id", 0)) != COLLISION_READY_ID:
        _fail("StreetAxis provenance metadata missing")
        return
    if str(player.get_meta("automatic_streetaxis_direct_cell_id", "")) != COLLISION_READY_CELL:
        _fail("streamed cell provenance metadata missing")
        return
    if not str(player.get_meta("automatic_streetaxis_direct_network_path", "")).ends_with("/runtime/network.game.json"):
        _fail("runtime network provenance path missing")
        return
    if not bool(player.get_meta("automatic_streetaxis_direct_collision_authorized", false)) or not bool(player.get_meta("automatic_streetaxis_direct_streaming_ready", false)):
        _fail("playability readiness metadata missing")
        return
    var ground_y := float(player.get_meta("automatic_streetaxis_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("authoritative DTM ground height missing")
        return

    var streamer := _find_streamer(main)
    if streamer == null or not streamer.runtime_ready:
        _fail("shared world streamer missing after destination")
        return
    if not streamer.manager.is_collision_active(COLLISION_READY_CELL):
        _fail("collision was lost after normal streaming handoff")
        return
    if streamer.manager.is_collision_pinned(COLLISION_READY_CELL):
        _fail("destination collision pin leaked after handoff")
        return
    var instance := streamer.get_destination_instance(COLLISION_READY_CELL)
    if instance == null or not instance.has_method("is_streamed_collision_enabled") or not bool(instance.call("is_streamed_collision_enabled")):
        _fail("streamed destination instance collision not enabled")
        return
    if instance.get_node_or_null("OfficialIxellesDTMCollision") == null:
        _fail("official DTM collision body missing")
        return

    for _frame: int in range(3):
        await process_frame
        await physics_frame
    var image := root.get_viewport().get_texture().get_image()
    if image.get_width() != 1280 or image.get_height() != 720:
        _fail("player witness is not 1280x720")
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/streetaxis"))
    var screenshot_path := "res://artifacts/streetaxis/streetaxis_70526_stream_spawn.png"
    if image.save_png(screenshot_path) != OK:
        _fail("could not save player witness")
        return

    print("AUTOMATIC_STREETAXIS_DIRECT_SPAWN_GREEN: id=%d cell=%s street=%s/%s ground_y=%.3f visual_only_rejected=%d screenshot=%s" % [COLLISION_READY_ID, COLLISION_READY_CELL, str(ready_source["street_fr"]), str(ready_source["street_nl"]), ground_y, VISUAL_ONLY_ID, screenshot_path])
    quit(0)
