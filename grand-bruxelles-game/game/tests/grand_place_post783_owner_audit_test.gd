extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const REGISTRY_PATH := "res://data/qa/grand_place_post783_owner_candidates.json"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_POST783_OWNER_FAIL: " + message)
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

func _freeze_world(main: Node) -> void:
    var nodes: Array[Node] = []
    _walk(root, nodes)
    for node: Node in nodes:
        if node is CanvasLayer:
            (node as CanvasLayer).visible = false
        elif node is CanvasItem:
            (node as CanvasItem).visible = false
        if node.is_in_group("vehicle") or node.is_in_group("npc") or node.is_in_group("ambient_pedestrian") or node.is_in_group("ambient_traffic"):
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D:
                (node as Node3D).visible = false
    for path: String in ["Player", "PrototypeCar", "PhysicalCar", "PhysicalCarB", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration", "MidiUrbanLife"]:
        var n := main.get_node_or_null(path)
        if n != null:
            n.process_mode = Node.PROCESS_MODE_DISABLED
            if n is Node3D:
                (n as Node3D).visible = false

func _capture() -> Image:
    for _i: int in range(5):
        RenderingServer.force_draw()
        await process_frame
    var image := root.get_viewport().get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.get_width() != WIDTH or image.get_height() != HEIGHT:
        image.resize(WIDTH, HEIGHT, Image.INTERPOLATE_LANCZOS)
    return image

func _metrics(a: Image, b: Image) -> Dictionary:
    var changed3 := 0
    var changed8 := 0
    var min_x := WIDTH
    var min_y := HEIGHT
    var max_x := -1
    var max_y := -1
    for y: int in range(HEIGHT):
        for x: int in range(WIDTH):
            var ca := a.get_pixel(x, y)
            var cb := b.get_pixel(x, y)
            var delta := maxf(absf(ca.r-cb.r), maxf(absf(ca.g-cb.g), absf(ca.b-cb.b))) * 255.0
            if delta > 3.0:
                changed3 += 1
                min_x = mini(min_x, x)
                min_y = mini(min_y, y)
                max_x = maxi(max_x, x)
                max_y = maxi(max_y, y)
            if delta > 8.0:
                changed8 += 1
    var total := float(WIDTH * HEIGHT)
    return {
        "gt3_pixels": changed3,
        "gt8_pixels": changed8,
        "gt3_percent": 100.0 * float(changed3) / total,
        "gt8_percent": 100.0 * float(changed8) / total,
        "bbox_width": max_x-min_x+1 if max_x >= min_x else 0,
        "bbox_height": max_y-min_y+1 if max_y >= min_y else 0
    }

func _run() -> void:
    var registry := _read_json(REGISTRY_PATH)
    if str(registry.get("schema", "")) != "grand-bruxelles-grand-place-post783-owner-candidates-v1":
        _fail("registry invalid")
        return
    if bool(registry.get("runtime_changed", true)) or bool(registry.get("geometry_changed", true)) or bool(registry.get("implementation_authorized", true)):
        _fail("evidence-only contract drifted")
        return
    var camera_contract := _read_json(str(registry.get("camera_contract_path", "")))
    if str(camera_contract.get("schema", "")) != "grand-bruxelles-grand-place-clean-player-witness-v1" or int(camera_contract.get("source_pr", 0)) != 711:
        _fail("canonical camera contract drifted")
        return
    var camera_position := _v3(camera_contract.get("camera_position", []))
    var camera_target := _v3(camera_contract.get("camera_target", []))
    var camera_fov := float(camera_contract.get("camera_fov_deg", 0.0))
    if not camera_position.is_finite() or not camera_target.is_finite() or camera_fov <= 1.0:
        _fail("canonical camera invalid")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    var old_camera := main.get_viewport().get_camera_3d()
    if old_camera != null:
        old_camera.current = false
    var camera := Camera3D.new()
    camera.position = camera_position
    camera.fov = camera_fov
    main.add_child(camera)
    camera.look_at(camera_target, Vector3.UP)
    camera.current = true

    for _i: int in range(120):
        _freeze_world(main)
        await process_frame
    var baseline := await _capture()
    if baseline == null:
        _fail("baseline capture failed")
        return

    var rows: Array = []
    var winner := ""
    var winner_pixels := -1
    for raw: Variant in registry.get("candidates", []):
        if typeof(raw) != TYPE_DICTIONARY:
            _fail("candidate malformed")
            return
        var candidate: Dictionary = raw
        var node := root.get_node_or_null(str(candidate.get("node_path", "")))
        if node == null or not node is Node3D:
            _fail("production candidate missing: %s" % str(candidate.get("id", "")))
            return
        var n := node as Node3D
        var was_visible := n.visible
        n.visible = false
        for _j: int in range(5):
            _freeze_world(main)
            await process_frame
        var hidden := await _capture()
        n.visible = was_visible
        for _j: int in range(5):
            _freeze_world(main)
            await process_frame
        if hidden == null:
            _fail("candidate capture failed")
            return
        var m := _metrics(baseline, hidden)
        var row := candidate.duplicate(true)
        row["metrics"] = m
        rows.append(row)
        var pixels := int(m.get("gt3_pixels", 0))
        if str(candidate.get("id", "")) != "right_gallery_b1500" and pixels > winner_pixels:
            winner_pixels = pixels
            winner = str(candidate.get("id", ""))

    if winner == "" or winner_pixels <= 0:
        _fail("no remaining visible owner")
        return
    var evidence := {
        "schema":"grand-bruxelles-grand-place-post783-owner-audit-v1",
        "status":"evidence_only",
        "runtime_changed":false,
        "geometry_changed":false,
        "implementation_authorized":false,
        "winner":winner,
        "winner_gt3_pixels":winner_pixels,
        "candidates":rows
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open("res://artifacts/qa/grand_place_post783_owner_audit.json", FileAccess.WRITE)
    if file == null:
        _fail("cannot write evidence")
        return
    file.store_string(JSON.stringify(evidence, "  "))
    file.close()
    print("GRAND_PLACE_POST783_OWNER_JSON " + JSON.stringify(evidence))
    print("GRAND_PLACE_POST783_OWNER_OK winner=%s gt3_pixels=%d" % [winner, winner_pixels])
    quit(0)
