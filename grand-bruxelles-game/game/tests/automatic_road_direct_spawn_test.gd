extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const SOURCE_SHA256 := "a96123a6098c2a94dcef2622b6ea099c831f426e1ebfeb28a2edda74675c2493"
const LEMONNIER_ID := 359177328


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_DIRECT_SPAWN_FAIL: %s" % message)
    quit(1)


func _document() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    return parsed as Dictionary if parsed is Dictionary else {}


func _rendered(world: Node, osm_id: int) -> bool:
    var prefix := "Road_%d_" % osm_id
    var stack: Array[Node] = [world]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if str(node.name).begins_with(prefix):
            return true
        for child: Node in node.get_children():
            stack.append(child)
    return false


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

    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)
    if resolver.runtime_index_road_count() != 139:
        _fail("deterministic runtime index road count drifted: %d" % resolver.runtime_index_road_count())
        return
    if resolver.runtime_index_source_document_count() != 1:
        _fail("deterministic runtime index source document count drifted")
        return
    var actual_source_sha := FileAccess.get_sha256(SOURCE_PATH).to_lower()
    if actual_source_sha != SOURCE_SHA256:
        _fail("source SHA no longer matches generated runtime index actual=%s expected=%s" % [actual_source_sha, SOURCE_SHA256])
        return
    if resolver.requested_road_id(PackedStringArray(["spawn=road-359177328"])) != LEMONNIER_ID:
        _fail("valid road request did not parse")
        return
    for malformed: String in ["spawn=road-", "spawn=road-zero", "spawn=road--1", "spawn=x=1", "spawn=road-0"]:
        if resolver.requested_road_id(PackedStringArray([malformed])) != 0:
            _fail("malformed request accepted: %s" % malformed)
            return

    var original_position := player.global_position
    if resolver.apply_to_player(player, 999999999):
        _fail("unknown road was accepted")
        return
    if player.global_position.distance_to(original_position) > 0.001:
        _fail("unknown road moved the player")
        return

    if not _rendered(main, LEMONNIER_ID):
        _fail("known Lemonnier road is not rendered in production scene")
        return
    if not resolver.apply_to_player(player, LEMONNIER_ID):
        _fail("indexed resolver refused rendered Lemonnier")
        return
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != LEMONNIER_ID:
        _fail("generic Lemonnier metadata missing")
        return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains("Maurice Lemonnier"):
        _fail("generic Lemonnier source identity missing")
        return
    if str(player.get_meta("automatic_road_direct_lookup_mode", "")) != "deterministic_runtime_index":
        _fail("road spawn did not use deterministic runtime index")
        return
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != SOURCE_SHA256:
        _fail("road spawn source SHA proof missing")
        return

    var document := _document()
    if document.is_empty():
        _fail("vertical slice source missing")
        return
    var roads: Variant = document.get("roads", [])
    if not roads is Array:
        _fail("vertical slice roads missing")
        return

    var second_id := 0
    var second_name := ""
    for raw: Variant in roads:
        if not raw is Dictionary:
            continue
        var road := raw as Dictionary
        var osm_id := int(road.get("osm_id", 0))
        var name := str(road.get("name", "")).strip_edges()
        var points: Variant = road.get("points", [])
        if osm_id <= 0 or osm_id == LEMONNIER_ID or name.is_empty() or not bool(road.get("drivable", false)):
            continue
        if not points is Array or points.size() < 2 or not _rendered(main, osm_id):
            continue
        if resolver.apply_to_player(player, osm_id):
            second_id = osm_id
            second_name = name
            break

    if second_id <= 0:
        _fail("no second rendered source-backed road passed the indexed resolver")
        return
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != second_id:
        _fail("second generic road metadata missing")
        return
    if str(player.get_meta("automatic_road_direct_source_name", "")) != second_name:
        _fail("second generic road source identity drifted")
        return
    if str(player.get_meta("automatic_road_direct_lookup_mode", "")) != "deterministic_runtime_index":
        _fail("second road bypassed deterministic runtime index")
        return
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != SOURCE_SHA256:
        _fail("second road source SHA proof drifted")
        return

    var source_path := str(player.get_meta("automatic_road_direct_source_path", ""))
    if source_path != SOURCE_PATH:
        _fail("source path provenance drifted: %s" % source_path)
        return
    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("physics-backed ground height missing")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("source sightline gate missing")
        return

    print("AUTOMATIC_ROAD_DIRECT_SPAWN_GREEN: indexed_roads=%d source_documents=%d first=%d second=%d second_name=%s source=%s source_sha=%s ground_y=%.3f" % [resolver.runtime_index_road_count(), resolver.runtime_index_source_document_count(), LEMONNIER_ID, second_id, second_name, source_path, SOURCE_SHA256, ground_y])
    quit(0)
