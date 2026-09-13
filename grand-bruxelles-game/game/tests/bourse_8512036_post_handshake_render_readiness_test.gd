extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const SOURCE_SHA256 := "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_post_handshake_render_readiness.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_POST_HANDSHAKE_RENDER_READINESS_FAIL: %s" % message)
    quit(1)

func _write_receipt(receipt: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open(RECEIPT_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(receipt, "  ") + "\n")
    file.close()
    return true

func _run() -> void:
    var scene := MAIN_SCENE.instantiate()
    root.add_child(scene)
    for _frame: int in range(36):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("authoritative player unavailable")
        return

    var resolver := RESOLVER_SCRIPT.new()
    scene.add_child(resolver)

    # Production readiness must be measured after the resolver/streaming
    # handshake. The previous global probe sampled render state before this call.
    var rendered_before := bool(resolver.call("_road_is_rendered", scene, ROAD_ID))
    if not bool(resolver.call("apply_to_player", player, ROAD_ID)):
        _fail("shared road resolver rejected source-backed Bourse winner")
        return

    for _frame: int in range(12):
        await process_frame
        await physics_frame

    var rendered_after := bool(resolver.call("_road_is_rendered", scene, ROAD_ID))
    if not rendered_after:
        _fail("road-8512036 is not production-rendered after resolver/streaming handshake")
        return

    var osm_id_value: Variant = player.get_meta("automatic_road_direct_osm_id", null)
    if typeof(osm_id_value) != TYPE_INT or osm_id_value != ROAD_ID:
        _fail("requested OSM identity missing, non-canonical or drifted")
        return

    var lookup_value: Variant = player.get_meta("automatic_road_direct_lookup_mode", null)
    if typeof(lookup_value) != TYPE_STRING or lookup_value != "deterministic_runtime_index":
        _fail("deterministic runtime-index lookup missing or non-canonical")
        return

    var source_path_value: Variant = player.get_meta("automatic_road_direct_source_path", null)
    if typeof(source_path_value) != TYPE_STRING or source_path_value != SOURCE_PATH:
        _fail("post-handshake source path drifted from locked OSM document")
        return

    var source_sha_value: Variant = player.get_meta("automatic_road_direct_source_sha256", null)
    if typeof(source_sha_value) != TYPE_STRING or source_sha_value != SOURCE_SHA256:
        _fail("post-handshake source SHA-256 drifted from locked OSM bytes")
        return

    var ground_value: Variant = player.get_meta("automatic_road_direct_ground_y", null)
    if typeof(ground_value) != TYPE_FLOAT and typeof(ground_value) != TYPE_INT:
        _fail("collision-backed ground metadata is not numeric")
        return
    var ground_y := float(ground_value)
    if not is_finite(ground_y):
        _fail("finite collision-backed ground missing")
        return

    var sightline_value: Variant = player.get_meta("automatic_road_direct_source_sightline_clear", null)
    if typeof(sightline_value) != TYPE_BOOL or sightline_value != true:
        _fail("source-backed sightline is not exact boolean true")
        return

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-post-handshake-render-readiness-v2",
        "road_osm_id": ROAD_ID,
        "request": "road-%d" % ROAD_ID,
        "render_predicate": "automatic_road_direct_spawn._road_is_rendered",
        "rendered_before_handshake": rendered_before,
        "resolver_applied": true,
        "stabilization_frames": 12,
        "rendered_after_handshake": rendered_after,
        "post_handshake_render_required": true,
        "lookup_mode": lookup_value,
        "source_path": source_path_value,
        "source_sha256": source_sha_value,
        "locked_source_identity_required": true,
        "exact_metadata_types_required": true,
        "ground_y": ground_y,
        "source_sightline_clear": true,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write_receipt(receipt):
        _fail("unable to persist post-handshake readiness receipt")
        return

    print("BOURSE_8512036_POST_HANDSHAKE_RENDER_READINESS_OK rendered_before=%s rendered_after=true source_identity_locked=true exact_metadata_types=true ground_y=%.6f destination_advertisable=false" % [str(rendered_before), ground_y])
    quit(0)
