extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("URBIS_CELL_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var builder_script: Script = load("res://game/scripts/urbis_cell_builder.gd") as Script
    var streamer_script: Script = load("res://game/scripts/urbis_cell_streamer.gd") as Script
    var mask_script: Script = load("res://game/scripts/urbis_cell_osm_mask.gd") as Script
    if builder_script == null:
        _fail("urbis_cell_builder.gd did not load")
        return
    if streamer_script == null:
        _fail("urbis_cell_streamer.gd did not load")
        return
    if mask_script == null:
        _fail("urbis_cell_osm_mask.gd did not load")
        return

    var builder: Node3D = builder_script.new() as Node3D
    if builder == null:
        _fail("generic cell builder did not instantiate")
        return
    root.add_child(builder)
    await process_frame

    var data := {
        "format": "grand-bruxelles-urbis-cell-runtime-v1",
        "cell_id": "smoke-000-000",
        "street_surfaces": [
            {
                "id": "surface-1",
                "type": "S",
                "polygon": [[0.0, 0.0], [20.0, 0.0], [20.0, 8.0], [0.0, 8.0]],
            }
        ],
        "buildings": [
            {
                "id": "building-1",
                "height": 12.0,
                "footprint": [[25.0, 0.0], [35.0, 0.0], [35.0, 10.0], [25.0, 10.0]],
            }
        ],
    }
    builder.set("expected_cell_id", "smoke-000-000")
    if not bool(builder.call("build_from_data", data)):
        _fail("generic cell runtime was rejected")
        return
    await process_frame

    if builder.get_node_or_null("UrbISStreetSurfaces") == null:
        _fail("street surface root was not generated")
        return
    if builder.get_node_or_null("UrbISExactBuildings") == null:
        _fail("building root was not generated")
        return

    var streamer: Node3D = streamer_script.new() as Node3D
    if streamer == null:
        _fail("cell streamer did not instantiate")
        return
    var inside_distance: float = float(
        streamer.call("_distance_to_bounds", Vector2(5.0, 5.0), [0.0, 0.0, 10.0, 10.0])
    )
    var outside_distance: float = float(
        streamer.call("_distance_to_bounds", Vector2(13.0, 14.0), [0.0, 0.0, 10.0, 10.0])
    )
    if not is_zero_approx(inside_distance):
        _fail("inside cell distance should be zero")
        return
    if not is_equal_approx(outside_distance, 5.0):
        _fail("outside cell distance should be 5m, got %s" % outside_distance)
        return

    var index_path := "res://data/urbis/remaining_brussels/runtime_index.json"
    if not FileAccess.file_exists(index_path):
        _fail("ownership-aware runtime index is missing")
        return
    var index_parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(index_path))
    if typeof(index_parsed) != TYPE_DICTIONARY:
        _fail("runtime index is not valid JSON")
        return
    var runtime_index := index_parsed as Dictionary
    if str(runtime_index.get("format", "")) != "grand-bruxelles-urbis-runtime-index-v2":
        _fail("runtime index is not v2")
        return
    var reserved_midi := "bxl-e147500-n169500-s500"
    for raw_cell: Variant in runtime_index.get("cells", []):
        if typeof(raw_cell) == TYPE_DICTIONARY and str((raw_cell as Dictionary).get("cell_id", "")) == reserved_midi:
            _fail("reserved Midi cell leaked into remaining-Brussels streaming index")
            return

    var mask: Node = mask_script.new() as Node
    if mask == null:
        _fail("OSM streaming mask did not instantiate")
        return
    var osm_root := Node3D.new()
    root.add_child(osm_root)
    var roads := Node3D.new()
    roads.name = "GeneratedRoads"
    osm_root.add_child(roads)

    var visible_road := MeshInstance3D.new()
    visible_road.position = Vector3(5.0, 0.0, 5.0)
    visible_road.visible = true
    roads.add_child(visible_road)
    var prehidden_road := MeshInstance3D.new()
    prehidden_road.position = Vector3(6.0, 0.0, 6.0)
    prehidden_road.visible = false
    roads.add_child(prehidden_road)
    var outside_road := MeshInstance3D.new()
    outside_road.position = Vector3(20.0, 0.0, 20.0)
    roads.add_child(outside_road)
    await process_frame

    var changes: Array = []
    var hidden_count := int(mask.call("_mask_root", roads, [0.0, 0.0, 10.0, 10.0], changes))
    if hidden_count != 2:
        _fail("OSM mask should select two in-cell nodes, got %d" % hidden_count)
        return
    if visible_road.visible or prehidden_road.visible or not outside_road.visible:
        _fail("OSM mask visibility state is incorrect after masking")
        return

    mask.set("_masked_nodes_by_cell", {"test-cell": changes})
    mask.call("_on_cell_unloaded", "test-cell")
    if not visible_road.visible:
        _fail("visible OSM node was not restored after cell unload")
        return
    if prehidden_road.visible:
        _fail("pre-hidden OSM node was incorrectly made visible after cell unload")
        return
    if not outside_road.visible:
        _fail("outside OSM node changed visibility unexpectedly")
        return

    print("URBIS_CELL_SMOKE_OK: builder + streamer + ownership + OSM mask passed")
    builder.queue_free()
    osm_root.queue_free()
    streamer.queue_free()
    mask.queue_free()
    await process_frame
    quit(0)