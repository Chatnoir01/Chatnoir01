extends SceneTree

const DATA_PATH := "res://data/urbis/bourse_official_sidewalks.game.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_SIDEWALK_RUNTIME_FAIL: %s" % message)
    quit(1)

func _open_vertex_count(raw_ring: Array) -> int:
    if raw_ring.size() < 3:
        return 0
    var count := raw_ring.size()
    var first: Variant = raw_ring[0]
    var last: Variant = raw_ring[count - 1]
    if typeof(first) == TYPE_ARRAY and typeof(last) == TYPE_ARRAY and first == last:
        count -= 1
    return count

func _run() -> void:
    if not FileAccess.file_exists(DATA_PATH):
        _fail("official sidewalk data missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("official sidewalk data invalid JSON")
        return
    var data := parsed as Dictionary
    if str(data.get("schema", "")) != "grand-bruxelles-bourse-official-sidewalk-runtime-v1":
        _fail("unsupported sidewalk schema")
        return
    var selection: Dictionary = data.get("selection", {})
    var rows: Array = data.get("sidewalks", [])
    if int(selection.get("feature_count", -1)) != 16 or rows.size() != 16:
        _fail("A1 requires exactly 16 bounded official sidewalk polygons")
        return
    var added: Array = selection.get("a1_added_source_ids", [])
    var legacy: Array = selection.get("a1_legacy_source_ids", [])
    if legacy.size() != 5 or added.size() != 11:
        _fail("A1 provenance must preserve 5 legacy + 11 added source IDs")
        return
    if bool(selection.get("geography_expanded", true)):
        _fail("A1 must not expand geography")
        return
    if bool(data.get("curb_elevation_resolved", true)):
        _fail("curb elevation must remain unresolved")
        return
    if not bool(data.get("presentation_height_is_renderer_bias_only", false)):
        _fail("renderer-only height provenance missing")
        return

    var expected_vertices := 0
    var expected_triangles := 0
    for raw_row: Variant in rows:
        if typeof(raw_row) != TYPE_DICTIONARY:
            _fail("sidewalk row is not a dictionary")
            return
        var row := raw_row as Dictionary
        var rings: Array = row.get("world_rings_xz", [])
        if rings.size() != 1 or typeof(rings[0]) != TYPE_ARRAY:
            _fail("A1 runtime supports exactly one exterior ring per sidewalk")
            return
        var open_vertices := _open_vertex_count(rings[0] as Array)
        if open_vertices < 3:
            _fail("invalid sidewalk ring")
            return
        expected_vertices += open_vertices
        expected_triangles += open_vertices - 2

    if expected_vertices != 272 or expected_triangles != 240:
        _fail("A1 source-derived vertex/triangle totals drifted")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame
    await process_frame
    await process_frame
    var overlay := scene.get_node_or_null("BourseFrontWallReveal/OfficialSidewalkOverlay")
    if overlay == null:
        _fail("official sidewalk overlay missing")
        return
    if int(overlay.official_sidewalk_overlay_count()) != 16:
        _fail("runtime did not mount all 16 official bounded sidewalk polygons")
        return
    if int(overlay.official_sidewalk_overlay_vertex_count()) != expected_vertices:
        _fail("runtime sidewalk vertex count does not match source")
        return
    if int(overlay.official_sidewalk_overlay_triangle_count()) != expected_triangles:
        _fail("runtime sidewalk triangle count does not match source")
        return
    if not bool(overlay.sidewalk_overlay_height_is_renderer_bias_only()):
        _fail("overlay must not claim physical curb elevation")
        return
    print(
        "BOURSE_SIDEWALK_RUNTIME_OK: polygons=16 vertices=%d triangles=%d a1_added=11 geography_expanded=false curb_elevation_resolved=false" %
        [expected_vertices, expected_triangles]
    )
    scene.queue_free()
    quit(0)
