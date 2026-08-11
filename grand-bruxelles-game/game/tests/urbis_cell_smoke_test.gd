extends SceneTree


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("URBIS_CELL_SMOKE_FAIL: %s" % message)
    quit(1)


func _run() -> void:
    var builder_script: Script = load("res://game/scripts/urbis_cell_builder.gd") as Script
    var streamer_script: Script = load("res://game/scripts/urbis_cell_streamer.gd") as Script
    if builder_script == null:
        _fail("urbis_cell_builder.gd did not load")
        return
    if streamer_script == null:
        _fail("urbis_cell_streamer.gd did not load")
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

    print("URBIS_CELL_SMOKE_OK: builder + streamer passed")
    builder.queue_free()
    streamer.queue_free()
    await process_frame
    quit(0)
