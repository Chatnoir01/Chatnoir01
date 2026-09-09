extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const OUTPUT_PATH := "res://artifacts/qa/midi_automatic_road_rejection_order_invariance.json"
const MIDI_ANCHOR_ID := "midi"
const MIDI_ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const MAX_MIDI_ANCHOR_DISTANCE_M := 80.0
const META_PREFIX := "automatic_road_direct_"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AUTOMATIC_ROAD_REJECTION_ORDER_INVARIANCE_FAIL: %s" % message)
    quit(1)

func _document() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    return parsed as Dictionary if parsed is Dictionary else {}

func _midi_anchor(document: Dictionary) -> Vector2:
    var corridor_raw: Variant = document.get("corridor", {})
    if not corridor_raw is Dictionary:
        return Vector2(INF, INF)
    var anchors_raw: Variant = (corridor_raw as Dictionary).get("anchors", [])
    if not anchors_raw is Array:
        return Vector2(INF, INF)
    for raw: Variant in anchors_raw:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == MIDI_ANCHOR_ID:
            return Vector2(float((raw as Dictionary).get("x", INF)), float((raw as Dictionary).get("z", INF)))
    return Vector2(INF, INF)

func _road_points(road: Dictionary) -> PackedVector2Array:
    var points := PackedVector2Array()
    var raw_points: Variant = road.get("points", [])
    if not raw_points is Array:
        return points
    for raw: Variant in raw_points:
        if not raw is Array or raw.size() != 2:
            return PackedVector2Array()
        var point := Vector2(float(raw[0]), float(raw[1]))
        if not point.is_finite():
            return PackedVector2Array()
        points.append(point)
    return points

func _nearest_anchor_distance(road: Dictionary, anchor: Vector2) -> float:
    var best := INF
    for point: Vector2 in _road_points(road):
        best = minf(best, point.distance_to(anchor))
    return best

func _candidates(document: Dictionary, anchor: Vector2) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var roads_raw: Variant = document.get("roads", [])
    if not roads_raw is Array:
        return result
    for raw: Variant in roads_raw:
        if not raw is Dictionary:
            continue
        var road := raw as Dictionary
        var osm_id := int(road.get("osm_id", 0))
        if osm_id <= 0 or str(road.get("name", "")) != MIDI_ROAD_NAME or not bool(road.get("drivable", false)):
            continue
        var distance := _nearest_anchor_distance(road, anchor)
        if is_finite(distance) and distance <= MAX_MIDI_ANCHOR_DISTANCE_M:
            result.append({"osm_id": osm_id, "anchor_distance_m": distance})
    result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var da := float(a.get("anchor_distance_m", INF))
        var db := float(b.get("anchor_distance_m", INF))
        if absf(da - db) > 0.000001:
            return da < db
        return int(a.get("osm_id", 0)) < int(b.get("osm_id", 0))
    )
    return result

func _hide_dynamic(scene: Node) -> void:
    for path: String in ["MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var item := scene.get_node_or_null(path) as CanvasItem
        if item != null:
            item.visible = false
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null:
            spatial.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false

func _automatic_metadata(player: CharacterBody3D) -> Dictionary:
    var result := {}
    for raw_key: StringName in player.get_meta_list():
        var key := str(raw_key)
        if key.begins_with(META_PREFIX):
            result[key] = player.get_meta(raw_key)
    return result

func _snapshot_player(player: CharacterBody3D) -> Dictionary:
    return {"global_transform": player.global_transform, "velocity": player.velocity, "metadata": _automatic_metadata(player)}

func _restore_player(player: CharacterBody3D, snapshot: Dictionary) -> void:
    player.global_transform = snapshot["global_transform"] as Transform3D
    player.velocity = snapshot["velocity"] as Vector3
    var metadata := snapshot["metadata"] as Dictionary
    for raw_key: StringName in player.get_meta_list():
        var key := str(raw_key)
        if key.begins_with(META_PREFIX) and not metadata.has(key):
            player.remove_meta(raw_key)
    for key: Variant in metadata.keys():
        player.set_meta(StringName(str(key)), metadata[key])

func _same_player(player: CharacterBody3D, snapshot: Dictionary) -> bool:
    if player.global_transform != (snapshot["global_transform"] as Transform3D) or player.velocity != (snapshot["velocity"] as Vector3):
        return false
    return _automatic_metadata(player) == (snapshot["metadata"] as Dictionary)

func _label(scene: Node) -> Label:
    return scene.get_node_or_null("LocationLabel") as Label

func _snapshot_label(scene: Node) -> Dictionary:
    var label := _label(scene)
    if label == null:
        return {"exists": false}
    return {"exists": true, "text": label.text, "forced_label": str(label.get("_forced_label")) if label.get("_forced_label") != null else ""}

func _restore_label(scene: Node, snapshot: Dictionary) -> void:
    var label := _label(scene)
    if label == null or not bool(snapshot.get("exists", false)):
        return
    var forced := str(snapshot.get("forced_label", ""))
    if forced.is_empty():
        label.call("clear_forced_label")
    else:
        label.call("set_forced_label", forced)
    label.text = str(snapshot.get("text", ""))

func _same_label(scene: Node, snapshot: Dictionary) -> bool:
    var label := _label(scene)
    if label == null:
        return not bool(snapshot.get("exists", false))
    return label.text == str(snapshot.get("text", "")) and str(label.get("_forced_label")) == str(snapshot.get("forced_label", ""))

func _new_scene() -> Dictionary:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(320, 180)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    _hide_dynamic(scene)
    return {"viewport": viewport, "scene": scene}

func _evaluate(scene: Node, player: CharacterBody3D, osm_id: int) -> Dictionary:
    var resolver := RESOLVER_SCRIPT.new()
    var bundle_raw: Variant = resolver.call("_source_bundle_by_id", osm_id)
    var bundle := bundle_raw as Dictionary if bundle_raw is Dictionary else {}
    var source_bundle := not bundle.is_empty()
    var rendered_geometry := false
    var safe_viewpoint := false
    var exact_road_support := false
    var spawn_xz := Vector2(INF, INF)
    var ground_y := INF
    if source_bundle:
        rendered_geometry = bool(resolver.call("_road_is_rendered", scene, osm_id))
        var viewpoint_raw: Variant = resolver.call("_safe_viewpoint", bundle.get("document", {}), bundle.get("road", {}))
        var viewpoint := viewpoint_raw as Dictionary if viewpoint_raw is Dictionary else {}
        safe_viewpoint = not viewpoint.is_empty()
        if safe_viewpoint:
            spawn_xz = viewpoint.get("spawn", Vector2(INF, INF)) as Vector2
            if spawn_xz.is_finite():
                ground_y = float(resolver.call("_ground_y", player, spawn_xz, osm_id))
                exact_road_support = is_finite(ground_y)
    var apply_to_player := bool(resolver.call("apply_to_player", player, osm_id))
    resolver.free()
    var expected := source_bundle and rendered_geometry and safe_viewpoint and exact_road_support
    if apply_to_player != expected:
        return {"error": "decomposition_mismatch"}
    var blocker := "ready"
    if not source_bundle:
        blocker = "source_bundle"
    elif not rendered_geometry:
        blocker = "rendered_geometry"
    elif not safe_viewpoint:
        blocker = "safe_viewpoint"
    elif not exact_road_support:
        blocker = "exact_road_support"
    return {
        "source_bundle": source_bundle,
        "rendered_geometry": rendered_geometry,
        "safe_viewpoint": safe_viewpoint,
        "exact_road_support": exact_road_support,
        "spawn_xz": [spawn_xz.x, spawn_xz.y] if spawn_xz.is_finite() else null,
        "ground_y": ground_y if is_finite(ground_y) else null,
        "apply_to_player": apply_to_player,
        "first_blocker": blocker,
    }

func _run_pass(candidates: Array[Dictionary], reverse_order: bool) -> Dictionary:
    var holder := _new_scene()
    var viewport := holder["viewport"] as SubViewport
    var scene := holder["scene"] as Node
    for _frame: int in range(36):
        await process_frame
        await physics_frame
    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null or _label(scene) == null:
        viewport.queue_free()
        return {"error": "production_player_or_label_missing"}
    var player_baseline := _snapshot_player(player)
    var label_baseline := _snapshot_label(scene)
    var ordered := candidates.duplicate(true)
    if reverse_order:
        ordered.reverse()
    var rows := {}
    for candidate: Dictionary in ordered:
        var osm_id := int(candidate.get("osm_id", 0))
        if not _same_player(player, player_baseline) or not _same_label(scene, label_baseline):
            viewport.queue_free()
            return {"error": "pre_candidate_state_leak", "osm_id": osm_id}
        var row := _evaluate(scene, player, osm_id)
        if row.has("error"):
            viewport.queue_free()
            return {"error": row["error"], "osm_id": osm_id}
        _restore_player(player, player_baseline)
        _restore_label(scene, label_baseline)
        if not _same_player(player, player_baseline) or not _same_label(scene, label_baseline):
            viewport.queue_free()
            return {"error": "post_candidate_restore_failed", "osm_id": osm_id}
        rows[str(osm_id)] = row
    viewport.queue_free()
    await process_frame
    return {"rows": rows}

func _write(payload: Dictionary) -> bool:
    var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(payload, "  ") + "\n")
    file.close()
    return true

func _run() -> void:
    var document := _document()
    if document.is_empty():
        _fail("source document missing or invalid")
        return
    var anchor := _midi_anchor(document)
    if not anchor.is_finite():
        _fail("Midi anchor missing")
        return
    var candidates := _candidates(document, anchor)
    if candidates.is_empty():
        _fail("no exact Fonsny candidates")
        return
    var forward := await _run_pass(candidates, false)
    if forward.has("error"):
        _fail("forward pass failed: %s" % str(forward))
        return
    var reverse := await _run_pass(candidates, true)
    if reverse.has("error"):
        _fail("reverse pass failed: %s" % str(reverse))
        return
    var forward_rows := forward["rows"] as Dictionary
    var reverse_rows := reverse["rows"] as Dictionary
    var mismatches: Array[Dictionary] = []
    for candidate: Dictionary in candidates:
        var osm_id := int(candidate.get("osm_id", 0))
        var key := str(osm_id)
        if not forward_rows.has(key) or not reverse_rows.has(key) or forward_rows[key] != reverse_rows[key]:
            mismatches.append({"osm_id": osm_id, "forward": forward_rows.get(key), "reverse": reverse_rows.get(key)})
    var payload := {
        "schema": "grand-bruxelles-midi-automatic-road-rejection-order-invariance-v1",
        "source_path": SOURCE_PATH,
        "source_sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
        "candidate_count": candidates.size(),
        "forward_rows": forward_rows,
        "reverse_rows": reverse_rows,
        "mismatch_count": mismatches.size(),
        "mismatches": mismatches,
        "fresh_scene_per_pass": true,
        "fresh_resolver_per_candidate": true,
        "player_state_restored_per_candidate": true,
        "location_label_state_restored_per_candidate": true,
        "order_invariant": mismatches.is_empty(),
        "resolver_contract_unchanged": true,
        "source_geometry_changed": false,
        "collision_changed": false,
        "osm_to_urbis_crosswalk_claimed": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write(payload):
        _fail("could not persist order-invariance evidence")
        return
    if not mismatches.is_empty():
        _fail("forward/reverse mismatch: %s" % str(mismatches))
        return
    print("MIDI_AUTOMATIC_ROAD_REJECTION_ORDER_INVARIANCE_GREEN: candidates=%d mismatches=0 fresh_scene_per_pass=true fresh_resolver_per_candidate=true crosswalk_claimed=false" % candidates.size())
    quit(0)
