extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const CATALOG_PATH := "res://data/provenance/brussels_road_destination_readiness_catalog.json"
const OUTPUT_PATH := "res://artifacts/road-destination-readiness/runtime-probe.json"
const REQUIRED_GRAND_PLACE_APPROACH := 13842686
const REQUIRED_BOURSE_LEGACY_APPROACH := 411724192
const REQUIRED_BOURSE_AUTOMATIC_WINNER := 8512036
const RENDER_DECOY_OSM_ID := 9007199254740001


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("ROAD_DESTINATION_RUNTIME_PROBE_FAIL: %s" % message)
    quit(1)


func _catalog() -> Dictionary:
    if not FileAccess.file_exists(CATALOG_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
    return parsed as Dictionary if parsed is Dictionary else {}


func _rendered(resolver: Node, world: Node, osm_id: int) -> bool:
    # Readiness evidence must use the exact production predicate. Duplicating a
    # weaker test-side renderer check can create false RUNTIME_READY witnesses.
    return bool(resolver.call("_road_is_rendered", world, osm_id))


func _write_result(payload: Dictionary) -> bool:
    var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
    var parent := absolute.get_base_dir()
    var mkdir_error := DirAccess.make_dir_recursive_absolute(parent)
    if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
        return false
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(payload, "  ") + "\n")
    file.close()
    return true


func _run() -> void:
    var catalog := _catalog()
    if catalog.is_empty():
        _fail("readiness catalog missing or invalid")
        return
    if str(catalog.get("schema", "")) != "grand-bruxelles-road-destination-readiness-catalog-v1":
        _fail("unexpected catalog schema")
        return
    if str(catalog.get("status", "")) != "SOURCE_BACKED_REGISTERED_NOT_RENDERED":
        _fail("catalog status must remain evidence-only REGISTERED_NOT_RENDERED")
        return
    var authorization: Variant = catalog.get("authorization", {})
    if not authorization is Dictionary:
        _fail("catalog authorization missing")
        return
    for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
        if bool((authorization as Dictionary).get(forbidden, true)):
            _fail("catalog self-authorized forbidden readiness: %s" % forbidden)
            return

    var raw_destinations: Variant = catalog.get("destinations", [])
    if not raw_destinations is Array or raw_destinations.is_empty():
        _fail("catalog destinations missing")
        return
    if int(catalog.get("destination_count", 0)) != (raw_destinations as Array).size():
        _fail("catalog destination count drifted")
        return

    # Keep the historical Bourse approach covered, but also require the
    # deterministic automatic Bourse winner so the global readiness chain
    # cannot regress to validating only the legacy hand-selected road.
    var required_ids := {
        REQUIRED_GRAND_PLACE_APPROACH: false,
        REQUIRED_BOURSE_LEGACY_APPROACH: false,
        REQUIRED_BOURSE_AUTOMATIC_WINNER: false,
    }
    for raw_row: Variant in raw_destinations:
        if raw_row is Dictionary:
            var candidate_id := int((raw_row as Dictionary).get("road_osm_id", 0))
            if required_ids.has(candidate_id):
                required_ids[candidate_id] = true
    for required_id: int in required_ids:
        if not bool(required_ids[required_id]):
            _fail("required corridor approach missing from locked catalog: road-%d" % required_id)
            return

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

    # Regression guard: a name-only decoy is not rendered geometry. This probe
    # now delegates to production semantics so future readiness checks cannot
    # drift back to accepting arbitrary Road_<id>_* node names.
    var render_decoy := Node3D.new()
    render_decoy.name = "Road_%d_NameOnlyDecoy" % RENDER_DECOY_OSM_ID
    main.add_child(render_decoy)
    if _rendered(resolver, main, RENDER_DECOY_OSM_ID):
        _fail("shared production render predicate accepted name-only decoy")
        return

    var original_position := player.global_position
    var observations: Array[Dictionary] = []
    var runtime_ready_count := 0
    var rendered_count := 0
    var resolver_applied_count := 0

    for raw_row: Variant in raw_destinations:
        if not raw_row is Dictionary:
            _fail("catalog destination row is not an object")
            return
        var row := raw_row as Dictionary
        var osm_id := int(row.get("road_osm_id", 0))
        var destination_id := str(row.get("destination_id", ""))
        var road_name := str(row.get("road_name", "")).strip_edges()
        var source_sha := str(row.get("source_sha256", "")).to_lower()
        if osm_id <= 0 or destination_id != "road-%d" % osm_id or road_name.is_empty() or source_sha.length() != 64:
            _fail("invalid catalog destination identity: %s" % destination_id)
            return
        for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
            if bool(row.get(forbidden, true)):
                _fail("destination self-authorized forbidden readiness: %s %s" % [destination_id, forbidden])
                return

        player.global_position = original_position
        player.velocity = Vector3.ZERO
        await physics_frame

        var rendered := _rendered(resolver, main, osm_id)
        var applied := resolver.apply_to_player(player, osm_id)
        var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF)) if applied else INF
        var ground_ready := applied and is_finite(ground_y)
        var sightline_clear := applied and bool(player.get_meta("automatic_road_direct_source_sightline_clear", false))
        var identity_match := applied and int(player.get_meta("automatic_road_direct_osm_id", 0)) == osm_id and str(player.get_meta("automatic_road_direct_source_name", "")) == road_name
        var source_sha_match := applied and str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() == source_sha
        var lookup_mode := str(player.get_meta("automatic_road_direct_lookup_mode", "")) if applied else ""
        var runtime_ready := rendered and applied and ground_ready and sightline_clear and identity_match and source_sha_match and lookup_mode == "deterministic_runtime_index"

        if rendered:
            rendered_count += 1
        if applied:
            resolver_applied_count += 1
        if runtime_ready:
            runtime_ready_count += 1

        observations.append({
            "destination_id": destination_id,
            "road_osm_id": osm_id,
            "road_name": road_name,
            "cell_id": str(row.get("cell_id", "")),
            "rendered": rendered,
            "resolver_applied": applied,
            "ground_ready": ground_ready,
            "ground_y": ground_y if ground_ready else null,
            "source_sightline_clear": sightline_clear,
            "source_identity_match": identity_match,
            "source_sha256_match": source_sha_match,
            "lookup_mode": lookup_mode,
            "runtime_ready_witness": runtime_ready,
            "readiness_observed": "RUNTIME_READY_WITNESS" if runtime_ready else ("RENDERED_RESOLVER_NOT_READY" if rendered else "REGISTERED_NOT_RENDERED"),
            "playability_claimed": false,
            "destination_advertisable": false,
            "jouable_authorized": false,
        })

    player.global_position = original_position
    player.velocity = Vector3.ZERO

    var payload := {
        "schema": "grand-bruxelles-road-destination-runtime-probe-v1",
        "catalog_schema": str(catalog.get("schema", "")),
        "catalog_semantic_sha256": str(catalog.get("semantic_sha256", "")),
        "catalog_sha256": FileAccess.get_sha256(CATALOG_PATH).to_lower(),
        "destination_count": observations.size(),
        "rendered_count": rendered_count,
        "resolver_applied_count": resolver_applied_count,
        "runtime_ready_witness_count": runtime_ready_count,
        "required_corridor_approaches": [REQUIRED_BOURSE_LEGACY_APPROACH, REQUIRED_BOURSE_AUTOMATIC_WINNER, REQUIRED_GRAND_PLACE_APPROACH],
        "render_predicate": "automatic_road_direct_spawn._road_is_rendered",
        "render_predicate_shared_with_production": true,
        "name_only_render_decoy_rejected": true,
        "automatic_bourse_winner_required": true,
        "observations": observations,
        "measurement_only": true,
        "catalog_mutated": false,
        "playability_claimed": false,
        "destination_advertisable": false,
        "jouable_authorized": false,
    }
    if not _write_result(payload):
        _fail("unable to persist runtime readiness probe")
        return

    print("ROAD_DESTINATION_RUNTIME_PROBE_OK destinations=%d rendered=%d resolver_applied=%d runtime_ready=%d playability_claimed=false" % [observations.size(), rendered_count, resolver_applied_count, runtime_ready_count])
    quit(0)