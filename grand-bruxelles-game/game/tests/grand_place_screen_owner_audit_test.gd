extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const REGISTRY_PATH := "res://data/qa/grand_place_screen_owner_candidates.json"
const OUTPUT_PATH := "res://artifacts/qa/grand_place_screen_owner_audit.json"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_SCREEN_OWNER_AUDIT_FAIL: " + message)
    quit(1)

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if typeof(parsed) == TYPE_DICTIONARY else {}

func _v3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2]))

func _walk(node: Node, out: Array[Node]) -> void:
    out.append(node)
    for child: Node in node.get_children():
        _walk(child, out)

func _mask_ui() -> void:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    for node: Node in nodes:
        if node is CanvasLayer:
            (node as CanvasLayer).visible = false
        if node is CanvasItem:
            (node as CanvasItem).visible = false

func _visible_canvas_count() -> int:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    var count := 0
    for node: Node in nodes:
        if node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
            count += 1
    return count

func _freeze_dynamics(main: Node) -> void:
    for group_name: String in ["vehicle", "npc"]:
        for node: Node in get_nodes_in_group(group_name):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCar", "PhysicalCarB", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var node := main.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false

func _capture(path: String) -> Image:
    for _frame: int in range(6):
        _mask_ui()
        RenderingServer.force_draw()
        await process_frame
    if _visible_canvas_count() != 0:
        return null
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    if image.save_png(path) != OK:
        return null
    return image

func _diff_metrics(baseline: Image, hidden: Image) -> Dictionary:
    var changed3 := 0
    var changed8 := 0
    var right_changed3 := 0
    var right_changed8 := 0
    var left_changed3 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var a := baseline.get_pixel(x, y)
            var b := hidden.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) * 255.0
            if delta > 3.0:
                changed3 += 1
                if x >= WIDTH / 2:
                    right_changed3 += 1
                else:
                    left_changed3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                changed8 += 1
                if x >= WIDTH / 2:
                    right_changed8 += 1
    var bbox_width := 0
    var bbox_height := 0
    var bbox_value: Variant = null
    if max_x >= min_x and max_y >= min_y:
        bbox_width = max_x - min_x + 1
        bbox_height = max_y - min_y + 1
        bbox_value = [min_x, min_y, max_x, max_y]
    var total := float(WIDTH * HEIGHT)
    var half_total := float((WIDTH / 2) * HEIGHT)
    return {
        "changed_gt3_pixels": changed3,
        "changed_gt8_pixels": changed8,
        "changed_gt3_percent": 100.0 * float(changed3) / total,
        "changed_gt8_percent": 100.0 * float(changed8) / total,
        "right_half_changed_gt3_pixels": right_changed3,
        "right_half_changed_gt8_pixels": right_changed8,
        "right_half_changed_gt3_percent": 100.0 * float(right_changed3) / half_total,
        "right_half_changed_gt8_percent": 100.0 * float(right_changed8) / half_total,
        "left_half_changed_gt3_pixels": left_changed3,
        "bbox": bbox_value,
        "bbox_width_px": bbox_width,
        "bbox_height_px": bbox_height,
    }

func _run() -> void:
    var registry := _read_json(REGISTRY_PATH)
    if registry.is_empty() or str(registry.get("schema", "")) != "grand-bruxelles-grand-place-screen-owner-candidates-v1":
        _fail("candidate registry missing or invalid")
        return
    var camera_path := str(registry.get("camera_contract_path", ""))
    if camera_path != "res://data/qa/grand_place_clean_player_witness.json":
        _fail("registry must use shared #753 camera contract")
        return
    var camera_contract := _read_json(camera_path)
    if camera_contract.is_empty() or str(camera_contract.get("schema", "")) != "grand-bruxelles-grand-place-clean-player-witness-v1":
        _fail("canonical camera contract missing or invalid")
        return
    if int(camera_contract.get("source_pr", 0)) != 711:
        _fail("canonical camera provenance drifted")
        return
    var resolution: Variant = camera_contract.get("resolution", [])
    if typeof(resolution) != TYPE_ARRAY or resolution.size() != 2 or int(resolution[0]) != WIDTH or int(resolution[1]) != HEIGHT:
        _fail("canonical camera resolution drifted")
        return
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var camera_fov := float(camera_contract.get("camera_fov_deg", 0.0))
    if not camera_position.is_finite() or not camera_target.is_finite() or camera_fov <= 1.0 or camera_fov >= 179.0:
        _fail("canonical camera values invalid")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main

    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.name = "GrandPlaceScreenOwnerAuditCamera"
    camera.position = camera_position
    camera.fov = camera_fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true

    var candidates: Array = registry.get("candidates", [])
    if candidates.is_empty():
        _fail("candidate registry empty")
        return

    for _frame: int in range(120):
        _freeze_dynamics(main)
        _mask_ui()
        await process_frame

    var baseline := await _capture("/tmp/grand-place-screen-owner-baseline.png")
    if baseline == null:
        _fail("baseline capture failed")
        return

    var results: Array[Dictionary] = []
    var missing: Array[String] = []
    var right_winner_id := ""
    var right_winner_pixels := -1
    var right_winner_kind := ""
    var right_winner_role := ""

    for raw_candidate: Variant in candidates:
        if typeof(raw_candidate) != TYPE_DICTIONARY:
            _fail("malformed candidate row")
            return
        var candidate: Dictionary = raw_candidate
        var candidate_id := str(candidate.get("id", ""))
        var node_path := str(candidate.get("node_path_from_root", ""))
        if candidate_id == "" or node_path == "":
            _fail("candidate id/path missing")
            return
        var node := root.get_node_or_null(node_path)
        if node == null or not node is Node3D:
            missing.append(candidate_id)
            continue
        var node3d := node as Node3D
        var was_visible := node3d.visible
        node3d.visible = false
        for _frame: int in range(5):
            _freeze_dynamics(main)
            _mask_ui()
            RenderingServer.force_draw()
            await process_frame
        var hidden_path := "/tmp/grand-place-screen-owner-%s-hidden.png" % candidate_id
        var hidden := await _capture(hidden_path)
        node3d.visible = was_visible
        for _frame: int in range(5):
            _freeze_dynamics(main)
            _mask_ui()
            RenderingServer.force_draw()
            await process_frame
        if hidden == null:
            _fail("capture failed for candidate %s" % candidate_id)
            return
        var metrics := _diff_metrics(baseline, hidden)
        var row: Dictionary = candidate.duplicate(true)
        row["metrics"] = metrics
        row["hidden_capture"] = hidden_path
        results.append(row)
        var kind := str(candidate.get("kind", ""))
        if "architectural" in kind:
            var right_pixels := int(metrics.get("right_half_changed_gt3_pixels", 0))
            if right_pixels > right_winner_pixels:
                right_winner_pixels = right_pixels
                right_winner_id = candidate_id
                right_winner_kind = kind
                right_winner_role = str(candidate.get("role", ""))

    if not missing.is_empty():
        _fail("expected production candidate nodes missing: %s" % ", ".join(missing))
        return
    if right_winner_id == "" or right_winner_pixels <= 0:
        _fail("no architectural candidate owns visible right-half pixels")
        return

    var winner_requires_drilldown := false
    for row: Dictionary in results:
        if str(row.get("id", "")) == right_winner_id:
            winner_requires_drilldown = bool(row.get("requires_drilldown_if_dominant", false))
            break

    var evidence := {
        "schema": "grand-bruxelles-grand-place-screen-owner-audit-v1",
        "status": "evidence_only",
        "runtime_changed": false,
        "camera_contract_path": camera_path,
        "camera_source_pr": 711,
        "camera_position": [camera_position.x, camera_position.y, camera_position.z],
        "camera_target": [camera_target.x, camera_target.y, camera_target.z],
        "camera_fov_deg": camera_fov,
        "resolution": [WIDTH, HEIGHT],
        "screen_region_of_interest": "right_half",
        "baseline_capture": "/tmp/grand-place-screen-owner-baseline.png",
        "candidates": results,
        "decision": {
            "right_half_architectural_owner_id": right_winner_id,
            "right_half_architectural_owner_kind": right_winner_kind,
            "right_half_architectural_owner_role": right_winner_role,
            "right_half_changed_gt3_pixels": right_winner_pixels,
            "requires_generic_building_drilldown": winner_requires_drilldown,
            "next_visual_candidate_approved": false,
            "reason": "This audit identifies screen ownership only. Previous human-failure history and source strategy must be checked before any visual implementation."
        }
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("cannot write evidence JSON")
        return
    file.store_string(JSON.stringify(evidence, "  "))
    file.close()
    print("GRAND_PLACE_SCREEN_OWNER_AUDIT_JSON " + JSON.stringify(evidence))
    print("GRAND_PLACE_SCREEN_OWNER_AUDIT_OK owner=%s kind=%s right_pixels=%d drilldown=%s" % [right_winner_id, right_winner_kind, right_winner_pixels, str(winner_requires_drilldown).to_lower()])
    quit(0)
