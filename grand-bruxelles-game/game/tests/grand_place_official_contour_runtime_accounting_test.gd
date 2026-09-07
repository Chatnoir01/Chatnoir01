extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const EXPECTED_OWNER_COUNT := 23
const EXPECTED_CONTOUR_WALL_ROOF_SOURCE_TRIANGLE_COUNT := 1490
const EXPECTED_ZERO_SURFACE_COUNT := 9
const EXPECTED_RENDER_TRIANGLE_COUNT := EXPECTED_CONTOUR_WALL_ROOF_SOURCE_TRIANGLE_COUNT - EXPECTED_ZERO_SURFACE_COUNT
const EXPECTED_SOURCE_TRIANGLE_COUNT := 2170
const EXPECTED_GROUND_POLICY := "validated_source_not_mounted"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_OFFICIAL_CONTOUR_RUNTIME_ACCOUNTING_FAIL: %s" % message)
    quit(1)

func _mesh_triangle_count(instance: MeshInstance3D) -> int:
    if instance.mesh == null:
        return -1
    var faces := instance.mesh.get_faces()
    if faces.size() % 3 != 0:
        return -1
    return faces.size() / 3

func _collision_triangle_count(node: Node) -> int:
    var total := 0
    var found := false
    for child: Node in node.get_children():
        if child is CollisionShape3D:
            var collision_shape := child as CollisionShape3D
            if collision_shape.shape == null or not collision_shape.shape is ConcavePolygonShape3D:
                return -1
            var faces := (collision_shape.shape as ConcavePolygonShape3D).get_faces()
            if faces.size() % 3 != 0:
                return -1
            total += faces.size() / 3
            found = true
        var nested := _collision_triangle_count(child)
        if nested < 0:
            return -1
        if nested > 0:
            total += nested
            found = true
    return total if found else 0

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main

    for _frame: int in range(45):
        await process_frame

    var contour := root.get_node_or_null("GrandPlaceOfficialLod2Contour")
    if contour == null:
        _fail("autoload missing")
        return
    if not bool(contour.get("geometry_loaded")):
        _fail("geometry_loaded=false after settlement")
        return
    if int(contour.get("loaded_owner_count")) != EXPECTED_OWNER_COUNT:
        _fail("owner count drifted: %s" % str(contour.get("loaded_owner_count")))
        return
    if int(contour.get("wall_collision_owner_count")) != EXPECTED_OWNER_COUNT:
        _fail("collision owner count drifted: %s" % str(contour.get("wall_collision_owner_count")))
        return
    if int(contour.get("render_triangle_count")) != EXPECTED_RENDER_TRIANGLE_COUNT:
        _fail("mounted 23-owner wall/roof triangle count drifted: expected=%d (= %d source wall/roof - %d proven zero-surface) actual=%s" % [EXPECTED_RENDER_TRIANGLE_COUNT, EXPECTED_CONTOUR_WALL_ROOF_SOURCE_TRIANGLE_COUNT, EXPECTED_ZERO_SURFACE_COUNT, str(contour.get("render_triangle_count"))])
        return
    if int(contour.get_meta("official_source_owner_count", -1)) != 25:
        _fail("source owner metadata drifted")
        return
    if int(contour.get_meta("source_triangle_count", -1)) != EXPECTED_SOURCE_TRIANGLE_COUNT:
        _fail("source triangle metadata drifted")
        return
    if int(contour.get_meta("source_zero_surface_triangle_count", -1)) != EXPECTED_ZERO_SURFACE_COUNT:
        _fail("zero-surface metadata drifted")
        return
    if str(contour.get_meta("source_ground_surface_policy", "")) != EXPECTED_GROUND_POLICY:
        _fail("ground-surface policy drifted")
        return
    if bool(contour.get_meta("runtime_approved", true)) or bool(contour.get_meta("visual_acceptance", true)) or bool(contour.get_meta("jouable_authorized", true)):
        _fail("promotion rail opened")
        return

    var owner_roots := 0
    var materialized_triangles := 0
    var materialized_wall_triangles := 0
    var materialized_collision_triangles := 0
    var materialized_collision_owners := 0
    for child: Node in contour.get_children():
        if child is Node3D and child.name.begins_with("GrandPlaceOfficial_"):
            owner_roots += 1
            var owner_id := str(child.get_meta("building_id", "")).trim_prefix("https://databrussels.be/id/building/")
            if owner_id.is_empty():
                _fail("owner root missing exact building identity: %s" % child.name)
                return
            var wall := child.get_node_or_null("%s_WALLSURFACE" % owner_id)
            if wall == null or not wall is MeshInstance3D:
                _fail("owner missing mounted wall mesh: %s" % owner_id)
                return
            var wall_triangles := _mesh_triangle_count(wall as MeshInstance3D)
            if wall_triangles <= 0:
                _fail("owner wall mesh has invalid/empty triangle payload: %s count=%d" % [owner_id, wall_triangles])
                return
            materialized_triangles += wall_triangles
            materialized_wall_triangles += wall_triangles
            var collision_triangles := _collision_triangle_count(wall)
            if collision_triangles <= 0:
                _fail("owner wall mesh missing/invalid trimesh collision payload: %s count=%d" % [owner_id, collision_triangles])
                return
            if collision_triangles != wall_triangles:
                _fail("owner wall collision payload disagrees with rendered wall mesh: %s wall=%d collision=%d" % [owner_id, wall_triangles, collision_triangles])
                return
            materialized_collision_triangles += collision_triangles
            materialized_collision_owners += 1

            var roof := child.get_node_or_null("%s_ROOFSURFACE" % owner_id)
            if roof != null:
                if not roof is MeshInstance3D:
                    _fail("owner roof surface is not a mesh: %s" % owner_id)
                    return
                var roof_triangles := _mesh_triangle_count(roof as MeshInstance3D)
                if roof_triangles <= 0:
                    _fail("owner roof mesh has invalid/empty triangle payload: %s count=%d" % [owner_id, roof_triangles])
                    return
                materialized_triangles += roof_triangles
    if owner_roots != EXPECTED_OWNER_COUNT:
        _fail("materialized owner-root count drifted: expected=%d actual=%d" % [EXPECTED_OWNER_COUNT, owner_roots])
        return
    if materialized_collision_owners != EXPECTED_OWNER_COUNT:
        _fail("materialized collision-owner count drifted: expected=%d actual=%d" % [EXPECTED_OWNER_COUNT, materialized_collision_owners])
        return
    if materialized_collision_triangles != materialized_wall_triangles:
        _fail("aggregate wall collision payload disagrees with rendered wall payload: wall=%d collision=%d" % [materialized_wall_triangles, materialized_collision_triangles])
        return
    if materialized_triangles != EXPECTED_RENDER_TRIANGLE_COUNT:
        _fail("materialized mesh payload disagrees with runtime accounting: expected=%d actual=%d" % [EXPECTED_RENDER_TRIANGLE_COUNT, materialized_triangles])
        return
    if materialized_triangles != int(contour.get("render_triangle_count")):
        _fail("runtime render counter disagrees with materialized mesh payload: counter=%s mesh=%d" % [str(contour.get("render_triangle_count")), materialized_triangles])
        return

    print("GRAND_PLACE_OFFICIAL_CONTOUR_RUNTIME_ACCOUNTING_OK owners=23 collision_owners=23 materialized_collision_owners=23 contour_wall_roof_source_triangles=1490 excluded_zero_surface=9 mounted_wall_roof_triangles=1481 materialized_mesh_triangles=1481 collision_payload_matches_wall_mesh=true source_triangles=2170 ground_surface_policy=validated_source_not_mounted runtime_approved=false visual_acceptance=false jouable_authorized=false")
    quit(0)
