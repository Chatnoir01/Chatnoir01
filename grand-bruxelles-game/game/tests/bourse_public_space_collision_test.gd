extends SceneTree

const SCRIPT := preload("res://game/scripts/bourse_official_sidewalk_overlay.gd")

func _init() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_PUBLIC_SPACE_COLLISION_FAIL: %s" % message)
    quit(1)

func _run() -> void:
    var root := Node3D.new()
    root.name = "BoursePublicSpaceCollisionTestRoot"
    get_root().add_child(root)

    var sidewalk := Node3D.new()
    sidewalk.name = "BourseOfficialSidewalkOverlay"
    sidewalk.set_script(SCRIPT)
    root.add_child(sidewalk)
    await process_frame
    await physics_frame

    if int(sidewalk.call("official_sidewalk_overlay_count")) != 5:
        _fail("official sidewalk source feature count drifted")
        return
    if int(sidewalk.call("official_sidewalk_overlay_triangle_count")) != 52:
        _fail("official sidewalk render triangle count drifted")
        return
    if not sidewalk.has_method("collision_ready") or not bool(sidewalk.call("collision_ready")):
        _fail("official Bourse public-space collision is missing")
        return

    var body := sidewalk.get_node_or_null("OfficialBourseSidewalkCollision") as StaticBody3D
    if body == null:
        _fail("named public-space StaticBody3D is missing")
        return
    var shape_node := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if shape_node == null or shape_node.shape == null:
        _fail("public-space CollisionShape3D is missing")
        return
    if not shape_node.shape is ConcavePolygonShape3D:
        _fail("public-space collision must be a ConcavePolygonShape3D")
        return

    if str(body.get_meta("geometry_source", "")) != "same_official_urbis_sidewalk_mesh":
        _fail("collision provenance is not tied to the same official sidewalk mesh")
        return
    if str(body.get_meta("height_authority", "")) != "gameplay_base_surface_datum":
        _fail("collision height authority must stay the gameplay base-surface datum")
        return
    if bool(body.get_meta("source_elevation_authority", true)):
        _fail("collision incorrectly claims authoritative source elevation")
        return
    if not bool(body.get_meta("no_curb_height_inference", false)):
        _fail("collision must explicitly reject inferred curb height")
        return
    if bool(body.get_meta("presentation_bias_applied", true)):
        _fail("render-only presentation bias leaked into collision")
        return

    var faces := (shape_node.shape as ConcavePolygonShape3D).get_faces()
    if faces.size() != int(sidewalk.call("official_sidewalk_overlay_triangle_count")) * 3:
        _fail("collision/render triangle topology mismatch: faces=%d triangles=%d" % [faces.size(), int(sidewalk.call("official_sidewalk_overlay_triangle_count"))])
        return

    if not sidewalk.has_method("base_surface_y_m") or not sidewalk.has_method("presentation_y_m"):
        _fail("surface datum accessors missing")
        return
    var expected_y := float(sidewalk.call("base_surface_y_m"))
    var min_y := INF
    var max_y := -INF
    for vertex: Vector3 in faces:
        min_y = minf(min_y, vertex.y)
        max_y = maxf(max_y, vertex.y)
    if absf(min_y - expected_y) > 0.0001 or absf(max_y - expected_y) > 0.0001:
        _fail("collision Y must equal base surface: min=%.6f max=%.6f expected=%.6f" % [min_y, max_y, expected_y])
        return
    if absf(float(sidewalk.call("presentation_y_m")) - expected_y) < 0.001:
        _fail("render presentation layer is no longer separated from collision datum")
        return

    if not sidewalk.has_method("collision_triangle_count") or int(sidewalk.call("collision_triangle_count")) != 52:
        _fail("collision triangle metric drifted")
        return

    # Prove that the physics server can actually hit the generated public-space floor.
    # Using the first collision triangle centroid keeps the ray source-backed and avoids
    # introducing any independently authored Bourse test coordinate.
    if faces.size() < 3:
        _fail("collision faces are unexpectedly empty before raycast proof")
        return
    var centroid := (faces[0] + faces[1] + faces[2]) / 3.0
    var ray_from := Vector3(centroid.x, expected_y + 2.0, centroid.z)
    var ray_to := Vector3(centroid.x, expected_y - 2.0, centroid.z)
    var query := PhysicsRayQueryParameters3D.create(ray_from, ray_to)
    query.collide_with_bodies = true
    query.collide_with_areas = false
    query.collision_mask = body.collision_layer
    # Keep front-face semantics: a floor whose triangle winding only collides from below
    # is not considered a valid walkable public-space support.
    query.hit_back_faces = false
    var hit := root.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        _fail("physics raycast from above did not hit the official Bourse public-space collision")
        return
    if hit.get("collider") != body:
        _fail("physics raycast hit an unexpected collider instead of the official Bourse public-space body")
        return
    var hit_position: Vector3 = hit.get("position", Vector3.ZERO)
    if absf(hit_position.y - expected_y) > 0.001:
        _fail("physics raycast hit wrong Y: got=%.6f expected=%.6f" % [hit_position.y, expected_y])
        return

    print("BOURSE_PUBLIC_SPACE_COLLISION_OK: features=5 triangles=52 collision_y=%.3f render_y=%.3f raycast_y=%.3f provenance=%s" % [expected_y, float(sidewalk.call("presentation_y_m")), hit_position.y, str(body.get_meta("geometry_source", ""))])
    root.queue_free()
    quit(0)
