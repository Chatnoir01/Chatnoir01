extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 180
const SETTLE_FRAMES := 12
const GATE_PATH := "res://data/qa/grand_place_facade_visual_gate.json"
const OUTPUT_DIR := "res://artifacts/grand-place-facade-evidence"
const CONTOUR_RUNTIME_NAME := "GrandPlaceCompleteContourRuntime"
const PRESENTATION_RUNTIME_NAME := "GrandPlaceOwnerIdentityPresentation"
const MAISON_DU_ROI_OWNER_ID := "1654360"
const EXPECTED_VIEWS := ["canonical", "cornet_renard", "brasseurs_rose_thabor", "maison_du_roi"]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_FACADE_CAPTURE_FAIL: %s" % message)
    quit(1)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    return parsed as Dictionary

func _write_json(path: String, value: Dictionary) -> bool:
    var absolute := ProjectSettings.globalize_path(path)
    var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if error != OK and error != ERR_ALREADY_EXISTS:
        return false
    var file := FileAccess.open(absolute, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(value, "  ") + "\n")
    return true

func _wait_for_named_node(node_name: String, property_name: String = "", expected: Variant = null) -> Node:
    for _frame: int in range(1200):
        var node := root.get_node_or_null(node_name)
        if node != null:
            if property_name.is_empty() or node.get(property_name) == expected:
                return node
        await process_frame
    return null

func _world_aabb(mesh: MeshInstance3D) -> AABB:
    var local := mesh.get_aabb()
    var first := mesh.global_transform * local.position
    var min_v := first
    var max_v := first
    for x: int in [0, 1]:
        for y: int in [0, 1]:
            for z: int in [0, 1]:
                var p := local.position + Vector3(local.size.x * x, local.size.y * y, local.size.z * z)
                var world := mesh.global_transform * p
                min_v = Vector3(minf(min_v.x, world.x), minf(min_v.y, world.y), minf(min_v.z, world.z))
                max_v = Vector3(maxf(max_v.x, world.x), maxf(max_v.y, world.y), maxf(max_v.z, world.z))
    return AABB(min_v, max_v - min_v)

func _owner_cluster_center(contour: Node, owner_ids: Array) -> Variant:
    var have_bounds := false
    var min_v := Vector3.ZERO
    var max_v := Vector3.ZERO
    for owner_id_variant: Variant in owner_ids:
        var owner_id := str(owner_id_variant)
        for suffix: String in ["WALLSURFACE", "ROOFSURFACE"]:
            var mesh := contour.get_node_or_null("GrandPlaceContour_%s_%s" % [owner_id, suffix]) as MeshInstance3D
            if mesh == null:
                return null
            var bounds := _world_aabb(mesh)
            var local_min := bounds.position
            var local_max := bounds.end
            if not have_bounds:
                min_v = local_min
                max_v = local_max
                have_bounds = true
            else:
                min_v = Vector3(minf(min_v.x, local_min.x), minf(min_v.y, local_min.y), minf(min_v.z, local_min.z))
                max_v = Vector3(maxf(max_v.x, local_max.x), maxf(max_v.y, local_max.y), maxf(max_v.z, local_max.z))
    if not have_bounds:
        return null
    return (min_v + max_v) * 0.5

func _surface_facing_stats(mesh_instance: MeshInstance3D, camera_position: Vector3) -> Dictionary:
    if mesh_instance == null or mesh_instance.mesh == null:
        return {}
    var triangle_count := 0
    var front_count := 0
    var total_area := 0.0
    var front_area := 0.0
    var front_normal_area_sum := Vector3.ZERO
    var source_mesh: Mesh = mesh_instance.mesh
    for surface_index: int in range(source_mesh.get_surface_count()):
        var arrays: Array = source_mesh.surface_get_arrays(surface_index)
        if arrays.size() <= Mesh.ARRAY_VERTEX:
            continue
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var indices := PackedInt32Array()
        if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
            if typeof(arrays[Mesh.ARRAY_INDEX]) != TYPE_PACKED_INT32_ARRAY:
                _fail("source render mesh index array has unexpected type for %s" % mesh_instance.name)
                return {}
            indices = arrays[Mesh.ARRAY_INDEX]
        var element_count := indices.size() if not indices.is_empty() else vertices.size()
        if element_count % 3 != 0:
            _fail("source render mesh triangle stream is malformed for %s" % mesh_instance.name)
            return {}
        for element: int in range(0, element_count, 3):
            var ia := indices[element] if not indices.is_empty() else element
            var ib := indices[element + 1] if not indices.is_empty() else element + 1
            var ic := indices[element + 2] if not indices.is_empty() else element + 2
            if ia < 0 or ib < 0 or ic < 0 or ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
                _fail("source render mesh index is invalid for %s" % mesh_instance.name)
                return {}
            var a := mesh_instance.global_transform * vertices[ia]
            var b := mesh_instance.global_transform * vertices[ib]
            var c := mesh_instance.global_transform * vertices[ic]
            var cross := (b - a).cross(c - a)
            var cross_len := cross.length()
            if not is_finite(cross_len) or cross_len <= 0.000001:
                continue
            var area := cross_len * 0.5
            var normal := cross / cross_len
            var center := (a + b + c) / 3.0
            var to_camera := camera_position - center
            triangle_count += 1
            total_area += area
            if to_camera.length_squared() > 0.000001 and normal.dot(to_camera.normalized()) > 0.0:
                front_count += 1
                front_area += area
                front_normal_area_sum += normal * area
    if triangle_count <= 0 or total_area <= 0.0:
        return {}
    var dominant := Vector3.ZERO
    if front_normal_area_sum.length_squared() > 0.000001:
        dominant = front_normal_area_sum.normalized()
    return {
        "triangles": triangle_count,
        "front_facing_triangles": front_count,
        "total_area_m2": total_area,
        "front_facing_area_m2": front_area,
        "front_facing_area_ratio": front_area / total_area,
        "dominant_front_normal": [dominant.x, dominant.y, dominant.z],
    }

func _owner_surface_facing_measurement(contour: Node, owner_id: String, camera_position: Vector3) -> Dictionary:
    var wall := contour.get_node_or_null("GrandPlaceContour_%s_WALLSURFACE" % owner_id) as MeshInstance3D
    var roof := contour.get_node_or_null("GrandPlaceContour_%s_ROOFSURFACE" % owner_id) as MeshInstance3D
    if wall == null or roof == null:
        _fail("source owner surfaces missing for facing measurement: %s" % owner_id)
        return {}
    var wall_stats := _surface_facing_stats(wall, camera_position)
    var roof_stats := _surface_facing_stats(roof, camera_position)
    if wall_stats.is_empty() or roof_stats.is_empty():
        _fail("source owner facing measurement is empty: %s" % owner_id)
        return {}
    return {
        "owner_id": owner_id,
        "camera_position": [camera_position.x, camera_position.y, camera_position.z],
        "wall_triangles": int(wall_stats["triangles"]),
        "roof_triangles": int(roof_stats["triangles"]),
        "front_facing_wall_triangles": int(wall_stats["front_facing_triangles"]),
        "front_facing_roof_triangles": int(roof_stats["front_facing_triangles"]),
        "wall_area_m2": float(wall_stats["total_area_m2"]),
        "roof_area_m2": float(roof_stats["total_area_m2"]),
        "front_facing_wall_area_m2": float(wall_stats["front_facing_area_m2"]),
        "front_facing_roof_area_m2": float(roof_stats["front_facing_area_m2"]),
        "front_facing_wall_area_ratio": float(wall_stats["front_facing_area_ratio"]),
        "front_facing_roof_area_ratio": float(roof_stats["front_facing_area_ratio"]),
        "dominant_front_wall_normal": wall_stats["dominant_front_normal"],
        "dominant_front_roof_normal": roof_stats["dominant_front_normal"],
        "source_geometry_changed": false,
        "source_collision_changed": false,
    }

func _hide_non_facade_overlays(node: Node) -> void:
    for child: Node in node.get_children():
        if child is CanvasLayer:
            child.process_mode = Node.PROCESS_MODE_DISABLED
            (child as CanvasLayer).visible = false
        elif child is Control:
            child.process_mode = Node.PROCESS_MODE_DISABLED
            (child as Control).visible = false
        elif child is CharacterBody3D or child is VehicleBody3D or child is RigidBody3D:
            child.process_mode = Node.PROCESS_MODE_DISABLED
            if child is Node3D:
                (child as Node3D).visible = false
        elif child is Node3D and child.name in ["TrafficManager", "NPCManager", "PedestrianManager", "Vehicles", "Ambulances", "Player"]:
            child.process_mode = Node.PROCESS_MODE_DISABLED
            (child as Node3D).visible = false
        _hide_non_facade_overlays(child)

func _capture_view(view: Dictionary, contour: Node, camera: Camera3D) -> Dictionary:
    var view_id := str(view.get("id", ""))
    var method := str(view.get("target_method", ""))
    var target := Vector3.ZERO
    var manifest_view := {"id": view_id, "target_method": method, "png": "%s.png" % view_id}
    if method == "fixed_existing_witness":
        var raw_target: Array = view.get("target", [])
        if raw_target.size() != 3:
            _fail("fixed target malformed for %s" % view_id)
            return {}
        target = Vector3(float(raw_target[0]), float(raw_target[1]), float(raw_target[2]))
        manifest_view["target"] = raw_target.duplicate(true)
    elif method == "source_bbox_cluster_center":
        var owner_ids: Array = view.get("target_owner_ids", [])
        if owner_ids.is_empty():
            _fail("owner target set is empty for %s" % view_id)
            return {}
        var center: Variant = _owner_cluster_center(contour, owner_ids)
        if center == null:
            _fail("official source surfaces missing for %s" % view_id)
            return {}
        target = center as Vector3
        manifest_view["target_owner_ids"] = owner_ids.duplicate(true)
    else:
        _fail("unsupported target method %s for %s" % [method, view_id])
        return {}

    camera.look_at(target, Vector3.UP)
    for _frame: int in range(SETTLE_FRAMES):
        await process_frame
    _hide_non_facade_overlays(root)
    RenderingServer.force_draw()
    await process_frame
    _hide_non_facade_overlays(root)
    RenderingServer.force_draw()
    var image: Image = root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("empty viewport image for %s" % view_id)
        return {}
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("unexpected viewport size for %s: %dx%d" % [view_id, image.get_width(), image.get_height()])
        return {}
    var output_path := "%s/%s.png" % [OUTPUT_DIR, view_id]
    var absolute := ProjectSettings.globalize_path(output_path)
    var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if error != OK and error != ERR_ALREADY_EXISTS:
        _fail("cannot create evidence directory")
        return {}
    error = image.save_png(absolute)
    if error != OK:
        _fail("cannot save %s: %s" % [view_id, error_string(error)])
        return {}
    return manifest_view

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)
    var gate := _read_json(GATE_PATH)
    if gate.is_empty():
        _fail("facade visual gate is missing or malformed")
        return
    var gate_resolution: Array = gate.get("resolution", [])
    if gate_resolution.size() != 2 or int(gate_resolution[0]) != WIDTH or int(gate_resolution[1]) != HEIGHT:
        _fail("gate resolution drifted")
        return
    var frozen_views: Array = gate.get("views", [])
    if frozen_views.size() != EXPECTED_VIEWS.size():
        _fail("gate view count drifted")
        return
    var ids: Array = []
    for view_variant: Variant in frozen_views:
        if typeof(view_variant) != TYPE_DICTIONARY:
            _fail("gate view is malformed")
            return
        ids.append(str((view_variant as Dictionary).get("id", "")))
    if ids != EXPECTED_VIEWS:
        _fail("gate view IDs/order drifted")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    for _frame: int in range(WARMUP_FRAMES):
        await process_frame

    var contour := await _wait_for_named_node(CONTOUR_RUNTIME_NAME, "geometry_loaded", true)
    if contour == null:
        _fail("official Grand-Place contour runtime did not become ready")
        return
    var presentation := root.get_node_or_null(PRESENTATION_RUNTIME_NAME)
    if presentation != null:
        for _frame: int in range(600):
            if bool(presentation.get("built")):
                break
            if bool(presentation.get("failed")):
                _fail("owner identity presentation failed")
                return
            await process_frame
        if not bool(presentation.get("built")):
            _fail("owner identity presentation did not become ready")
            return

    scene.process_mode = Node.PROCESS_MODE_DISABLED
    _hide_non_facade_overlays(root)

    var camera_position: Array = gate.get("camera_position", [])
    if camera_position.size() != 3:
        _fail("frozen camera position is malformed")
        return
    var frozen_camera_position := Vector3(float(camera_position[0]), float(camera_position[1]), float(camera_position[2]))
    var source_surface_facing := _owner_surface_facing_measurement(contour, MAISON_DU_ROI_OWNER_ID, frozen_camera_position)
    if source_surface_facing.is_empty():
        return
    var camera := Camera3D.new()
    camera.name = "GrandPlaceFacadeEvidenceCamera"
    root.add_child(camera)
    camera.global_position = frozen_camera_position
    camera.fov = float(gate.get("fov_deg", 0.0))
    camera.current = true

    var manifest_views: Array = []
    for view_variant: Variant in frozen_views:
        var captured: Dictionary = await _capture_view(view_variant as Dictionary, contour, camera)
        if captured.is_empty():
            return
        manifest_views.append(captured)

    var base_sha := OS.get_environment("GB_EVIDENCE_BASE_SHA").strip_edges().to_lower()
    var head_sha := OS.get_environment("GB_EVIDENCE_HEAD_SHA").strip_edges().to_lower()
    if base_sha.length() != 40 or head_sha.length() != 40 or base_sha == head_sha:
        _fail("base/head SHA environment is missing, malformed or identical")
        return
    var manifest := {
        "schema": "grand-bruxelles-grand-place-facade-evidence-v1",
        "artifact_kind": "grand_place_facade_visual_witness",
        "producer": {"engine": "Godot", "version": Engine.get_version_info().get("string", "unknown"), "renderer": RenderingServer.get_current_rendering_driver_name()},
        "base_sha": base_sha,
        "head_sha": head_sha,
        "resolution": [WIDTH, HEIGHT],
        "camera_position": camera_position.duplicate(true),
        "fov_deg": float(gate.get("fov_deg", 0.0)),
        "human_review_required": true,
        "human_review_status": "pending",
        "source_surface_facing": source_surface_facing,
        "views": manifest_views,
    }
    if not _write_json("%s/manifest.json" % OUTPUT_DIR, manifest):
        _fail("could not write evidence manifest")
        return
    print("GRAND_PLACE_FACADE_CAPTURE_OK views=4 resolution=1280x720 human_review=pending maison_du_roi_front_wall_ratio=%.6f maison_du_roi_front_roof_ratio=%.6f" % [float(source_surface_facing["front_facing_wall_area_ratio"]), float(source_surface_facing["front_facing_roof_area_ratio"])])
    camera.queue_free()
    scene.queue_free()
    await process_frame
    quit(0)
