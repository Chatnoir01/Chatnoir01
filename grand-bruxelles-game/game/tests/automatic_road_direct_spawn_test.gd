extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const RUNTIME_INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"
const RUNTIME_INDEX_FORMAT := "grand-bruxelles-road-runtime-index-v1"
const LEMONNIER_ID := 359177328
const POISSONNIERS_ID := 12357557


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_DIRECT_SPAWN_FAIL: %s" % message)
    quit(1)


func _document() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    return parsed as Dictionary if parsed is Dictionary else {}


func _runtime_index_contract() -> Dictionary:
    if not FileAccess.file_exists(RUNTIME_INDEX_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(RUNTIME_INDEX_PATH))
    if not parsed is Dictionary:
        return {}
    var index := parsed as Dictionary
    if str(index.get("format", "")) != RUNTIME_INDEX_FORMAT or not bool(index.get("source_lookup_only", false)):
        return {}
    var authorization: Variant = index.get("authorization", {})
    if not authorization is Dictionary:
        return {}
    var auth := authorization as Dictionary
    if not bool(auth.get("source_lookup_only", false)):
        return {}
    for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
        if bool(auth.get(forbidden, true)):
            return {}

    var documents: Variant = index.get("documents", [])
    if not documents is Array or documents.is_empty():
        return {}
    var source_relative := SOURCE_PATH.trim_prefix("res://")
    for raw_document: Variant in documents:
        if not raw_document is Dictionary:
            return {}
        var descriptor := raw_document as Dictionary
        if str(descriptor.get("path", "")) != source_relative:
            continue
        var expected_sha := str(descriptor.get("sha256", "")).strip_edges().to_lower()
        var road_ids: Variant = descriptor.get("road_ids", [])
        if expected_sha.length() != 64 or not road_ids is Array or road_ids.is_empty():
            return {}
        var normalized_road_ids: Dictionary = {}
        for raw_id: Variant in road_ids:
            var osm_id := int(raw_id)
            if osm_id <= 0 or normalized_road_ids.has(osm_id):
                return {}
            normalized_road_ids[osm_id] = true
        if not normalized_road_ids.has(LEMONNIER_ID) or not normalized_road_ids.has(POISSONNIERS_ID):
            return {}
        return {
            "source_sha256": expected_sha,
            "road_count": normalized_road_ids.size(),
            "document_count": documents.size(),
        }
    return {}


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

    var index_contract := _runtime_index_contract()
    if index_contract.is_empty():
        _fail("deterministic runtime index contract missing or invalid")
        return
    var expected_source_sha := str(index_contract.get("source_sha256", ""))
    var expected_road_count := int(index_contract.get("road_count", 0))
    var expected_document_count := int(index_contract.get("document_count", 0))
    var actual_source_sha := FileAccess.get_sha256(SOURCE_PATH).to_lower()
    if actual_source_sha != expected_source_sha:
        _fail("source SHA no longer matches generated runtime index: actual=%s expected=%s" % [actual_source_sha, expected_source_sha])
        return

    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)
    if resolver.runtime_index_road_count() != expected_road_count:
        _fail("deterministic runtime index road count drifted: resolver=%d index=%d" % [resolver.runtime_index_road_count(), expected_road_count])
        return
    if resolver.runtime_index_source_document_count() != expected_document_count:
        _fail("deterministic runtime index source document count drifted: resolver=%d index=%d" % [resolver.runtime_index_source_document_count(), expected_document_count])
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
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != expected_source_sha:
        _fail("road spawn source SHA proof missing")
        return

    # RED-first regression: automatic road grounding must only trust the
    # canonical generic OSM road-support layer (layer 20). A foreign prop or
    # blocker above the road must never become the direct-entry ground.
    var lemmonnier_ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(lemmonnier_ground_y):
        _fail("Lemonnier physics-backed ground height missing")
        return
    var decoy := StaticBody3D.new()
    decoy.name = "ForeignRoadGroundDecoy"
    decoy.collision_layer = 1
    decoy.collision_mask = 0
    var decoy_shape := CollisionShape3D.new()
    var decoy_box := BoxShape3D.new()
    decoy_box.size = Vector3(4.0, 0.5, 4.0)
    decoy_shape.shape = decoy_box
    decoy.add_child(decoy_shape)
    main.add_child(decoy)
    decoy.global_position = Vector3(player.global_position.x, lemmonnier_ground_y + 2.0, player.global_position.z)
    await physics_frame
    var guarded_ground_y := float(resolver._ground_y(player, Vector2(player.global_position.x, player.global_position.z)))
    main.remove_child(decoy)
    decoy.queue_free()
    await physics_frame
    if not is_finite(guarded_ground_y) or absf(guarded_ground_y - lemmonnier_ground_y) > 0.05:
        _fail("foreign collider captured automatic-road grounding: expected=%.3f actual=%.3f" % [lemmonnier_ground_y, guarded_ground_y])
        return

    # Regression for the exact #1291 runtime-probe exception. Poissonniers is
    # source-indexed and rendered; the resolver must decide it from the same
    # generic geometry/sightline/ground chain as every other road.
    if not _rendered(main, POISSONNIERS_ID):
        _fail("known Poissonniers road is not rendered in production scene")
        return
    if not resolver.apply_to_player(player, POISSONNIERS_ID):
        _fail("indexed resolver refused rendered Poissonniers")
        return
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != POISSONNIERS_ID:
        _fail("generic Poissonniers metadata missing")
        return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains("Poissonniers"):
        _fail("generic Poissonniers source identity missing")
        return
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != expected_source_sha:
        _fail("Poissonniers source SHA proof missing")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("Poissonniers source sightline proof missing")
        return
    var poissonniers_ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(poissonniers_ground_y):
        _fail("Poissonniers physics-backed ground height missing")
        return
    var poissonniers_alignment := float(player.get_meta("automatic_road_direct_axis_alignment", -1.0))
    if poissonniers_alignment < 0.90:
        _fail("Poissonniers source-axis alignment below 0.90: %.6f" % poissonniers_alignment)
        return
    print("AUTOMATIC_ROAD_POISSONNIERS_RUNTIME_READY_GREEN: osm_id=%d ground_y=%.3f axis_alignment=%.6f source_sha=%s" % [POISSONNIERS_ID, poissonniers_ground_y, poissonniers_alignment, expected_source_sha])

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
        if osm_id <= 0 or osm_id == LEMONNIER_ID or osm_id == POISSONNIERS_ID or name.is_empty() or not bool(road.get("drivable", false)):
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
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != expected_source_sha:
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

    print("AUTOMATIC_ROAD_RUNTIME_READY_GREEN: indexed_roads=%d source_documents=%d first=%d witness=%d witness_name=%s source=%s source_sha=%s ground_y=%.3f lookup=deterministic_runtime_index playability_claimed=false" % [expected_road_count, expected_document_count, LEMONNIER_ID, second_id, second_name, source_path, expected_source_sha, ground_y])
    print("AUTOMATIC_ROAD_PLAYER_WITNESS_HOLD: reason=character_visual_review_owned_separately qa_witness_accepted=false destination_advertisable=false jouable=false")
    quit(0)