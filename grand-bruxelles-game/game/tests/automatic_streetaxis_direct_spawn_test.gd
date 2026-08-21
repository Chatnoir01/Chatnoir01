extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_streetaxis_direct_spawn.gd")
const SEED_READY_ID := 70526
const SECOND_READY_ID := 70488
const VISUAL_ONLY_ID := 100383
const SEED_READY_CELL := "bxl-e149000-n169000-s500"
const SECOND_READY_CELL := "bxl-e149000-n169500-s500"
const VISUAL_ONLY_CELL := "bxl-e149500-n169000-s500"

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

func _assert_visual_only_rejected(resolver: StreetAxisDestinationResolver, player: CharacterBody3D, original_position: Vector3) -> bool:
    var visual_source := resolver.resolve_streetaxis(VISUAL_ONLY_ID)
    if visual_source.is_empty() or str(visual_source.get("cell_id", "")) != VISUAL_ONLY_CELL:
        _fail("visual-only control StreetAxis did not resolve to expected cell")
        return false
    if bool(visual_source.get("destination_collision_authorized", true)):
        _fail("visual-only control was incorrectly collision-authorized")
        return false
    var rejected := await resolver.apply_streetaxis_to_player(player, VISUAL_ONLY_ID, 1000)
    if bool(rejected.get("ok", false)) or str(rejected.get("reason", "")) != "cell_collision_not_authorized":
        _fail("visual-only StreetAxis did not fail closed")
        return false
    if player.global_position.distance_to(original_position) > 0.001:
        _fail("visual-only rejected destination moved player")
        return false
    return true

func _assert_ready_destination(resolver: StreetAxisDestinationResolver, player: CharacterBody3D, streetaxis_id: int, expected_cell: String, expected_fr: String, expected_nl: String) -> Dictionary:
    var source := resolver.resolve_streetaxis(streetaxis_id)
    if source.is_empty():
        _fail("collision-ready StreetAxis source did not resolve: %d" % streetaxis_id)
        return {}
    if str(source.get("cell_id", "")) != expected_cell:
        _fail("collision-ready StreetAxis mapped to wrong cell: %d" % streetaxis_id)
        return {}
    if str(source.get("street_fr", "")) != expected_fr or str(source.get("street_nl", "")) != expected_nl:
        _fail("collision-ready StreetAxis bilingual identity drifted: %d" % streetaxis_id)
        return {}
    if not bool(source.get("destination_collision_authorized", false)):
        _fail("collision-ready StreetAxis lost explicit collision authorization: %d" % streetaxis_id)
        return {}

    var before := player.global_position
    var accepted := await resolver.apply_streetaxis_to_player(player, streetaxis_id, 60000)
    if not bool(accepted.get("ok", false)):
        _fail("collision-ready StreetAxis failed %d: %s" % [streetaxis_id, str(accepted.get("reason", "unknown"))])
        return {}
    if player.global_position.distance_to(before) < 10.0:
        _fail("accepted streamed destination did not move player: %d" % streetaxis_id)
        return {}
    if int(player.get_meta("automatic_streetaxis_direct_id", 0)) != streetaxis_id:
        _fail("StreetAxis provenance metadata missing: %d" % streetaxis_id)
        return {}
    if str(player.get_meta("automatic_streetaxis_direct_cell_id", "")) != expected_cell:
        _fail("streamed cell provenance metadata missing: %d" % streetaxis_id)
        return {}
    if not bool(player.get_meta("automatic_streetaxis_direct_collision_authorized", false)) or not bool(player.get_meta("automatic_streetaxis_direct_streaming_ready", false)):
        _fail("playability readiness metadata missing: %d" % streetaxis_id)
        return {}
    var ground_y := float(player.get_meta("automatic_streetaxis_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("authoritative DTM ground height missing: %d" % streetaxis_id)
        return {}

    var streamer := _find_streamer(root)
    if streamer == null or not streamer.runtime_ready:
        _fail("shared world streamer missing after destination")
        return {}
    if not streamer.manager.is_collision_active(expected_cell):
        _fail("collision was lost after normal streaming handoff: %s" % expected_cell)
        return {}
    if streamer.manager.is_collision_pinned(expected_cell):
        _fail("destination collision pin leaked after handoff: %s" % expected_cell)
        return {}
    var instance := streamer.get_destination_instance(expected_cell)
    if instance == null or not instance.has_method("is_streamed_collision_enabled") or not bool(instance.call("is_streamed_collision_enabled")):
        _fail("streamed destination instance collision not enabled: %s" % expected_cell)
        return {}
    if instance.get_node_or_null("OfficialIxellesDTMCollision") == null:
        _fail("official DTM collision body missing: %s" % expected_cell)
        return {}
    return {"source": source, "ground_y": ground_y}

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
    if resolver.requested_streetaxis_id(PackedStringArray(["spawn=streetaxis-70488"])) != SECOND_READY_ID:
        _fail("valid StreetAxis request did not parse")
        return
    for malformed: String in ["spawn=streetaxis-", "spawn=streetaxis-zero", "spawn=streetaxis--1", "spawn=streetaxis-0", "spawn=x=827&z=903", "spawn=road-70488"]:
        if resolver.requested_streetaxis_id(PackedStringArray([malformed])) != 0:
            _fail("malformed or foreign request accepted: %s" % malformed)
            return

    var original_position := player.global_position
    if not await _assert_visual_only_rejected(resolver, player, original_position):
        return

    var seed := await _assert_ready_destination(resolver, player, SEED_READY_ID, SEED_READY_CELL, "Rue du Prince Royal", "Koninklijke-Prinsstraat")
    if seed.is_empty():
        return
    var second := await _assert_ready_destination(resolver, player, SECOND_READY_ID, SECOND_READY_CELL, "Rue du Pépin", "Kernstraat")
    if second.is_empty():
        return

    for _frame: int in range(3):
        await process_frame
        await physics_frame
    var image := root.get_viewport().get_texture().get_image()
    if image.get_width() != 1280 or image.get_height() != 720:
        _fail("player witness is not 1280x720")
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/streetaxis"))
    var screenshot_path := "res://artifacts/streetaxis/streetaxis_70488_second_dtm_cell.png"
    if image.save_png(screenshot_path) != OK:
        _fail("could not save player witness")
        return

    print("AUTOMATIC_STREETAXIS_SECOND_DTM_CELL_GREEN: first=%d second=%d second_cell=%s second_ground_y=%.3f visual_only_rejected=%d screenshot=%s" % [SEED_READY_ID, SECOND_READY_ID, SECOND_READY_CELL, float(second["ground_y"]), VISUAL_ONLY_ID, screenshot_path])
    quit(0)
