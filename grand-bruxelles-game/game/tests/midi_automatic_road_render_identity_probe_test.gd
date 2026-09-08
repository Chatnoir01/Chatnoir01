extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const MIDI_ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const MIDI_ANCHOR_ID := "midi"
const MAX_DISTANCE_M := 80.0
const OUTPUT_PATH := "res://artifacts/qa/midi_automatic_road_render_identity.json"
const SAMPLE_LIMIT := 64
const HIDDEN_SAMPLE_LIMIT := 8
const ANCESTRY_DEPTH_LIMIT := 12
const SUPPORT_RAY_UP_M := 4.0
const SUPPORT_RAY_DOWN_M := 8.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AUTOMATIC_ROAD_RENDER_IDENTITY_FAIL: %s" % message)
    quit(1)

func _document() -> Dictionary:
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

func _road_points(raw: Variant) -> Array[Vector2]:
    var result: Array[Vector2] = []
    if not raw is Array:
        return result
    for pair: Variant in raw:
        if not pair is Array or pair.size() != 2:
            return []
        var point := Vector2(float(pair[0]), float(pair[1]))
        if not point.is_finite():
            return []
        result.append(point)
    return result

func _candidate_ids(document: Dictionary, anchor: Vector2) -> Array[int]:
    var result: Array[int] = []
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
        for point: Vector2 in _road_points(road.get("points", [])):
            nearest = minf(nearest, point.distance_to(anchor))
        if is_finite(nearest) and nearest <= MAX_DISTANCE_M:
            result.append(osm_id)
    result.sort()
    return result

func _renderable_geometry(node: GeometryInstance3D) -> bool:
    if node is MeshInstance3D:
        var mesh := (node as MeshInstance3D).mesh
        return mesh != null and mesh.get_surface_count() > 0
    if node is MultiMeshInstance3D:
        var multimesh := (node as MultiMeshInstance3D).multimesh
        return multimesh != null and multimesh.mesh != null and multimesh.mesh.get_surface_count() > 0 and multimesh.instance_count > 0
    if node is CSGShape3D:
        return true
    return false

func _metadata_snapshot(node: Node) -> Dictionary:
    var snapshot: Dictionary = {}
    for key: StringName in node.get_meta_list():
        var value: Variant = node.get_meta(key)
        if value is String or value is StringName or value is bool or value is int or value is float:
            snapshot[str(key)] = value
        elif value is Array:
            var simple: Array = []
            var valid := true
            for item: Variant in value:
                if item is String or item is StringName or item is bool or item is int or item is float:
                    simple.append(item)
                else:
                    valid = false
                    break
            if valid:
                snapshot[str(key)] = simple
    return snapshot

func _metadata_mentions(node: Node, token: String) -> bool:
    for key: StringName in node.get_meta_list():
        if str(node.get_meta(key)).contains(token):
            return true
    return false

func _leaf_osm_id_matches(node: Node, osm_id: int) -> bool:
    if not node.has_meta("osm_id"):
        return false
    return int(node.get_meta("osm_id")) == osm_id

func _ancestor_chain(node: Node3D) -> Array[Dictionary]:
    var chain: Array[Dictionary] = []
    var current: Node = node
    var depth := 0
    while current != null and depth < ANCESTRY_DEPTH_LIMIT:
        var row := {
            "path": current.get_path().get_concatenated_names(),
            "class": current.get_class(),
            "metadata": _metadata_snapshot(current),
        }
        if current is Node3D:
            row["visible"] = (current as Node3D).visible
            row["visible_in_tree"] = (current as Node3D).is_visible_in_tree()
        chain.append(row)
        current = current.get_parent()
        depth += 1
    return chain

func _captured_ancestors_all_visible(chain: Array[Dictionary]) -> bool:
    for index: int in range(1, chain.size()):
        var row: Dictionary = chain[index]
        if row.has("visible") and not bool(row["visible"]):
            return false
    return true

func _first_hidden_3d_ancestor(node: Node3D) -> String:
    var current: Node = node.get_parent()
    while current != null:
        if current is Node3D and not (current as Node3D).visible:
            return current.get_path().get_concatenated_names()
        current = current.get_parent()
    return ""

func _visibility_reason(node: GeometryInstance3D) -> String:
    if not _renderable_geometry(node):
        return "not_renderable"
    if not node.visible:
        return "self_hidden"
    if not node.is_visible_in_tree():
        var hidden_ancestor := _first_hidden_3d_ancestor(node)
        return "ancestor_hidden:%s" % hidden_ancestor if not hidden_ancestor.is_empty() else "tree_hidden_unknown"
    return "visible_renderable"

func _visibility_owner(reason: String) -> String:
    if reason == "self_hidden":
        return "road_leaf"
    if reason.begins_with("ancestor_hidden:"):
        return "ancestor:%s" % reason.trim_prefix("ancestor_hidden:")
    if reason == "visible_renderable":
        return "runtime_visible"
    if reason == "not_renderable":
        return "not_renderable"
    return "unknown"

func _readiness_blocker(reason: String) -> String:
    if reason == "self_hidden":
        return "exact_osm_geometry_leaf_self_hidden"
    if reason.begins_with("ancestor_hidden:"):
        return "exact_osm_geometry_ancestor_hidden"
    if reason == "visible_renderable":
        return "none"
    if reason == "not_renderable":
        return "exact_osm_geometry_not_renderable"
    return "unknown_visibility_owner"

func _vector3_json(value: Vector3) -> Dictionary:
    return {"x": value.x, "y": value.y, "z": value.z}

func _support_probe(node: GeometryInstance3D) -> Dictionary:
    var origin := node.global_position + Vector3(0.0, SUPPORT_RAY_UP_M, 0.0)
    var finish := node.global_position - Vector3(0.0, SUPPORT_RAY_DOWN_M, 0.0)
    var result := {
        "ray_from": _vector3_json(origin),
        "ray_to": _vector3_json(finish),
        "hit": false,
        "collider_path": "",
        "collider_class": "",
        "collision_layer": 0,
        "position": {},
        "normal": {},
        "metadata": {},
    }
    var world := node.get_world_3d()
    if world == null:
        return result
    var query := PhysicsRayQueryParameters3D.create(origin, finish)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var hit: Dictionary = world.direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return result
    result["hit"] = true
    var position: Variant = hit.get("position", null)
    var normal: Variant = hit.get("normal", null)
    if position is Vector3:
        result["position"] = _vector3_json(position)
    if normal is Vector3:
        result["normal"] = _vector3_json(normal)
    var collider: Variant = hit.get("collider", null)
    if collider is Node:
        var collider_node := collider as Node
        result["collider_path"] = collider_node.get_path().get_concatenated_names()
        result["collider_class"] = collider_node.get_class()
        result["metadata"] = _metadata_snapshot(collider_node)
        if collider_node is CollisionObject3D:
            result["collision_layer"] = (collider_node as CollisionObject3D).collision_layer
    return result

func _run() -> void:
    var document := _document()
    if document.is_empty():
        _fail("source unavailable")
        return
    var midi_anchor := _anchor(document)
    if not midi_anchor.is_finite():
        _fail("Midi anchor unavailable")
        return
    var ids := _candidate_ids(document, midi_anchor)
    if ids.is_empty():
        _fail("no source-backed Fonsny candidates")
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

    var all_geometry: Array[GeometryInstance3D] = []
    var stack: Array[Node] = [scene]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is GeometryInstance3D:
            all_geometry.append(node as GeometryInstance3D)
        for child: Node in node.get_children():
            stack.append(child)

    var road_named_total := 0
    var road_named_visible_renderable := 0
    var road_named_samples: Array[String] = []
    var road_visibility_reasons: Dictionary = {}
    for geometry: GeometryInstance3D in all_geometry:
        var name := str(geometry.name)
        if name.begins_with("Road_"):
            road_named_total += 1
            var reason := _visibility_reason(geometry)
            road_visibility_reasons[reason] = int(road_visibility_reasons.get(reason, 0)) + 1
            if reason == "visible_renderable":
                road_named_visible_renderable += 1
            if road_named_samples.size() < SAMPLE_LIMIT:
                road_named_samples.append(name)

    var rows: Array[Dictionary] = []
    var total_hidden_samples := 0
    var total_hidden_support_hits := 0
    var ownership_errors: Array[String] = []
    var ownership_counts: Dictionary = {}
    var blocker_counts: Dictionary = {}
    for osm_id: int in ids:
        var prefix := "Road_%d_" % osm_id
        var token := str(osm_id)
        var exact_named := 0
        var exact_visible_renderable := 0
        var exact_self_visible := 0
        var exact_renderable := 0
        var exact_leaf_osm_id_matches := 0
        var token_named := 0
        var metadata_mentions := 0
        var support_hits := 0
        var reasons: Dictionary = {}
        var visibility_owners: Dictionary = {}
        var readiness_blockers: Dictionary = {}
        var hidden_ancestors: Dictionary = {}
        var samples: Array[String] = []
        var hidden_identity_samples: Array[Dictionary] = []
        for geometry: GeometryInstance3D in all_geometry:
            var name := str(geometry.name)
            var exact := name.begins_with(prefix)
            var token_hit := name.contains(token)
            var meta_hit := _metadata_mentions(geometry, token)
            if exact:
                exact_named += 1
                if geometry.visible:
                    exact_self_visible += 1
                if _renderable_geometry(geometry):
                    exact_renderable += 1
                var leaf_matches := _leaf_osm_id_matches(geometry, osm_id)
                if leaf_matches:
                    exact_leaf_osm_id_matches += 1
                else:
                    ownership_errors.append("road-%d exact geometry %s does not carry matching osm_id metadata" % [osm_id, geometry.get_path().get_concatenated_names()])
                var reason := _visibility_reason(geometry)
                var owner := _visibility_owner(reason)
                var blocker := _readiness_blocker(reason)
                reasons[reason] = int(reasons.get(reason, 0)) + 1
                visibility_owners[owner] = int(visibility_owners.get(owner, 0)) + 1
                readiness_blockers[blocker] = int(readiness_blockers.get(blocker, 0)) + 1
                ownership_counts[owner] = int(ownership_counts.get(owner, 0)) + 1
                blocker_counts[blocker] = int(blocker_counts.get(blocker, 0)) + 1
                if owner == "unknown" or blocker == "unknown_visibility_owner":
                    ownership_errors.append("road-%d has ambiguous visibility reason %s at %s" % [osm_id, reason, geometry.get_path().get_concatenated_names()])
                if reason.begins_with("ancestor_hidden:"):
                    var hidden_path := reason.trim_prefix("ancestor_hidden:")
                    hidden_ancestors[hidden_path] = int(hidden_ancestors.get(hidden_path, 0)) + 1
                if reason == "visible_renderable":
                    exact_visible_renderable += 1
                elif hidden_identity_samples.size() < HIDDEN_SAMPLE_LIMIT:
                    var ancestry := _ancestor_chain(geometry)
                    var ancestors_all_visible := _captured_ancestors_all_visible(ancestry)
                    if reason == "self_hidden" and not ancestors_all_visible:
                        ownership_errors.append("road-%d self-hidden leaf has an additional hidden captured ancestor at %s" % [osm_id, geometry.get_path().get_concatenated_names()])
                    var support := _support_probe(geometry)
                    if bool(support.get("hit", false)):
                        support_hits += 1
                        total_hidden_support_hits += 1
                    total_hidden_samples += 1
                    hidden_identity_samples.append({
                        "path": geometry.get_path().get_concatenated_names(),
                        "reason": reason,
                        "visibility_owner": owner,
                        "readiness_blocker": blocker,
                        "direct_leaf_visibility_disabled": not geometry.visible,
                        "captured_ancestors_all_visible": ancestors_all_visible,
                        "leaf_osm_id_matches_candidate": leaf_matches,
                        "metadata": _metadata_snapshot(geometry),
                        "ancestor_chain": ancestry,
                        "support_probe": support,
                    })
            if token_hit:
                token_named += 1
            if meta_hit:
                metadata_mentions += 1
            if (exact or token_hit or meta_hit) and samples.size() < 12:
                samples.append(geometry.get_path().get_concatenated_names())
        if exact_named > 0 and exact_leaf_osm_id_matches != exact_named:
            ownership_errors.append("road-%d exact geometry identity is not fully source-bound" % osm_id)
        if sum(visibility_owners.values()) != exact_named:
            ownership_errors.append("road-%d visibility ownership count does not match exact geometry count" % osm_id)
        rows.append({
            "osm_id": osm_id,
            "expected_prefix": prefix,
            "exact_named_geometry": exact_named,
            "exact_self_visible_geometry": exact_self_visible,
            "exact_renderable_geometry": exact_renderable,
            "exact_visible_renderable_geometry": exact_visible_renderable,
            "exact_leaf_osm_id_matches": exact_leaf_osm_id_matches,
            "visibility_reasons": reasons,
            "visibility_owners": visibility_owners,
            "readiness_blockers": readiness_blockers,
            "hidden_ancestors": hidden_ancestors,
            "hidden_identity_samples": hidden_identity_samples,
            "hidden_support_hits": support_hits,
            "id_token_named_geometry": token_named,
            "metadata_mentions": metadata_mentions,
            "samples": samples,
        })
        print("MIDI_ROAD_RENDER_IDENTITY_ROW: osm_id=%d exact=%d source_bound=%d self_visible=%d renderable=%d visible_renderable=%d token=%d metadata=%d support_hits=%d reasons=%s owners=%s blockers=%s hidden_ancestors=%s hidden_identity_samples=%d" % [osm_id, exact_named, exact_leaf_osm_id_matches, exact_self_visible, exact_renderable, exact_visible_renderable, token_named, metadata_mentions, support_hits, JSON.stringify(reasons), JSON.stringify(visibility_owners), JSON.stringify(readiness_blockers), JSON.stringify(hidden_ancestors), hidden_identity_samples.size()])

    var output := {
        "schema": "grand-bruxelles-midi-road-render-identity-v3",
        "visibility_ownership_contract_version": 1,
        "visibility_ownership_fail_closed": true,
        "visibility_ownership_errors": ownership_errors,
        "visibility_owner_counts": ownership_counts,
        "readiness_blocker_counts": blocker_counts,
        "source_path": SOURCE_PATH,
        "source_sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
        "candidate_ids": ids,
        "geometry_instance_count": all_geometry.size(),
        "road_named_geometry_count": road_named_total,
        "road_named_visible_renderable_count": road_named_visible_renderable,
        "road_visibility_reasons": road_visibility_reasons,
        "road_named_samples": road_named_samples,
        "hidden_identity_proof": true,
        "hidden_support_probe_count": total_hidden_samples,
        "hidden_support_hit_count": total_hidden_support_hits,
        "hidden_support_probe_independent": true,
        "rows": rows,
        "diagnostic_only": true,
        "source_geometry_changed": false,
        "collision_changed": false,
        "resolver_changed": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("cannot persist render identity probe")
        return
    file.store_string(JSON.stringify(output, "  ", true) + "\n")
    file.close()
    if not ownership_errors.is_empty():
        _fail("visibility ownership contract ambiguous: %s" % JSON.stringify(ownership_errors))
        return
    print("MIDI_AUTOMATIC_ROAD_RENDER_IDENTITY_GREEN: candidates=%d geometry=%d road_named=%d road_named_visible_renderable=%d hidden_support_probes=%d hidden_support_hits=%d ownership_contract=1 ownership_errors=0 hidden_identity_proof=true destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [ids.size(), all_geometry.size(), road_named_total, road_named_visible_renderable, total_hidden_samples, total_hidden_support_hits])
    quit(0)
