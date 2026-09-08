extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const MIDI_ANCHOR_ID := "midi"
const MIDI_ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const MAX_MIDI_ANCHOR_DISTANCE_M := 80.0
const OUTPUT_PATH := "res://artifacts/qa/midi_automatic_road_blockers.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AUTOMATIC_ROAD_BLOCKER_ATTRIBUTION_FAIL: %s" % message)
    quit(1)

func _source_document() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    return parsed as Dictionary if parsed is Dictionary else {}

func _anchor(document: Dictionary) -> Vector2:
    var corridor: Variant = document.get("corridor", {})
    if not corridor is Dictionary:
        return Vector2(INF, INF)
    var anchors: Variant = (corridor as Dictionary).get("anchors", [])
    if not anchors is Array:
        return Vector2(INF, INF)
    for raw: Variant in anchors:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == MIDI_ANCHOR_ID:
            return Vector2(float((raw as Dictionary).get("x", INF)), float((raw as Dictionary).get("z", INF)))
    return Vector2(INF, INF)

func _points(road: Dictionary) -> Array[Vector2]:
    var result: Array[Vector2] = []
    var raw_points: Variant = road.get("points", [])
    if not raw_points is Array:
        return result
    for raw: Variant in raw_points:
        if not raw is Array or raw.size() != 2:
            return []
        var point := Vector2(float(raw[0]), float(raw[1]))
        if not point.is_finite():
            return []
        result.append(point)
    return result

func _candidates(document: Dictionary, midi_anchor: Vector2) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var roads: Variant = document.get("roads", [])
    if not roads is Array:
        return result
    for raw: Variant in roads:
        if not raw is Dictionary:
            continue
        var road := raw as Dictionary
        if str(road.get("name", "")) != MIDI_ROAD_NAME or not bool(road.get("drivable", false)):
            continue
        var osm_id := int(road.get("osm_id", 0))
        if osm_id <= 0:
            continue
        var nearest := INF
        for point: Vector2 in _points(road):
            nearest = minf(nearest, point.distance_to(midi_anchor))
        if is_finite(nearest) and nearest <= MAX_MIDI_ANCHOR_DISTANCE_M:
            result.append({"osm_id": osm_id, "road": road, "anchor_distance_m": nearest})
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var da := float(a.get("anchor_distance_m", INF))
        var db := float(b.get("anchor_distance_m", INF))
        if absf(da - db) > 0.000001:
            return da < db
        return int(a.get("osm_id", 0)) < int(b.get("osm_id", 0))
    )
    return result

func _run() -> void:
    var document := _source_document()
    if document.is_empty():
        _fail("source document unavailable")
        return
    var midi_anchor := _anchor(document)
    if not midi_anchor.is_finite():
        _fail("Midi anchor unavailable")
        return
    var candidates := _candidates(document, midi_anchor)
    if candidates.is_empty():
        _fail("no source-backed Fonsny candidates inside Midi neighborhood")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.own_world_3d = true
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    for _frame: int in range(36):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player missing")
        return
    var resolver := RESOLVER_SCRIPT.new()
    viewport.add_child(resolver)

    var rows: Array[Dictionary] = []
    var blocker_counts := {"source_bundle": 0, "rendered_geometry": 0, "safe_viewpoint": 0, "exact_road_support": 0, "ready": 0}
    for candidate: Dictionary in candidates:
        var osm_id := int(candidate.get("osm_id", 0))
        var bundle_raw: Variant = resolver.call("_source_bundle_by_id", osm_id)
        var bundle := bundle_raw as Dictionary if bundle_raw is Dictionary else {}
        var source_ok := not bundle.is_empty()
        var rendered := false
        var viewpoint: Dictionary = {}
        var ground_y := INF
        if source_ok:
            rendered = bool(resolver.call("_road_is_rendered", scene, osm_id))
        if source_ok and rendered:
            var view_raw: Variant = resolver.call("_safe_viewpoint", document, candidate.get("road", {}) as Dictionary)
            viewpoint = view_raw as Dictionary if view_raw is Dictionary else {}
        if source_ok and rendered and not viewpoint.is_empty():
            ground_y = float(resolver.call("_ground_y", player, viewpoint.get("spawn", Vector2.ZERO) as Vector2, osm_id))
        var support_ok := is_finite(ground_y)
        var expected_ready := source_ok and rendered and not viewpoint.is_empty() and support_ok
        var applied := bool(resolver.call("apply_to_player", player, osm_id))
        if applied != expected_ready:
            _fail("resolver stage decomposition disagrees with apply_to_player for road-%d" % osm_id)
            return
        var blocker := "ready"
        if not source_ok:
            blocker = "source_bundle"
        elif not rendered:
            blocker = "rendered_geometry"
        elif viewpoint.is_empty():
            blocker = "safe_viewpoint"
        elif not support_ok:
            blocker = "exact_road_support"
        blocker_counts[blocker] = int(blocker_counts.get(blocker, 0)) + 1
        rows.append({
            "osm_id": osm_id,
            "anchor_distance_m": float(candidate.get("anchor_distance_m", INF)),
            "source_bundle": source_ok,
            "rendered_geometry": rendered,
            "safe_viewpoint": not viewpoint.is_empty(),
            "exact_road_support": support_ok,
            "ground_y": ground_y if support_ok else null,
            "apply_to_player": applied,
            "first_blocker": blocker,
        })
        print("MIDI_AUTOMATIC_ROAD_BLOCKER_ROW: osm_id=%d source=%s rendered=%s viewpoint=%s support=%s applied=%s blocker=%s" % [osm_id, str(source_ok), str(rendered), str(not viewpoint.is_empty()), str(support_ok), str(applied), blocker])

    var output := {
        "schema": "grand-bruxelles-midi-automatic-road-blocker-attribution-v1",
        "source_path": SOURCE_PATH,
        "source_sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
        "source_name": MIDI_ROAD_NAME,
        "midi_anchor": [midi_anchor.x, midi_anchor.y],
        "candidate_count": candidates.size(),
        "blocker_counts": blocker_counts,
        "rows": rows,
        "resolver_contract_unchanged": true,
        "source_geometry_changed": false,
        "collision_changed": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("cannot persist blocker attribution")
        return
    file.store_string(JSON.stringify(output, "  ", true) + "\n")
    file.close()
    print("MIDI_AUTOMATIC_ROAD_BLOCKER_ATTRIBUTION_GREEN: candidates=%d source_bundle=%d rendered_geometry=%d safe_viewpoint=%d exact_road_support=%d ready=%d destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [candidates.size(), int(blocker_counts["source_bundle"]), int(blocker_counts["rendered_geometry"]), int(blocker_counts["safe_viewpoint"]), int(blocker_counts["exact_road_support"]), int(blocker_counts["ready"])])
    quit(0)
