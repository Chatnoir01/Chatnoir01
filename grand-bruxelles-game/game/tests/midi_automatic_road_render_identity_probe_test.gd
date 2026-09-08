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

func _metadata_mentions(node: Node, token: String) -> bool:
    for key: StringName in node.get_meta_list():
        if str(node.get_meta(key)).contains(token):
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

func _first_hidden_3d_ancestor(node: Node3D) -> String:
    var current: Node = node
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
    for osm_id: int in ids:
        var prefix := "Road_%d_" % osm_id
        var token := str(osm_id)
        var exact_named := 0
        var exact_visible_renderable := 0
        var exact_self_visible := 0
        var exact_renderable := 0
        var token_named := 0
        var metadata_mentions := 0
        var reasons: Dictionary = {}
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
                var reason := _visibility_reason(geometry)
                reasons[reason] = int(reasons.get(reason, 0)) + 1
                if reason.begins_with("ancestor_hidden:"):
                    var hidden_path := reason.trim_prefix("ancestor_hidden:")
                    hidden_ancestors[hidden_path] = int(hidden_ancestors.get(hidden_path, 0)) + 1
                if reason == "visible_renderable":
                    exact_visible_renderable += 1
                elif hidden_identity_samples.size() < HIDDEN_SAMPLE_LIMIT:
                    hidden_identity_samples.append({
                        "path": geometry.get_path().get_concatenated_names(),
                        "reason": reason,
                        "metadata": _metadata_snapshot(geometry),
                        "ancestor_chain": _ancestor_chain(geometry),
                    })
            if token_hit:
                token_named += 1
            if meta_hit:
                metadata_mentions += 1
            if (exact or token_hit or meta_hit) and samples.size() < 12:
                samples.append(geometry.get_path().get_concatenated_names())
        rows.append({
            "osm_id": osm_id,
            "expected_prefix": prefix,
            "exact_named_geometry": exact_named,
            "exact_self_visible_geometry": exact_self_visible,
            "exact_renderable_geometry": exact_renderable,
            "exact_visible_renderable_geometry": exact_visible_renderable,
            "visibility_reasons": reasons,
            "hidden_ancestors": hidden_ancestors,
            "hidden_identity_samples": hidden_identity_samples,
            "id_token_named_geometry": token_named,
            "metadata_mentions": metadata_mentions,
            "samples": samples,
        })
        print("MIDI_ROAD_RENDER_IDENTITY_ROW: osm_id=%d exact=%d self_visible=%d renderable=%d visible_renderable=%d token=%d metadata=%d reasons=%s hidden_ancestors=%s hidden_identity_samples=%d" % [osm_id, exact_named, exact_self_visible, exact_renderable, exact_visible_renderable, token_named, metadata_mentions, JSON.stringify(reasons), JSON.stringify(hidden_ancestors), hidden_identity_samples.size()])

    var output := {
        "schema": "grand-bruxelles-midi-road-render-identity-v3",
        "source_path": SOURCE_PATH,
        "source_sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
        "candidate_ids": ids,
        "geometry_instance_count": all_geometry.size(),
        "road_named_geometry_count": road_named_total,
        "road_named_visible_renderable_count": road_named_visible_renderable,
        "road_visibility_reasons": road_visibility_reasons,
        "road_named_samples": road_named_samples,
        "hidden_identity_proof": true,
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
    print("MIDI_AUTOMATIC_ROAD_RENDER_IDENTITY_GREEN: candidates=%d geometry=%d road_named=%d road_named_visible_renderable=%d hidden_identity_proof=true destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [ids.size(), all_geometry.size(), road_named_total, road_named_visible_renderable])
    quit(0)
