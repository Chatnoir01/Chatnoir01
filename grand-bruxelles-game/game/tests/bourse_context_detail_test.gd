extends SceneTree

const BOURSE_ROUTE_ANCHOR := Vector2(81.54, -664.58)
const BOURSE_URBIS_CENTER := Vector2(172.5915, -672.2825)
const DETAIL_RADIUS_M := 180.0
const OFFICIAL_AXIS_ENDPOINTS: Array[Vector2] = [
    Vector2(94.07228826064966, -679.7570927080197),
    Vector2(98.96090281064971, -687.1860766580177),
    Vector2(114.20618808065774, -710.3535770180134),
    Vector2(129.03463705067406, -732.889563668021),
]


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("BOURSE_CONTEXT_DETAIL_FAIL: %s" % message)
    quit(1)


func _near(position: Vector3, anchor: Vector2) -> bool:
    return Vector2(position.x, position.z).distance_to(anchor) <= DETAIL_RADIUS_M


func _run() -> void:
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await process_frame

    var official_axis := scene.get_node_or_null("UrbISBourseAxisContext")
    if official_axis == null:
        _fail("official UrbIS Bourse axis context is missing from main scene")
        return
    if not official_axis.has_method("official_segment_count") or not official_axis.has_method("official_axis_endpoint_error_max_m"):
        _fail("official Bourse axis diagnostics are missing")
        return
    var official_segment_count := int(official_axis.official_segment_count())
    if official_segment_count != 3:
        _fail("expected exactly 3 source-backed Place de la Bourse axis segments; got %d" % official_segment_count)
        return
    var endpoint_error := float(official_axis.official_axis_endpoint_error_max_m(OFFICIAL_AXIS_ENDPOINTS))
    if endpoint_error > 0.01:
        _fail("official Bourse axis endpoints drifted by %.4f m" % endpoint_error)
        return

    var roads := scene.get_node_or_null("BrusselsOSM/GeneratedRoads") as Node3D
    if roads == null:
        _fail("generated road root is missing")
        return

    var bourse_sidewalks := 0
    for child in roads.get_children():
        if child is CSGBox3D:
            var box := child as CSGBox3D
            if absf(box.size.y - 0.12) < 0.001 and _near(box.position, BOURSE_ROUTE_ANCHOR):
                bourse_sidewalks += 1
    if bourse_sidewalks < 2:
        _fail("expected source-aligned Bourse road context to generate sidewalks; got %d" % bourse_sidewalks)
        return

    var city_builder := scene.get_node_or_null("BrusselsOSM")
    if city_builder == null:
        _fail("OSM city builder is missing")
        return
    if not city_builder.has_method("facade_window_count_near") or not city_builder.has_method("facade_window_bounds"):
        _fail("logical facade placement diagnostics are missing")
        return

    var bourse_urbis_windows := int(city_builder.facade_window_count_near(BOURSE_URBIS_CENTER, DETAIL_RADIUS_M))
    var bounds: Rect2 = city_builder.facade_window_bounds()
    print(
        "BOURSE_CONTEXT_DIAGNOSTIC: official_segments=%d endpoint_error=%.4f logical_bounds=[%.2f,%.2f]-[%.2f,%.2f] urbis_hits=%d" %
        [official_segment_count, endpoint_error, bounds.position.x, bounds.position.y, bounds.end.x, bounds.end.y, bourse_urbis_windows]
    )

    if bourse_urbis_windows < 1:
        _fail(
            "source-backed facade generation contains no logical window placements around the authoritative UrbIS Bourse center; " +
            "do not treat streetscape detail as visually populated"
        )
        return

    print(
        "BOURSE_CONTEXT_DETAIL_OK: 3 official axis segments exact to source endpoints, %d procedural sidewalks, %d logical facade windows inside %.0f m; exact ground surfaces are validated separately" %
        [bourse_sidewalks, bourse_urbis_windows, DETAIL_RADIUS_M]
    )
    scene.queue_free()
    quit(0)
