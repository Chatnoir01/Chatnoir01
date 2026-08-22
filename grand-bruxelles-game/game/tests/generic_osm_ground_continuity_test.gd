extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_ROAD_PREFIX := "Road_359177328_"
const SUPPORT_BODY_NAME := "GenericOsmSurfaceCollisionBody"
const MAX_SUPPORT_GAP_M := 0.035
const ROAD_HEIGHT_M := 0.10
const SIDEWALK_HEIGHT_M := 0.12
const HEIGHT_EPSILON_M := 0.001
const MAX_READY_FRAMES := 240

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GENERIC_OSM_GROUND_CONTINUITY_FAIL: %s" % message)
    quit(1)

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

func _classify_surfaces(roads_root: Node) -> Dictionary:
    var roads: Array[CSGBox3D] = []
    var sidewalks: Array[CSGBox3D] = []
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D:
            continue
        var box := child as CSGBox3D
        if box.name.begins_with("Road_") and absf(box.size.y - ROAD_HEIGHT_M) <= HEIGHT_EPSILON_M:
            roads.append(box)
        elif absf(box.size.y - SIDEWALK_HEIGHT_M) <= HEIGHT_EPSILON_M:
            sidewalks.append(box)
    return {"roads": roads, "sidewalks": sidewalks}

func _assert_supported(label: String, box: CSGBox3D, world: World3D) -> bool:
    var support_variant: Variant = _support_y(world, box.global_position)
    if support_variant == null:
        _fail("%s has no physical support ray hit" % label)
        return false
    var support_y := float(support_variant)
    var visual_top_y := _surface_top_y(box)
    var gap := visual_top_y - support_y
    print("GENERIC_OSM_GROUND_SAMPLE: label=%s visual_top_y=%.4f support_y=%.4f gap_m=%.4f" % [label, visual_top_y, support_y, gap])
    if absf(gap) > MAX_SUPPORT_GAP_M:
        _fail("%s visual/support gap %.4f m exceeds %.4f m" % [label, gap, MAX_SUPPORT_GAP_M])
        return false
    return true

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

    var roads_root: Node = null
    var road: CSGBox3D = null
    var surfaces := {}
    var support_body: StaticBody3D = null
    for _frame: int in range(MAX_READY_FRAMES):
        await physics_frame
        roads_root = scene.get_node_or_null("BrusselsOSM/GeneratedRoads")
        if roads_root == null:
            continue
        road = _find_anneessens_road(roads_root)
        surfaces = _classify_surfaces(roads_root)
        support_body = roads_root.get_node_or_null(SUPPORT_BODY_NAME) as StaticBody3D
        if road != null and (surfaces.get("sidewalks", []) as Array).size() >= 2 and support_body != null:
            await physics_frame
            break

    if roads_root == null:
        _fail("GeneratedRoads missing from production OSM scene")
        return
    if road == null:
        _fail("source-backed Anneessens road 359177328 is not rendered")
        return

    var roads := surfaces.get("roads", []) as Array
    var sidewalks := surfaces.get("sidewalks", []) as Array
    if roads.is_empty() or sidewalks.size() < 2:
        _fail("generic rendered support surfaces missing")
        return
    if support_body == null:
        _fail("generic OSM support body did not materialize")
        return
    if support_body.get_child_count() != 1:
        _fail("support body must contain exactly one compact collision shape, got %d" % support_body.get_child_count())
        return
    var support_node := support_body.get_child(0) as CollisionShape3D
    if support_node == null or not support_node.shape is ConcavePolygonShape3D:
        _fail("compact support shape is not ConcavePolygonShape3D")
        return

    var expected_triangles := (roads.size() + sidewalks.size()) * 2
    if int(support_body.get_meta("road_support_surfaces", -1)) != roads.size():
        _fail("road support surface accounting mismatch")
        return
    if int(support_body.get_meta("sidewalk_support_surfaces", -1)) != sidewalks.size():
        _fail("sidewalk support surface accounting mismatch")
        return
    if int(support_body.get_meta("support_shape_count", -1)) != 1:
        _fail("support shape count metadata mismatch")
        return
    if int(support_body.get_meta("support_triangle_count", -1)) != expected_triangles:
        _fail("support triangle accounting mismatch")
        return
    if str(support_body.get_meta("support_mode", "")) != "top_surfaces_only":
        _fail("support mode must remain top-surfaces-only")
        return
    if bool(support_body.get_meta("source_geometry_changed", true)) or bool(support_body.get_meta("source_height_inferred", true)):
        _fail("support runtime manufactured source geometry/height semantics")
        return

    var world := scene.get_world_3d()
    if world == null:
        _fail("production World3D missing")
        return
    if not _assert_supported("Anneessens road %s" % road.name, road, world):
        return
    if not _assert_supported("generic sidewalk A", sidewalks[0] as CSGBox3D, world):
        return
    if not _assert_supported("generic sidewalk B", sidewalks[1] as CSGBox3D, world):
        return

    print("GENERIC_OSM_GROUND_CONTINUITY_OK: road=%s roads=%d sidewalks=%d support_shapes=1 support_triangles=%d tolerance_m=%.3f source_geometry_unchanged=true source_height_inferred=false exact_bourse_scope=false" % [road.name, roads.size(), sidewalks.size(), expected_triangles, MAX_SUPPORT_GAP_M])
    quit(0)
