extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_ROAD_PREFIX := "Road_359177328_"
const MAX_SUPPORT_GAP_M := 0.035
const SIDEWALK_HEIGHT_M := 0.12
const SIDEWALK_SEARCH_RADIUS_M := 32.0

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GENERIC_OSM_GROUND_CONTINUITY_FAIL: %s" % message)
    quit(1)

func _xz_distance(a: Vector3, b: Vector3) -> float:
    return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _surface_top_y(box: CSGBox3D) -> float:
    return box.global_position.y + box.size.y * 0.5

func _support_y(world: World3D, point: Vector3) -> Variant:
    var query := PhysicsRayQueryParameters3D.create(
        Vector3(point.x, 5.0, point.z),
        Vector3(point.x, -5.0, point.z)
    )
    query.collision_mask = 1
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var hit := world.direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return null
    return float((hit.get("position", Vector3.ZERO) as Vector3).y)

func _find_anneessens_road(roads_root: Node) -> CSGBox3D:
    for child: Node in roads_root.get_children():
        if child is CSGBox3D and child.name.begins_with(ANNEESSENS_ROAD_PREFIX):
            return child as CSGBox3D
    return null

func _find_nearby_sidewalks(roads_root: Node, road: CSGBox3D) -> Array[CSGBox3D]:
    var sidewalks: Array[CSGBox3D] = []
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D:
            continue
        var box := child as CSGBox3D
        if absf(box.size.y - SIDEWALK_HEIGHT_M) > 0.001:
            continue
        if _xz_distance(box.global_position, road.global_position) <= SIDEWALK_SEARCH_RADIUS_M:
            sidewalks.append(box)
    return sidewalks

func _assert_supported(label: String, box: CSGBox3D, world: World3D) -> void:
    var support_variant: Variant = _support_y(world, box.global_position)
    if support_variant == null:
        _fail("%s has no physical support ray hit" % label)
        return
    var support_y := float(support_variant)
    var visual_top_y := _surface_top_y(box)
    var gap := visual_top_y - support_y
    print("GENERIC_OSM_GROUND_SAMPLE: label=%s visual_top_y=%.4f support_y=%.4f gap_m=%.4f collision=%s" % [
        label,
        visual_top_y,
        support_y,
        gap,
        str(box.use_collision),
    ])
    if absf(gap) > MAX_SUPPORT_GAP_M:
        _fail("%s visual/support gap %.4f m exceeds %.4f m" % [label, gap, MAX_SUPPORT_GAP_M])

func _run() -> void:
    var packed := load(MAIN_SCENE) as PackedScene
    if packed == null:
        _fail("production main scene missing")
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _fail("production main scene did not instantiate")
        return
    root.add_child(scene)

    for _frame: int in range(90):
        await physics_frame
        var ready_root := scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
        if ready_root != null:
            break

    var roads_root := scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
    if roads_root == null:
        _fail("GeneratedRoads missing from production OSM scene")
        return

    var road := _find_anneessens_road(roads_root)
    if road == null:
        _fail("source-backed Anneessens road 359177328 is not rendered")
        return

    var world := scene.get_world_3d()
    if world == null:
        _fail("production World3D missing")
        return

    _assert_supported("Anneessens road %s" % road.name, road, world)

    var sidewalks := _find_nearby_sidewalks(roads_root, road)
    if sidewalks.size() < 2:
        _fail("expected at least two generic sidewalks near Anneessens source road, got %d" % sidewalks.size())
        return
    _assert_supported("Anneessens sidewalk A", sidewalks[0], world)
    _assert_supported("Anneessens sidewalk B", sidewalks[1], world)

    print("GENERIC_OSM_GROUND_CONTINUITY_OK: road=%s sidewalks=%d tolerance_m=%.3f source_geometry_unchanged=true exact_bourse_scope=false" % [
        road.name,
        sidewalks.size(),
        MAX_SUPPORT_GAP_M,
    ])
    quit(0)
