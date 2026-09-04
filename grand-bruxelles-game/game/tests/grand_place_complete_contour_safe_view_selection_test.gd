extends SceneTree

const CONTRACT_PATH := "res://data/qa/grand_place_complete_contour_safe_view_contract.json"
const WARMUP_FRAMES := 140

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("GRAND_PLACE_SAFE_VIEW_SELECTION_FAIL: %s" % message)
    quit(1)

func _read_contract() -> Dictionary:
    if not FileAccess.file_exists(CONTRACT_PATH):
        return {}
    var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
    return value if typeof(value) == TYPE_DICTIONARY else {}

func _exact_vec3(raw: Variant) -> Vector3:
    if typeof(raw) != TYPE_ARRAY or raw.size() != 3:
        return Vector3.INF
    for component: Variant in raw:
        var t := typeof(component)
        if t != TYPE_INT and t != TYPE_FLOAT:
            return Vector3.INF
    var value := Vector3(float(raw[0]), float(raw[1]), float(raw[2]))
    return value if value.is_finite() else Vector3.INF

func _matches_numeric_sequence(raw: Variant, expected: Array) -> bool:
    if typeof(raw) != TYPE_ARRAY or raw.size() != expected.size():
        return false
    for index: int in range(expected.size()):
        var component: Variant = raw[index]
        var component_type := typeof(component)
        if component_type != TYPE_INT and component_type != TYPE_FLOAT:
            return false
        var numeric := float(component)
        if not is_finite(numeric) or numeric != float(expected[index]):
            return false
    return true

func _freeze_scene(scene: Node) -> void:
    for path: String in ["Player", "PrototypeCar", "MidiUrbanLife", "TrafficManager", "NpcPopulationDirector", "NpcRuntimeIntegration"]:
        var node := scene.get_node_or_null(path)
        if node != null:
            node.process_mode = Node.PROCESS_MODE_DISABLED
            if node is Node3D and path in ["Player", "PrototypeCar", "MidiUrbanLife", "TrafficManager"]:
                (node as Node3D).visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)

func _measure(world: World3D, camera_position: Vector3, target: Vector3) -> Dictionary:
    var segment := target - camera_position
    var segment_length := segment.length()
    if world == null or not camera_position.is_finite() or not target.is_finite() or not is_finite(segment_length) or segment_length <= 0.0001:
        return {}
    var query := PhysicsRayQueryParameters3D.create(camera_position, target)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var hit := world.direct_space_state.intersect_ray(query)
    var clearance := segment_length
    var collider_path := ""
    if not hit.is_empty():
        var hit_position: Variant = hit.get("position", null)
        if typeof(hit_position) != TYPE_VECTOR3 or not (hit_position as Vector3).is_finite():
            return {}
        clearance = camera_position.distance_to(hit_position as Vector3)
        var collider: Variant = hit.get("collider", null)
        if collider is Node:
            collider_path = str((collider as Node).get_path())
    if not is_finite(clearance) or clearance < 0.0 or clearance > segment_length + 0.001:
        return {}
    return {
        "clearance_m": clearance,
        "segment_m": segment_length,
        "clearance_ratio": clearance / segment_length,
        "collider_path": collider_path,
        "hit": not hit.is_empty(),
    }

func _run() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 1:
        _fail("expected output JSON path")
        return
    var output_path := str(args[0])
    var contract := _read_contract()
    if str(contract.get("schema", "")) != "grand-bruxelles-grand-place-safe-view-selection-v1":
        _fail("safe-view contract missing")
        return
    var seed_contract: Dictionary = contract.get("camera_seed", {})
    var seed_position := _exact_vec3(seed_contract.get("position", []))
    var target := _exact_vec3(seed_contract.get("target", []))
    if not seed_position.is_finite() or not target.is_finite():
        _fail("invalid seed camera")
        return
    var candidate_yaws: Variant = contract.get("candidate_yaws_degrees", [])
    var quadrants: Variant = contract.get("quadrants", [])
    var expected_yaws: Array = [0, 45, 90, 135, 180, 225, 270, 315]
    var expected_quadrants: Array = [
        {"id": "q0", "candidate_yaws_degrees": [0, 45]},
        {"id": "q1", "candidate_yaws_degrees": [90, 135]},
        {"id": "q2", "candidate_yaws_degrees": [180, 225]},
        {"id": "q3", "candidate_yaws_degrees": [270, 315]},
    ]
    if not _matches_numeric_sequence(candidate_yaws, expected_yaws) or typeof(quadrants) != TYPE_ARRAY or quadrants.size() != expected_quadrants.size():
        _fail("candidate set drifted")
        return
    for quadrant_index: int in range(expected_quadrants.size()):
        var raw_quadrant: Variant = quadrants[quadrant_index]
        var expected_quadrant: Dictionary = expected_quadrants[quadrant_index]
        if typeof(raw_quadrant) != TYPE_DICTIONARY:
            _fail("quadrant set drifted")
            return
        var quadrant: Dictionary = raw_quadrant
        if str(quadrant.get("id", "")) != str(expected_quadrant["id"]) or not _matches_numeric_sequence(quadrant.get("candidate_yaws_degrees", []), expected_quadrant["candidate_yaws_degrees"]):
            _fail("quadrant set drifted")
            return
    var rules: Dictionary = contract.get("selection_rule", {})
    if str(rules.get("metric", "")) != "physics_center_ray_clearance_ratio" or not bool(rules.get("select_exactly_one_per_quadrant", false)) or str(rules.get("winner", "")) != "maximum_clearance_ratio" or str(rules.get("tie_break", "")) != "lowest_yaw_degrees" or not bool(rules.get("selection_happens_before_png_capture", false)) or bool(rules.get("post_capture_reselection_allowed", true)):
        _fail("selection rule drifted")
        return

    seed(711753)
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    if scene == null:
        _fail("main scene did not instantiate")
        return
    _freeze_scene(scene)
    root.add_child(scene)

    var contour := root.get_node_or_null("GrandPlaceCompleteContourRuntime")
    if contour != null and contour.has_method("bind_scene"):
        contour.call("bind_scene", scene)
    for _frame: int in range(WARMUP_FRAMES):
        await process_frame
    for loader_name: String in ["GrandPlaceOfficialLod2", "GrandPlaceOfficialLod2Next"]:
        var loader := root.get_node_or_null(loader_name)
        if loader == null or not bool(loader.get("geometry_loaded")):
            _fail("official loader not ready: %s" % loader_name)
            return
    contour = root.get_node_or_null("GrandPlaceCompleteContourRuntime")
    if contour == null or not contour.has_method("ready_complete") or not bool(contour.call("ready_complete")) or bool(contour.call("failed")) or int(contour.call("owner_count")) != 23:
        _fail("complete contour runtime not ready")
        return
    var world: World3D = scene.get_world_3d()
    if world == null or not contour.has_method("world_matches") or not bool(contour.call("world_matches", world)):
        _fail("selection/runtime World3D mismatch")
        return

    var seed_offset := seed_position - target
    var measurements := {}
    for raw_yaw: Variant in candidate_yaws:
        if typeof(raw_yaw) != TYPE_INT and typeof(raw_yaw) != TYPE_FLOAT:
            _fail("non-numeric candidate yaw")
            return
        var yaw_degrees := int(raw_yaw)
        var rotated_offset := seed_offset.rotated(Vector3.UP, deg_to_rad(float(yaw_degrees)))
        var camera_position := target + rotated_offset
        if not camera_position.is_finite() or absf(rotated_offset.length() - seed_offset.length()) > 0.0001 or absf(camera_position.y - seed_position.y) > 0.0001:
            _fail("candidate violated frozen seed radius/height")
            return
        var measurement := _measure(world, camera_position, target)
        if measurement.is_empty():
            _fail("could not measure yaw %d" % yaw_degrees)
            return
        measurement["camera_position"] = [camera_position.x, camera_position.y, camera_position.z]
        measurements[str(yaw_degrees)] = measurement

    var selected: Array = []
    for raw_quadrant: Variant in quadrants:
        if typeof(raw_quadrant) != TYPE_DICTIONARY:
            _fail("invalid quadrant")
            return
        var quadrant: Dictionary = raw_quadrant
        var qid := str(quadrant.get("id", ""))
        var qyaws: Variant = quadrant.get("candidate_yaws_degrees", [])
        if typeof(qyaws) != TYPE_ARRAY or qyaws.size() != 2:
            _fail("invalid quadrant candidates")
            return
        var best_yaw := -1
        var best_ratio := -1.0
        for raw_qyaw: Variant in qyaws:
            var qyaw := int(raw_qyaw)
            if not measurements.has(str(qyaw)):
                _fail("quadrant references unmeasured yaw")
                return
            var ratio := float((measurements[str(qyaw)] as Dictionary)["clearance_ratio"])
            if ratio > best_ratio + 0.000000001 or (absf(ratio - best_ratio) <= 0.000000001 and (best_yaw < 0 or qyaw < best_yaw)):
                best_ratio = ratio
                best_yaw = qyaw
        selected.append({"quadrant": qid, "yaw_degrees": best_yaw, "clearance_ratio": best_ratio})

    if selected.size() != 4:
        _fail("did not select exactly four views")
        return
    var receipt := {
        "schema": "grand-bruxelles-grand-place-safe-view-selection-receipt-v1",
        "contract_schema": contract["schema"],
        "selection_stage": "before_png_capture",
        "selection_rule": rules,
        "camera_seed": seed_contract,
        "measurements": measurements,
        "selected": selected,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    var absolute := output_path if output_path.begins_with("/") else ProjectSettings.globalize_path(output_path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(absolute, FileAccess.WRITE)
    if file == null:
        _fail("could not create selection receipt")
        return
    file.store_string(JSON.stringify(receipt, "  "))
    file.close()
    print("GRAND_PLACE_SAFE_VIEW_SELECTION_OK: selected=%s output=%s pre_capture=true visual_acceptance=false jouable_authorized=false" % [str(selected), absolute])
    quit(0)