extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const AUTOMATIC_ROAD_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const COVERAGE_PATH := "res://data/city_machine/road_cell_coverage_candidates.json"
const REPRESENTATIVE_OSM_ID := 359177328
const UNKNOWN_OSM_ID := 2147483647

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_SOURCE_LOOKUP_AUTH_FAIL: %s" % message)
    quit(1)

func _load_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}

func _run() -> void:
    var resolver := AUTOMATIC_ROAD_SCRIPT.new()
    if resolver.runtime_index_source_document_count() <= 0:
        _fail("locked source document registry is unavailable")
        return
    if resolver.runtime_index_road_count() <= 0:
        _fail("locked source runtime index is unavailable")
        return
    if not resolver.has_method("runtime_index_playable_authorized"):
        _fail("resolver exposes no source-registry authorization diagnostic")
        return
    if bool(resolver.call("runtime_index_playable_authorized")):
        _fail("source_lookup_only index was incorrectly advertised as a playable catalog")
        return
    if not resolver.has_method("source_bundle_for_test"):
        _fail("resolver exposes no fail-closed source binding diagnostic")
        return

    var coverage := _load_json(COVERAGE_PATH)
    if coverage.is_empty() or str(coverage.get("schema", "")) != "grand-bruxelles-road-cell-coverage-candidates-v2":
        _fail("durable road coverage source lock is unavailable")
        return
    if str(coverage.get("status", "")) != "DISCOVERED_SOURCE_ONLY":
        _fail("road coverage lock is not source-only")
        return
    for forbidden: String in ["road_cell_mapping_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"]:
        if bool(coverage.get(forbidden, true)):
            _fail("road coverage lock opened forbidden rail %s" % forbidden)
            return

    var bundle: Dictionary = resolver.call("source_bundle_for_test", REPRESENTATIVE_OSM_ID)
    if bundle.is_empty():
        _fail("representative indexed road cannot bind to current source evidence")
        return
    if str(bundle.get("lookup_mode", "")) != "deterministic_runtime_index_coverage_lock":
        _fail("resolver did not use the durable current-source binding")
        return
    if str(bundle.get("source_sha256", "")) != str(coverage.get("road_source_sha256", "")):
        _fail("resolver source SHA is not bound to the current Data lock")
        return
    if str(bundle.get("road_semantic_sha256", "")) != str(coverage.get("road_semantic_sha256", "")):
        _fail("resolver road semantic identity is not bound to the Data lock")
        return
    if not (resolver.call("source_bundle_for_test", UNKNOWN_OSM_ID) as Dictionary).is_empty():
        _fail("unknown road bypassed deterministic index membership")
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

    print("AUTOMATIC_ROAD_SOURCE_LOOKUP_AUTH_OK: source_documents=%d source_lookup_only=true playable_catalog=false representative_osm_id=%d current_source_bound=true unknown_osm_id=%d fail_closed=true player_unchanged=true" % [resolver.runtime_index_source_document_count(), REPRESENTATIVE_OSM_ID, UNKNOWN_OSM_ID])
    quit(0)
