extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE := "res://data/osm/vertical_slice_01.game.json"
const OUTPUT := "res://artifacts/qa/midi_post_mask_automatic_road_readiness.json"
const MIDI := Vector2(-668.5, 627.84)
const MAX_DISTANCE_M := 80.0
const ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const SUPPORT_OWNER := "generic_osm_surface_collision_runtime"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_POST_MASK_AUTOMATIC_ROAD_READINESS_FAIL: %s" % message)
    quit(1)

func _candidate_ids() -> Array[int]:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE))
    if not parsed is Dictionary:
        return []
    var out: Array[int] = []
    for raw: Variant in (parsed as Dictionary).get("roads", []):
        if not raw is Dictionary:
            continue
        var road := raw as Dictionary
        if str(road.get("name", "")) != ROAD_NAME or not bool(road.get("drivable", false)):
            continue
        var nearest := INF
        for pair: Variant in road.get("points", []):
            if pair is Array and pair.size() == 2:
                nearest = minf(nearest, Vector2(float(pair[0]), float(pair[1])).distance_to(MIDI))
        if nearest <= MAX_DISTANCE_M:
            out.append(int(road.get("osm_id", 0)))
    out.sort()
    return out

func _renderable(node: GeometryInstance3D) -> bool:
    if not node.is_visible_in_tree():
        return false
    if node is MeshInstance3D:
        var mesh := (node as MeshInstance3D).mesh
        return mesh != null and mesh.get_surface_count() > 0
    return true

func _run() -> void:
    if not FileAccess.file_exists(SOURCE):
        _fail("source missing")
        return
    var ids := _candidate_ids()
    if ids.size() != 8:
        _fail("expected 8 exact Fonsny candidates, got %d" % ids.size())
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.own_world_3d = true
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    for _i: int in range(36):
        await process_frame
        await physics_frame

    var visible: Dictionary = {}
    var exact: Dictionary = {}
    var support: Dictionary = {}
    var malformed_support := false
    var stack: Array[Node] = [scene]
    while not stack.is_empty():
        var node := stack.pop_back()
        if node is GeometryInstance3D:
            var g := node as GeometryInstance3D
            for id: int in ids:
                if str(g.name).begins_with("Road_%d_" % id) or (g.has_meta("osm_id") and int(g.get_meta("osm_id")) == id):
                    exact[id] = int(exact.get(id, 0)) + 1
                    if _renderable(g):
                        visible[id] = int(visible.get(id, 0)) + 1
        if str(node.get_meta("grand_bruxelles_owner", "")) == SUPPORT_OWNER:
            var raw_ids: Variant = node.get_meta("road_support_osm_ids", [])
            if not raw_ids is Array:
                malformed_support = true
            else:
                for raw_id: Variant in raw_ids:
                    if typeof(raw_id) != TYPE_INT:
                        malformed_support = true
                    elif ids.has(int(raw_id)):
                        support[int(raw_id)] = true
        for child: Node in node.get_children():
            stack.append(child)

    var visible_candidates := 0
    var support_candidates := 0
    var rows: Array[Dictionary] = []
    for id: int in ids:
        var v := int(visible.get(id, 0))
        var s := support.has(id)
        if v > 0:
            visible_candidates += 1
        if s:
            support_candidates += 1
        rows.append({"osm_id": id, "exact_geometry": int(exact.get(id, 0)), "visible_geometry": v, "generic_player_support": s})

    var receipt := {
        "schema": "grand-bruxelles-midi-post-mask-automatic-road-readiness-v1",
        "source_sha256": FileAccess.get_sha256(SOURCE).to_lower(),
        "candidate_ids": ids,
        "candidate_count": ids.size(),
        "visible_candidate_count": visible_candidates,
        "generic_player_support_candidate_count": support_candidates,
        "rows": rows,
        "osm_to_urbis_crosswalk_claimed": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false
    }
    var absolute := ProjectSettings.globalize_path(OUTPUT)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var f := FileAccess.open(OUTPUT, FileAccess.WRITE)
    if f == null:
        _fail("cannot persist receipt")
        return
    f.store_string(JSON.stringify(receipt, "  ", true) + "\n")
    f.close()

    if malformed_support:
        _fail("malformed generic support ownership metadata")
        return
    if visible_candidates == 0:
        _fail("post-mask guard restored no source-backed Fonsny road visibility")
        return
    print("MIDI_POST_MASK_AUTOMATIC_ROAD_READINESS_OK: candidates=%d visible=%d generic_support=%d crosswalk=false advertisable=false" % [ids.size(), visible_candidates, support_candidates])
    quit(0)
