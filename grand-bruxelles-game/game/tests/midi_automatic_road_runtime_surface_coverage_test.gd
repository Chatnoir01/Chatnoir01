extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const OUTPUT_PATH := "res://artifacts/qa/midi_automatic_road_runtime_surface_coverage.json"
const MIDI_ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const MIDI_ANCHOR_ID := "midi"
const MAX_DISTANCE_M := 80.0
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AUTOMATIC_ROAD_RUNTIME_SURFACE_COVERAGE_FAIL: %s" % message)
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

func _is_renderable(node: GeometryInstance3D) -> bool:
    if not node.is_visible_in_tree():
        return false
    if node is MeshInstance3D:
        var mesh := (node as MeshInstance3D).mesh
        return mesh != null and mesh.get_surface_count() > 0
    if node is MultiMeshInstance3D:
        var mm := (node as MultiMeshInstance3D).multimesh
        return mm != null and mm.mesh != null and mm.mesh.get_surface_count() > 0 and mm.instance_count > 0 and mm.visible_instance_count != 0
    if node is CSGShape3D:
        return true
    return false

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

    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.own_world_3d = true
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    for _frame: int in range(36):
        await process_frame
        await physics_frame

    var candidate_set: Dictionary = {}
    for osm_id: int in ids:
        candidate_set[osm_id] = true

    var exact_geometry_count: Dictionary = {}
    var visible_geometry_count: Dictionary = {}
    var metadata_geometry_count: Dictionary = {}
    var generic_support_ids: Dictionary = {}
    var support_owner_nodes := 0
    var malformed_support_owner_nodes := 0
    var all_generic_support_ids: Dictionary = {}
    var all_road_named_visible := 0

    var stack: Array[Node] = [scene]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is GeometryInstance3D:
            var geometry := node as GeometryInstance3D
            var name := str(geometry.name)
            if name.begins_with("Road_") and _is_renderable(geometry):
                all_road_named_visible += 1
            for osm_id: int in ids:
                if name.begins_with("Road_%d_" % osm_id):
                    exact_geometry_count[osm_id] = int(exact_geometry_count.get(osm_id, 0)) + 1
                    if _is_renderable(geometry):
                        visible_geometry_count[osm_id] = int(visible_geometry_count.get(osm_id, 0)) + 1
                if geometry.has_meta("osm_id") and int(geometry.get_meta("osm_id")) == osm_id:
                    metadata_geometry_count[osm_id] = int(metadata_geometry_count.get(osm_id, 0)) + 1
        if str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")) == ROAD_SUPPORT_OWNER_ID:
            support_owner_nodes += 1
            var raw_ids: Variant = node.get_meta(ROAD_SUPPORT_OSM_IDS_META, [])
            if not raw_ids is Array or raw_ids.is_empty():
                malformed_support_owner_nodes += 1
            else:
                var local_seen: Dictionary = {}
                for raw_id: Variant in raw_ids:
                    if typeof(raw_id) != TYPE_INT or int(raw_id) <= 0 or local_seen.has(int(raw_id)):
                        malformed_support_owner_nodes += 1
                        break
                    var support_id := int(raw_id)
                    local_seen[support_id] = true
                    all_generic_support_ids[support_id] = true
                    if candidate_set.has(support_id):
                        generic_support_ids[support_id] = true
        for child: Node in node.get_children():
            stack.append(child)

    var rows: Array[Dictionary] = []
    var candidate_visible_count := 0
    var candidate_generic_support_count := 0
    for osm_id: int in ids:
        var visible := int(visible_geometry_count.get(osm_id, 0))
        var generic_support := generic_support_ids.has(osm_id)
        if visible > 0:
            candidate_visible_count += 1
        if generic_support:
            candidate_generic_support_count += 1
        rows.append({
            "osm_id": osm_id,
            "exact_named_geometry": int(exact_geometry_count.get(osm_id, 0)),
            "exact_visible_renderable_geometry": visible,
            "metadata_bound_geometry": int(metadata_geometry_count.get(osm_id, 0)),
            "generic_collision_support_registered": generic_support,
        })
        print("MIDI_RUNTIME_SURFACE_COVERAGE_ROW: osm_id=%d exact=%d visible=%d metadata=%d generic_support=%s" % [osm_id, int(exact_geometry_count.get(osm_id, 0)), visible, int(metadata_geometry_count.get(osm_id, 0)), str(generic_support)])

    var output := {
        "schema": "grand-bruxelles-midi-automatic-road-runtime-surface-coverage-v1",
        "source_path": SOURCE_PATH,
        "source_sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
        "candidate_ids": ids,
        "candidate_count": ids.size(),
        "candidate_visible_renderable_count": candidate_visible_count,
        "candidate_generic_collision_support_count": candidate_generic_support_count,
        "global_visible_road_named_geometry_count": all_road_named_visible,
        "generic_support_owner_node_count": support_owner_nodes,
        "generic_support_unique_road_id_count": all_generic_support_ids.size(),
        "malformed_generic_support_owner_node_count": malformed_support_owner_nodes,
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
        _fail("cannot persist runtime surface coverage")
        return
    file.store_string(JSON.stringify(output, "  ", true) + "\n")
    file.close()

    if malformed_support_owner_nodes != 0:
        _fail("generic collision support ownership metadata is malformed")
        return
    print("MIDI_AUTOMATIC_ROAD_RUNTIME_SURFACE_COVERAGE_GREEN: candidates=%d visible_candidates=%d generic_support_candidates=%d global_visible_road_geometry=%d generic_support_ids=%d crosswalk_claimed=false destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [ids.size(), candidate_visible_count, candidate_generic_support_count, all_road_named_visible, all_generic_support_ids.size()])
    quit(0)
