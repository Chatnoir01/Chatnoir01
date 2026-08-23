extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 180
const SETTLE_FRAMES := 12
const GATE_PATH := "res://data/qa/grand_place_facade_visual_gate.json"
const OUTPUT_DIR := "res://artifacts/grand-place-maison-winding-ab"
const CONTOUR_RUNTIME_NAME := "GrandPlaceCompleteContourRuntime"
const PRESENTATION_RUNTIME_NAME := "GrandPlaceOwnerIdentityPresentation"
const MAISON_DU_ROI_OWNER_ID := "1654360"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_MAISON_WINDING_AB_FAIL: %s" % message)
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
        if node != null and (property_name.is_empty() or node.get(property_name) == expected):
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

func _owner_center(contour: Node) -> Variant:
    var wall := contour.get_node_or_null("GrandPlaceContour_%s_WALLSURFACE" % MAISON_DU_ROI_OWNER_ID) as MeshInstance3D
    var roof := contour.get_node_or_null("GrandPlaceContour_%s_ROOFSURFACE" % MAISON_DU_ROI_OWNER_ID) as MeshInstance3D
    if wall == null or roof == null:
        return null
    var wall_bounds := _world_aabb(wall)
    var roof_bounds := _world_aabb(roof)
    var min_v := Vector3(minf(wall_bounds.position.x, roof_bounds.position.x), minf(wall_bounds.position.y, roof_bounds.position.y), minf(wall_bounds.position.z, roof_bounds.position.z))
    var max_v := Vector3(maxf(wall_bounds.end.x, roof_bounds.end.x), maxf(wall_bounds.end.y, roof_bounds.end.y), maxf(wall_bounds.end.z, roof_bounds.end.z))
    return (min_v + max_v) * 0.5

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

func _capture_png(filename: String) -> Image:
    for _frame: int in range(SETTLE_FRAMES):
        await process_frame
    _hide_non_facade_overlays(root)
    RenderingServer.force_draw()
    await process_frame
    _hide_non_facade_overlays(root)
    RenderingServer.force_draw()
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _fail("empty viewport image for %s" % filename)
        return null
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("unexpected viewport size for %s: %dx%d" % [filename, image.get_width(), image.get_height()])
        return null
    var output_path := "%s/%s" % [OUTPUT_DIR, filename]
    var absolute := ProjectSettings.globalize_path(output_path)
    var error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    if error != OK and error != ERR_ALREADY_EXISTS:
        _fail("cannot create winding evidence directory")
        return null
    error = image.save_png(absolute)
    if error != OK:
        _fail("cannot save %s: %s" % [filename, error_string(error)])
        return null
    return image

func _pixel_delta(before: Image, after: Image) -> Dictionary:
    if before == null or after == null or before.get_size() != after.get_size():
        return {}
    var changed := 0
    var sum_abs := 0.0
    var max_abs := 0.0
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := before.get_pixel(x, y)
            var b := after.get_pixel(x, y)
            var delta := (absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)) / 3.0
            sum_abs += delta
            max_abs = maxf(max_abs, delta)
            if delta > 0.001:
                changed += 1
    var total := WIDTH * HEIGHT
    return {"changed_pixels_gt_0_001":changed,"changed_fraction_gt_0_001":float(changed)/float(total),"mean_rgb_abs_delta":sum_abs/float(total),"max_rgb_abs_delta":max_abs}

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)
    var gate := _read_json(GATE_PATH)
    if gate.is_empty():
        _fail("facade visual gate is missing or malformed")
        return
    var gate_resolution: Array = gate.get("resolution", [])
    var camera_position: Array = gate.get("camera_position", [])
    if gate_resolution.size() != 2 or int(gate_resolution[0]) != WIDTH or int(gate_resolution[1]) != HEIGHT:
        _fail("gate resolution drifted")
        return
    if camera_position.size() != 3:
        _fail("frozen camera position is malformed")
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
    var presentation := await _wait_for_named_node(PRESENTATION_RUNTIME_NAME, "built", true)
    if presentation == null or bool(presentation.get("failed")):
        _fail("owner identity presentation did not become ready")
        return
    if not presentation.has_method("set_source_winding_diagnostic_cull_mode"):
        _fail("owner presentation does not expose bounded winding cull-mode diagnostic")
        return
    if int(presentation.get_meta("source_winding_diagnostic_cull_mode", -1)) != BaseMaterial3D.CULL_BACK:
        _fail("production winding state must default to CULL_BACK before diagnostic")
        return

    scene.process_mode = Node.PROCESS_MODE_DISABLED
    _hide_non_facade_overlays(root)

    var target_variant: Variant = _owner_center(contour)
    if target_variant == null:
        _fail("Maison du Roi exact owner surfaces are missing")
        return
    var target := target_variant as Vector3
    var frozen_camera_position := Vector3(float(camera_position[0]), float(camera_position[1]), float(camera_position[2]))
    var camera := Camera3D.new()
    camera.name = "GrandPlaceMaisonWindingABCamera"
    root.add_child(camera)
    camera.global_position = frozen_camera_position
    camera.fov = float(gate.get("fov_deg", 0.0))
    camera.look_at(target, Vector3.UP)
    camera.current = true

    if not bool(presentation.call("set_source_winding_diagnostic_cull_mode", BaseMaterial3D.CULL_BACK)):
        _fail("could not enforce Maison du Roi CULL_BACK state")
        return
    var cull_back := await _capture_png("maison_du_roi_cull_back.png")
    if cull_back == null:
        return

    if not bool(presentation.call("set_source_winding_diagnostic_cull_mode", BaseMaterial3D.CULL_FRONT)):
        _fail("could not enable diagnostic Maison du Roi CULL_FRONT state")
        return
    var cull_front := await _capture_png("maison_du_roi_cull_front.png")
    if cull_front == null:
        return

    if not bool(presentation.call("set_source_winding_diagnostic_cull_mode", BaseMaterial3D.CULL_DISABLED)):
        _fail("could not enable diagnostic Maison du Roi CULL_DISABLED state")
        return
    var cull_disabled := await _capture_png("maison_du_roi_cull_disabled.png")
    if cull_disabled == null:
        return

    var delta_front := _pixel_delta(cull_back, cull_front)
    var delta_disabled := _pixel_delta(cull_back, cull_disabled)
    if delta_front.is_empty() or delta_disabled.is_empty():
        _fail("could not compare winding diagnostic frames")
        return

    if not bool(presentation.call("set_source_winding_diagnostic_cull_mode", BaseMaterial3D.CULL_BACK)):
        _fail("could not restore production CULL_BACK state after diagnostic")
        return
    if int(presentation.get_meta("source_winding_diagnostic_cull_mode", -1)) != BaseMaterial3D.CULL_BACK:
        _fail("production winding state was not restored to CULL_BACK after diagnostic")
        return

    var report := {
        "schema": "grand-bruxelles-grand-place-maison-winding-ab-v2",
        "owner_id": MAISON_DU_ROI_OWNER_ID,
        "camera_position": camera_position.duplicate(true),
        "fov_deg": float(gate.get("fov_deg", 0.0)),
        "resolution": [WIDTH, HEIGHT],
        "target_method": "source_bbox_cluster_center",
        "state_a": {"cull_mode": "CULL_BACK", "png": "maison_du_roi_cull_back.png"},
        "state_b": {"cull_mode": "CULL_FRONT", "png": "maison_du_roi_cull_front.png"},
        "state_c": {"cull_mode": "CULL_DISABLED", "png": "maison_du_roi_cull_disabled.png"},
        "production_default_cull_mode": "CULL_BACK",
        "production_mitigation_authorized": false,
        "delta_cull_front_vs_back": delta_front,
        "delta_cull_disabled_vs_back": delta_disabled,
        "source_geometry_changed": false,
        "source_collision_changed": false,
        "human_review_required": true,
        "human_review_status": "pending",
    }
    if not _write_json("%s/maison_du_roi_winding_ab.json" % OUTPUT_DIR, report):
        _fail("could not write winding diagnostic report")
        return

    print("GRAND_PLACE_MAISON_WINDING_AB_OK front_changed_fraction=%.6f disabled_changed_fraction=%.6f production_default=cull_back human_review=pending" % [float(delta_front["changed_fraction_gt_0_001"]), float(delta_disabled["changed_fraction_gt_0_001"])])
    camera.queue_free()
    scene.queue_free()
    await process_frame
    quit(0)
