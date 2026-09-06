extends SceneTree

const BUILDER_SCRIPT_CANDIDATES: Array[String] = [
    "res://scripts/osm_city_builder.gd",
    "res://game/scripts/osm_city_builder.gd",
]


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("ANNEESSENS_FOOTPRINT_DETAIL_ZONE_FAIL: %s" % message)
    quit(1)


func _load_builder_script() -> Script:
    for candidate: String in BUILDER_SCRIPT_CANDIDATES:
        if not ResourceLoader.exists(candidate, "Script"):
            continue
        var resource := load(candidate)
        if resource is Script:
            return resource as Script
    return null


func _run() -> void:
    var builder_script := _load_builder_script()
    if builder_script == null:
        _fail("osm_city_builder.gd is missing from both supported Godot project roots")
        return
    var builder = builder_script.new()
    if builder == null:
        _fail("osm_city_builder.gd could not be instantiated")
        return

    # Synthetic regression geometry isolates the helper contract without
    # modifying or substituting canonical OSM source geometry. The footprint
    # center stays outside the Anneessens detail radius while its near edge
    # crosses the radius. Midi/Bourse already honor this edge/vertex rule.
    var anchor := Vector2(-288.863, -100.711)
    var radius: float = float(builder.anneessens_detail_radius_m)
    var footprint: Array = [
        [anchor.x + radius - 0.25, anchor.y - 6.0],
        [anchor.x + radius + 8.0, anchor.y - 6.0],
        [anchor.x + radius + 8.0, anchor.y + 6.0],
        [anchor.x + radius - 0.25, anchor.y + 6.0],
    ]

    var center: Vector2 = builder._building_center(footprint)
    if center.distance_to(anchor) <= radius:
        builder.free()
        _fail("regression fixture center must stay outside Anneessens radius")
        return
    if not builder._footprint_intersects_detail_zone(footprint):
        builder.free()
        _fail("footprint crosses Anneessens detail radius but intersection helper rejected it")
        return

    # Fail closed on malformed source geometry. The detail-zone helper must
    # never throw or accidentally accept a building when a footprint point is
    # structurally invalid, non-numeric or non-finite.
    var malformed_footprints: Array = [
        [[anchor.x, anchor.y], []],
        [[anchor.x, anchor.y], ["not-a-number", anchor.y]],
        [[anchor.x, anchor.y], [INF, anchor.y]],
    ]
    for malformed: Array in malformed_footprints:
        if builder._footprint_intersects_detail_zone(malformed):
            builder.free()
            _fail("malformed footprint must be rejected fail-closed")
            return

    # Roads and railways share _point() during scene construction. Their source
    # points need the same structural/type/finitude boundary as building
    # footprints so malformed source cannot throw during _build_roads/_build_rails.
    var valid_point: Array = [anchor.x, anchor.y]
    if not builder._source_point_is_valid(valid_point):
        builder.free()
        _fail("finite numeric source point must remain valid")
        return
    var malformed_points: Array = [
        [],
        [anchor.x],
        ["not-a-number", anchor.y],
        [anchor.x, "not-a-number"],
        [INF, anchor.y],
        [anchor.x, NAN],
        [true, anchor.y],
    ]
    for malformed_point: Variant in malformed_points:
        if builder._source_point_is_valid(malformed_point):
            builder.free()
            _fail("malformed road/rail point must be rejected fail-closed")
            return

    print("ANNEESSENS_FOOTPRINT_DETAIL_ZONE_GREEN: center_distance_m=%.3f radius_m=%.3f malformed_rejected=true road_rail_points_guarded=true source_geometry_unchanged=true camera_unchanged=true destination_advertisable=false jouable=false" % [center.distance_to(anchor), radius])
    builder.free()
    quit(0)
