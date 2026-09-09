extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const OUTPUT_PATH := "res://artifacts/qa/midi_automatic_road_visibility_mask_attribution.json"
const MIDI_ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const MIDI_ANCHOR_ID := "midi"
const MAX_DISTANCE_M := 80.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AUTOMATIC_ROAD_VISIBILITY_MASK_ATTRIBUTION_FAIL: %s" % message)
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

func _json_meta(node: Node) -> Dictionary:
    var output: Dictionary = {}
    for key: StringName in node.get_meta_list():
        var value: Variant = node.get_meta(key)
        match typeof(value):
            TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
                output[str(key)] = value
            TYPE_ARRAY:
                var safe := true
                for item: Variant in value:
                    if typeof(item) not in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME]:
                        safe = false
                        break
                if safe:
                    output[str(key)] = value
    return output

func _first_hidden_ancestor(node: GeometryInstance3D) -> Node:
    var cursor: Node = node
    while cursor != null:
        if cursor is Node3D and not (cursor as Node3D).visible:
            return cursor
        cursor = cursor.get_parent()
    return null

func _script_ancestry(scene: Node, node: Node) -> Array[Dictionary]:
    var result: Array[Dictionary] = []
    var cursor: Node = node
    while cursor != null:
        var script_variant: Variant = cursor.get_script()
        if script_variant is Script:
            var script := script_variant as Script
            var path := script.resource_path
            if not path.is_empty():
                result.append({
                    "node_path": str(scene.get_path_to(cursor)),
                    "node_name": str(cursor.name),
                    "node_class": cursor.get_class(),
                    "script_path": path,
                })
        if cursor == scene:
            break
        cursor = cursor.get_parent()
    return result

func _run() -> void:
    var document := _document()
    if document.is_empty():
        _fail("source unavailable")
        return
    var anchor := _anchor(document)
    if not anchor.is_finite():
        _fail("Midi anchor unavailable")
        return
    var ids := _candidate_ids(document, anchor)
    if ids.is_empty():
        _fail("no source-backed Fonsny candidates")
        return
    var candidate_set: Dictionary = {}
    for osm_id: int in ids:
        candidate_set[osm_id] = true

    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.own_world_3d = true
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    for _frame: int in range(36):
        await process_frame
        await physics_frame

    var rows: Array[Dictionary] = []
    var exact_nodes := 0
    var hidden_nodes := 0
    var direct_self_hidden_nodes := 0
    var unattributed_hidden_nodes := 0
    var missing_script_ancestry_nodes := 0
    var stack: Array[Node] = [scene]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is GeometryInstance3D:
            var geometry := node as GeometryInstance3D
            var osm_id := int(geometry.get_meta("osm_id", 0))
            if osm_id <= 0:
                var node_name := str(geometry.name)
                for candidate_id: int in ids:
                    if node_name.begins_with("Road_%d_" % candidate_id):
                        osm_id = candidate_id
                        break
            if candidate_set.has(osm_id):
                exact_nodes += 1
                var renderable := geometry.is_visible_in_tree()
                var hidden_owner: Node = null
                if not renderable:
                    hidden_nodes += 1
                    hidden_owner = _first_hidden_ancestor(geometry)
                    if hidden_owner == null:
                        unattributed_hidden_nodes += 1
                    elif hidden_owner == geometry:
                        direct_self_hidden_nodes += 1
                var ancestry := _script_ancestry(scene, geometry)
                if ancestry.is_empty():
                    missing_script_ancestry_nodes += 1
                var owner_meta := _json_meta(hidden_owner) if hidden_owner != null else {}
                var row := {
                    "osm_id": osm_id,
                    "node_path": str(scene.get_path_to(geometry)),
                    "node_name": str(geometry.name),
                    "node_class": geometry.get_class(),
                    "node_visible": geometry.visible,
                    "visible_in_tree": renderable,
                    "node_metadata": _json_meta(geometry),
                    "first_hidden_ancestor_path": str(scene.get_path_to(hidden_owner)) if hidden_owner != null else "",
                    "first_hidden_ancestor_name": str(hidden_owner.name) if hidden_owner != null else "",
                    "first_hidden_ancestor_class": hidden_owner.get_class() if hidden_owner != null else "",
                    "first_hidden_ancestor_metadata": owner_meta,
                    "hidden_owner_is_self": hidden_owner == geometry,
                    "script_ancestry": ancestry,
                }
                rows.append(row)
                print("MIDI_VISIBILITY_MASK_ROW: osm_id=%d node=%s visible=%s hidden_owner=%s self_hidden=%s script_ancestry=%s owner_meta=%s" % [osm_id, row["node_path"], str(renderable), row["first_hidden_ancestor_path"], str(row["hidden_owner_is_self"]), JSON.stringify(ancestry), JSON.stringify(owner_meta)])
        for child: Node in node.get_children():
            stack.append(child)

    rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if int(a["osm_id"]) != int(b["osm_id"]):
            return int(a["osm_id"]) < int(b["osm_id"])
        return str(a["node_path"]) < str(b["node_path"])
    )
    var output := {
        "schema": "grand-bruxelles-midi-automatic-road-visibility-mask-attribution-v2",
        "source_path": SOURCE_PATH,
        "source_sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
        "candidate_ids": ids,
        "candidate_count": ids.size(),
        "exact_candidate_geometry_node_count": exact_nodes,
        "hidden_candidate_geometry_node_count": hidden_nodes,
        "direct_self_hidden_geometry_node_count": direct_self_hidden_nodes,
        "unattributed_hidden_geometry_node_count": unattributed_hidden_nodes,
        "missing_script_ancestry_geometry_node_count": missing_script_ancestry_nodes,
        "rows": rows,
        "diagnostic_only": true,
        "osm_to_urbis_crosswalk_claimed": false,
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
        _fail("cannot persist visibility attribution")
        return
    file.store_string(JSON.stringify(output, "  ", true) + "\n")
    file.close()

    if exact_nodes == 0:
        _fail("source-backed candidates have no exact runtime geometry")
        return
    if hidden_nodes != exact_nodes:
        _fail("candidate visibility state is mixed; attribution no longer represents the reproduced blocker")
        return
    if direct_self_hidden_nodes != exact_nodes:
        _fail("candidate masking is not direct per-road-node visibility state")
        return
    if unattributed_hidden_nodes != 0:
        _fail("hidden candidate geometry lacks a concrete hidden-node/ancestor cause")
        return
    if missing_script_ancestry_nodes != 0:
        _fail("candidate geometry lacks script-bearing ancestry needed for ownership routing")
        return
    print("MIDI_AUTOMATIC_ROAD_VISIBILITY_MASK_ATTRIBUTION_GREEN: candidates=%d exact_nodes=%d hidden_nodes=%d direct_self_hidden=%d script_ancestry_missing=%d crosswalk_claimed=false destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [ids.size(), exact_nodes, hidden_nodes, direct_self_hidden_nodes, missing_script_ancestry_nodes])
    quit(0)
