extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const OUTPUT_PATH := "res://artifacts/qa/midi_automatic_road_rejection_ledger.json"
const MIDI_ANCHOR_ID := "midi"
const MIDI_ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const MAX_MIDI_ANCHOR_DISTANCE_M := 80.0
const AUTOMATIC_ROAD_META_PREFIX := "automatic_road_direct_"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AUTOMATIC_ROAD_REJECTION_LEDGER_FAIL: %s" % message)
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
        if not raw is Dictionary:
            continue
        var anchor := raw as Dictionary
        if str(anchor.get("id", "")) == MIDI_ANCHOR_ID:
            return Vector2(float(anchor.get("x", INF)), float(anchor.get("z", INF)))
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

func _automatic_road_metadata(player: CharacterBody3D) -> Dictionary:
    var metadata := {}
    for raw_key: StringName in player.get_meta_list():
        var key := str(raw_key)
        if key.begins_with(AUTOMATIC_ROAD_META_PREFIX):
            metadata[key] = player.get_meta(raw_key)
    return metadata

func _snapshot_player_state(player: CharacterBody3D) -> Dictionary:
    return {
        "global_transform": player.global_transform,
        "velocity": player.velocity,
        "metadata": _automatic_road_metadata(player),
    }

func _restore_player_state(player: CharacterBody3D, snapshot: Dictionary) -> void:
    player.global_transform = snapshot.get("global_transform", player.global_transform) as Transform3D
    player.velocity = snapshot.get("velocity", Vector3.ZERO) as Vector3
    var metadata_raw: Variant = snapshot.get("metadata", {})
    var metadata := metadata_raw as Dictionary if metadata_raw is Dictionary else {}
    for raw_key: StringName in player.get_meta_list():
        var key := str(raw_key)
        if key.begins_with(AUTOMATIC_ROAD_META_PREFIX) and not metadata.has(key):
            player.remove_meta(raw_key)
    for key: Variant in metadata.keys():
        player.set_meta(StringName(str(key)), metadata[key])

func _same_player_state(player: CharacterBody3D, snapshot: Dictionary) -> bool:
    if player.global_transform != (snapshot.get("global_transform", player.global_transform) as Transform3D):
        return false
    if player.velocity != (snapshot.get("velocity", player.velocity) as Vector3):
        return false
    var metadata_raw: Variant = snapshot.get("metadata", {})
    var metadata := metadata_raw as Dictionary if metadata_raw is Dictionary else {}
    var current := _automatic_road_metadata(player)
    if current.size() != metadata.size():
        return false
    for key: Variant in metadata.keys():
        if not current.has(key) or current[key] != metadata[key]:
            return false
    return true

func _location_label(scene: Node) -> Label:
    return scene.get_node_or_null("LocationLabel") as Label

func _snapshot_location_label_state(scene: Node) -> Dictionary:
    var label := _location_label(scene)
    if label == null:
        return {"exists": false}
    var forced := ""
    if label.has_method("set_forced_label") and label.get("_forced_label") != null:
        forced = str(label.get("_forced_label"))
    return {"exists": true, "text": label.text, "forced_label": forced}

func _restore_location_label_state(scene: Node, snapshot: Dictionary) -> void:
    var label := _location_label(scene)
    if label == null or not bool(snapshot.get("exists", false)):
        return
    var forced := str(snapshot.get("forced_label", ""))
    if label.has_method("set_forced_label") and label.has_method("clear_forced_label"):
        if forced.is_empty():
            label.call("clear_forced_label")
        else:
            label.call("set_forced_label", forced)
    label.text = str(snapshot.get("text", label.text))

func _same_location_label_state(scene: Node, snapshot: Dictionary) -> bool:
    var label := _location_label(scene)
    var expected_exists := bool(snapshot.get("exists", false))
    if (label != null) != expected_exists:
        return false
    if label == null:
        return true
    if label.text != str(snapshot.get("text", "")):
        return false
    if label.has_method("set_forced_label") and label.get("_forced_label") != null:
        return str(label.get("_forced_label")) == str(snapshot.get("forced_label", ""))
    return str(snapshot.get("forced_label", "")).is_empty()

func _write_ledger(payload: Dictionary) -> bool:
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
        _fail("no exact Fonsny candidates inside Midi neighborhood")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(320, 180)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    _hide_dynamic(scene)
    for _frame: int in range(36):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player missing")
        return
    var location_label := _location_label(scene)
    if location_label == null:
        _fail("production LocationLabel missing")
        return
    var baseline_player_state := _snapshot_player_state(player)
    var baseline_location_label_state := _snapshot_location_label_state(scene)

    var rows: Array[Dictionary] = []
    var first_ready_id := 0
    var blocker_counts := {
        "source_bundle": 0,
        "rendered_geometry": 0,
        "safe_viewpoint": 0,
        "exact_road_support": 0,
        "ready": 0,
    }
    for candidate: Dictionary in candidates:
        if not _same_player_state(player, baseline_player_state):
            _fail("player state leaked before evaluating road-%d" % int(candidate.get("osm_id", 0)))
            return
        if not _same_location_label_state(scene, baseline_location_label_state):
            _fail("LocationLabel state leaked before evaluating road-%d" % int(candidate.get("osm_id", 0)))
            return
        # A fresh resolver per candidate prevents mutable resolver caches/state from
        # making the ledger order-dependent as the generic resolver evolves.
        var resolver := RESOLVER_SCRIPT.new()
        var osm_id := int(candidate.get("osm_id", 0))
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
        var expected_apply := source_bundle and rendered_geometry and safe_viewpoint and exact_road_support
        if apply_to_player != expected_apply:
            _restore_player_state(player, baseline_player_state)
            _restore_location_label_state(scene, baseline_location_label_state)
            _fail("resolver decomposition mismatch for road-%d" % osm_id)
            return
        _restore_player_state(player, baseline_player_state)
        _restore_location_label_state(scene, baseline_location_label_state)
        if not _same_player_state(player, baseline_player_state):
            _fail("could not restore player state after road-%d" % osm_id)
            return
        if not _same_location_label_state(scene, baseline_location_label_state):
            _fail("could not restore LocationLabel state after road-%d" % osm_id)
            return
        var first_blocker := "ready"
        if not source_bundle:
            first_blocker = "source_bundle"
        elif not rendered_geometry:
            first_blocker = "rendered_geometry"
        elif not safe_viewpoint:
            first_blocker = "safe_viewpoint"
        elif not exact_road_support:
            first_blocker = "exact_road_support"
        blocker_counts[first_blocker] = int(blocker_counts[first_blocker]) + 1
        if apply_to_player and first_ready_id == 0:
            first_ready_id = osm_id
        rows.append({
            "osm_id": osm_id,
            "anchor_distance_m": float(candidate.get("anchor_distance_m", INF)),
            "source_bundle": source_bundle,
            "rendered_geometry": rendered_geometry,
            "safe_viewpoint": safe_viewpoint,
            "exact_road_support": exact_road_support,
            "spawn_xz": [spawn_xz.x, spawn_xz.y] if spawn_xz.is_finite() else null,
            "ground_y": ground_y if is_finite(ground_y) else null,
            "apply_to_player": apply_to_player,
            "first_blocker": first_blocker,
            "resolver_instance_isolated": true,
            "player_state_restored": true,
            "location_label_state_restored": true,
        })

    var payload := {
        "schema": "grand-bruxelles-midi-automatic-road-rejection-ledger-v5",
        "source_path": SOURCE_PATH,
        "source_sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
        "candidate_count": candidates.size(),
        "first_ready_osm_id": first_ready_id,
        "blocker_counts": blocker_counts,
        "rows": rows,
        "resolver_instance_isolated": true,
        "resolver_isolation": "fresh_instance_per_candidate",
        "player_state_isolated": true,
        "player_metadata_isolation": "automatic_road_direct_namespace",
        "location_label_state_isolated": true,
        "location_label_isolation": "forced_label_and_text",
        "resolver_contract_unchanged": true,
        "source_geometry_changed": false,
        "collision_changed": false,
        "osm_to_urbis_crosswalk_claimed": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write_ledger(payload):
        _fail("could not persist rejection ledger")
        return
    print("MIDI_AUTOMATIC_ROAD_REJECTION_LEDGER_GREEN: candidates=%d ready=%d blockers=%s source_sha=%s resolver_instance_isolated=true resolver_isolation=fresh_instance_per_candidate player_state_isolated=true metadata_isolation=automatic_road_direct_namespace location_label_state_isolated=true location_label_isolation=forced_label_and_text crosswalk_claimed=false" % [candidates.size(), int(blocker_counts["ready"]), str(blocker_counts).replace(" ", ""), str(payload["source_sha256"])])
    quit(0)
