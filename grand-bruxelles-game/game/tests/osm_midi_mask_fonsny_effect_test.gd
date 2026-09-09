extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const OUTPUT_PATH := "res://artifacts/qa/osm_midi_mask_fonsny_effect.json"
const MIDI_ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const MIDI_ANCHOR_ID := "midi"
const MAX_DISTANCE_M := 80.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("OSM_MIDI_MASK_FONSNY_EFFECT_FAIL: %s" % message)
    quit(1)

func _candidate_ids(document: Dictionary) -> Array[int]:
    var anchor := Vector2(INF, INF)
    var corridor: Variant = document.get("corridor", {})
    if corridor is Dictionary:
        var anchors: Variant = (corridor as Dictionary).get("anchors", [])
        if anchors is Array:
            for raw: Variant in anchors:
                if raw is Dictionary and str((raw as Dictionary).get("id", "")) == MIDI_ANCHOR_ID:
                    anchor = Vector2(float((raw as Dictionary).get("x", INF)), float((raw as Dictionary).get("z", INF)))
                    break
    if not anchor.is_finite():
        return []
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
        var nearest := INF
        var points: Variant = road.get("points", [])
        if not points is Array:
            continue
        for pair: Variant in points:
            if pair is Array and pair.size() == 2:
                nearest = minf(nearest, Vector2(float(pair[0]), float(pair[1])).distance_to(anchor))
        if nearest <= MAX_DISTANCE_M:
            var osm_id := int(road.get("osm_id", 0))
            if osm_id > 0:
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
    return node is CSGShape3D

func _run() -> void:
    if not FileAccess.file_exists(SOURCE_PATH):
        _fail("source unavailable")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    if not parsed is Dictionary:
        _fail("source JSON invalid")
        return
    var ids := _candidate_ids(parsed as Dictionary)
    if ids.size() != 8:
        _fail("expected exact 8 Fonsny source candidates, got %d" % ids.size())
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

    var exact_counts: Dictionary = {}
    var visible_counts: Dictionary = {}
    var stack: Array[Node] = [scene]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is GeometryInstance3D:
            var geometry := node as GeometryInstance3D
            var node_name := str(geometry.name)
            for osm_id: int in ids:
                if node_name.begins_with("Road_%d_" % osm_id):
                    exact_counts[osm_id] = int(exact_counts.get(osm_id, 0)) + 1
                    if _is_renderable(geometry):
                        visible_counts[osm_id] = int(visible_counts.get(osm_id, 0)) + 1
        for child: Node in node.get_children():
            stack.append(child)

    var rows: Array[Dictionary] = []
    var exact_total := 0
    var visible_total := 0
    var visible_candidate_count := 0
    for osm_id: int in ids:
        var exact := int(exact_counts.get(osm_id, 0))
        var visible := int(visible_counts.get(osm_id, 0))
        if exact <= 0:
            _fail("missing exact runtime geometry for road-%d" % osm_id)
            return
        exact_total += exact
        visible_total += visible
        if visible > 0:
            visible_candidate_count += 1
        rows.append({"osm_id": osm_id, "exact_geometry": exact, "visible_renderable_geometry": visible})
        print("OSM_MIDI_MASK_FONSNY_EFFECT_ROW: osm_id=%d exact=%d visible=%d" % [osm_id, exact, visible])

    var output := {
        "schema": "grand-bruxelles-osm-midi-mask-fonsny-effect-v1",
        "source_path": SOURCE_PATH,
        "source_sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
        "candidate_ids": ids,
        "candidate_count": ids.size(),
        "exact_geometry_count": exact_total,
        "visible_renderable_geometry_count": visible_total,
        "visible_candidate_count": visible_candidate_count,
        "historical_pre_fix_exact_geometry_count": 29,
        "historical_pre_fix_visible_renderable_geometry_count": 0,
        "changed_from_historical_pre_fix_visibility": visible_total > 0,
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
        _fail("cannot persist effect evidence")
        return
    file.store_string(JSON.stringify(output, "  ", true) + "\n")
    file.close()
    print("OSM_MIDI_MASK_FONSNY_EFFECT_OK: candidates=%d exact=%d visible=%d visible_candidates=%d diagnostic_only=true" % [ids.size(), exact_total, visible_total, visible_candidate_count])
    quit(0)
