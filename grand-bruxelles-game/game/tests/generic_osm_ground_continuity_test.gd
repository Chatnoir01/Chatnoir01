extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const ANNEESSENS_ROAD_PREFIX := "Road_359177328_"
const SUPPORT_BODY_NAME := "GenericOsmSurfaceCollisionBody"
const MAX_SUPPORT_GAP_M := 0.035
const ROAD_HEIGHT_M := 0.10
const SIDEWALK_HEIGHT_M := 0.12
const HEIGHT_EPSILON_M := 0.001
const MAX_READY_FRAMES := 240
const EXPECTED_SUPPORT_COLLISION_LAYER := 1 << 19
const EXPECTED_SUPPORT_COLLISION_MASK := 0

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
    query.collision_mask = EXPECTED_SUPPORT_COLLISION_LAYER
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var hit := world.direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return null
    return float((hit.get("position", Vector3.ZERO) as Vector3).y)

func _find_anneessens_road(roads_root: Node) -> CSGBox3D:
    for child: Node in roads_root.get_children():
        if child is CSGBox3D and child.name.begins_with(ANNEESSENS_ROAD_PREFIX):
            var box := child as CSGBox3D
            if box.is_visible_in_tree():
                return box
    return null

func _classify_surfaces(roads_root: Node) -> Dictionary:
    var roads: Array[CSGBox3D] = []
    var sidewalks: Array[CSGBox3D] = []
    for child: Node in roads_root.get_children():
        if not child is CSGBox3D:
            continue
        var box := child as CSGBox3D
        if not box.is_visible_in_tree():
            continue
        if box.name.begins_with("Road_") and absf(box.size.y - ROAD_HEIGHT_M) <= HEIGHT_EPSILON_M:
            roads.append(box)
        elif absf(box.size.y - SIDEWALK_HEIGHT_M) <= HEIGHT_EPSILON_M:
            sidewalks.append(box)
    return {"roads": roads, "sidewalks": sidewalks}

func _contains_render_geometry(node: Node) -> bool:
    for child: Node in node.get_children():
        if child is GeometryInstance3D:
            return true
        if _contains_render_geometry(child):
            return true
    return false

func _assert_supported(label: String, box: CSGBox3D, world: World3D) -> bool:
    if not box.is_visible_in_tree():
        _fail("%s is hidden and must not be part of generic rendered support evidence" % label)
        return false
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
        _fail("source-backed Anneessens road 359177328 is not visibly rendered")
        return

    var roads := surfaces.get("roads", []) as Array
    var sidewalks := surfaces.get("sidewalks", []) as Array
    if roads.is_empty() or sidewalks.size() < 2:
        _fail("generic visibly rendered support surfaces missing")
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
    if _contains_render_geometry(support_body):
        _fail("physics-only support layer leaked GeometryInstance3D render content")
        return

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("canonical Player CharacterBody3D missing")
        return
    if support_body.collision_layer != EXPECTED_SUPPORT_COLLISION_LAYER:
        _fail("support collision layer drifted: got %d expected %d" % [support_body.collision_layer, EXPECTED_SUPPORT_COLLISION_LAYER])
        return
    if support_body.collision_mask != EXPECTED_SUPPORT_COLLISION_MASK:
        _fail("support collision mask drifted: got %d expected %d" % [support_body.collision_mask, EXPECTED_SUPPORT_COLLISION_MASK])
        return
    if (player.collision_mask & support_body.collision_layer) == 0:
        _fail("canonical Player collision mask does not query generic support layer")
        return

    var expected_triangles := (roads.size() + sidewalks.size()) * 2
    if int(support_body.get_meta("road_support_surfaces", -1)) != roads.size():
        _fail("visible road support surface accounting mismatch")
        return
    if int(support_body.get_meta("sidewalk_support_surfaces", -1)) != sidewalks.size():
        _fail("visible sidewalk support surface accounting mismatch")
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
    if not bool(support_body.get_meta("visible_surfaces_only", false)):
        _fail("generic support must exclude hidden/superseded OSM surfaces")
        return
    if not bool(support_body.get_meta("player_only_collision", false)):
        _fail("generic support must remain isolated to the canonical Player")
        return
    if int(support_body.get_meta("support_collision_layer", -1)) != EXPECTED_SUPPORT_COLLISION_LAYER:
        _fail("support collision layer metadata mismatch")
        return
    if int(support_body.get_meta("support_collision_mask", -1)) != EXPECTED_SUPPORT_COLLISION_MASK:
        _fail("support collision mask metadata mismatch")
        return
    if bool(support_body.get_meta("source_geometry_changed", true)) or bool(support_body.get_meta("source_height_inferred", true)):
        _fail("support runtime manufactured source geometry/height semantics")
        return
    if bool(support_body.get_meta("visual_output_changed", true)):
        _fail("physics support must not claim or introduce rendered geometry")
        return
    if int(support_body.get_meta("render_geometry_count", -1)) != 0:
        _fail("physics support render-geometry accounting must remain zero")
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

    print("GENERIC_OSM_GROUND_CONTINUITY_OK: road=%s visible_roads=%d visible_sidewalks=%d support_shapes=1 support_triangles=%d collision_layer=%d collision_mask=%d player_mask_overlap=true player_only_collision=true visible_surfaces_only=true tolerance_m=%.3f source_geometry_unchanged=true source_height_inferred=false render_geometry_count=0 exact_bourse_scope=false" % [road.name, roads.size(), sidewalks.size(), expected_triangles, EXPECTED_SUPPORT_COLLISION_LAYER, EXPECTED_SUPPORT_COLLISION_MASK, MAX_SUPPORT_GAP_M])
    quit(0)
