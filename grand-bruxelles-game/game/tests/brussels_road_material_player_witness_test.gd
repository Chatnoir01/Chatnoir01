extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const SOURCE_SHA256 := "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"
const TARGETS := {
    359177328: {"name_fragment": "Maurice Lemonnier", "slug": "lemmonnier", "expect_resolver_ready": true},
    408211693: {"name_fragment": "Fonsny", "slug": "fonsny", "expect_resolver_ready": false, "blocked_reason": "osm_segments_present_but_hidden_in_authoritative_midi_runtime"},
    411724192: {"name_fragment": "Auguste Orts", "slug": "orts", "expect_resolver_ready": true},
    13842686: {"name_fragment": "Amigo", "slug": "amigo", "expect_resolver_ready": true},
}
const ARTIFACT_DIR := "res://artifacts/road_material_player_witness"
const DIFF_THRESHOLD := 0.08
const MIN_CHANGED_FRACTION := 0.0015
const MIN_BBOX_WIDTH := 180
const MIN_BBOX_HEIGHT := 24

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_ROAD_MATERIAL_PLAYER_WITNESS_FAIL: %s" % message)
    quit(1)

func _selected_target() -> Dictionary:
    var raw := OS.get_environment("GB_ROAD_WITNESS_OSM_ID").strip_edges()
    if raw.is_empty() or not raw.is_valid_int():
        return {}
    var osm_id := int(raw)
    if not TARGETS.has(osm_id):
        return {}
    var config: Dictionary = TARGETS[osm_id].duplicate(true)
    config["osm_id"] = osm_id
    return config

func _target_roads(root_node: Node, target_osm_id: int) -> Array[CSGBox3D]:
    var found: Array[CSGBox3D] = []
    var prefix := "Road_%d_" % target_osm_id
    var stack: Array[Node] = [root_node]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is CSGBox3D and str(node.name).begins_with(prefix):
            found.append(node as CSGBox3D)
        for child: Node in node.get_children():
            stack.append(child)
    return found

func _capture(path: String) -> Image:
    for _frame: int in range(3):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        return null
    if image.get_width() != 1280 or image.get_height() != 720:
        return null
    if image.save_png(path) != OK:
        return null
    return image

func _hide_dynamic_review_noise(main: Node, player: Node3D) -> void:
    player.visible = false
    player.process_mode = Node.PROCESS_MODE_DISABLED
    var traffic := main.get_node_or_null("TrafficManager")
    if traffic is Node3D:
        (traffic as Node3D).visible = false
        traffic.process_mode = Node.PROCESS_MODE_DISABLED
    var stack: Array[Node] = [main]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if node is CanvasItem:
            (node as CanvasItem).visible = false
        for child: Node in node.get_children():
            stack.append(child)

func _control_material() -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.albedo_color = Color(1.0, 0.0, 1.0, 1.0)
    material.metallic = 0.0
    material.roughness = 1.0
    return material

func _diff_metrics(before: Image, control: Image) -> Dictionary:
    var changed := 0
    var min_x := before.get_width()
    var min_y := before.get_height()
    var max_x := -1
    var max_y := -1
    for y: int in range(before.get_height()):
        for x: int in range(before.get_width()):
            var a := before.get_pixel(x, y)
            var b := control.get_pixel(x, y)
            var delta := maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b)))
            if delta <= DIFF_THRESHOLD:
                continue
            changed += 1
            min_x = mini(min_x, x)
            min_y = mini(min_y, y)
            max_x = maxi(max_x, x)
            max_y = maxi(max_y, y)
    var total := before.get_width() * before.get_height()
    var fraction := float(changed) / float(total)
    var bbox_width := 0 if max_x < min_x else max_x - min_x + 1
    var bbox_height := 0 if max_y < min_y else max_y - min_y + 1
    return {
        "changed_pixels": changed,
        "changed_fraction": fraction,
        "bbox": [min_x, min_y, max_x, max_y] if changed > 0 else [],
        "bbox_width": bbox_width,
        "bbox_height": bbox_height,
    }

func _run() -> void:
    var target := _selected_target()
    if target.is_empty():
        _fail("GB_ROAD_WITNESS_OSM_ID must select a canonical corridor witness target")
        return
    var target_osm_id := int(target["osm_id"])
    var target_name_fragment := str(target["name_fragment"])
    var target_slug := str(target["slug"])
    var expect_resolver_ready := bool(target.get("expect_resolver_ready", true))
    var before_path := ARTIFACT_DIR + "/road_material_%s_before.png" % target_slug
    var control_path := ARTIFACT_DIR + "/road_material_%s_control.png" % target_slug
    var report_path := ARTIFACT_DIR + "/road_material_%s_player_witness.json" % target_slug

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ARTIFACT_DIR))
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(16):
        await process_frame
        await physics_frame

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player missing")
        return

    var resolver := RESOLVER_SCRIPT.new()
    root.add_child(resolver)
    if FileAccess.get_sha256(SOURCE_PATH).to_lower() != SOURCE_SHA256:
        _fail("OSM source SHA drifted")
        return

    var target_roads := _target_roads(main, target_osm_id)
    if not expect_resolver_ready:
        if target_roads.is_empty():
            _fail("fail-closed target %d has no source-identity OSM road segments in runtime" % target_osm_id)
            return
        var visible_segments := 0
        for road: CSGBox3D in target_roads:
            if road.is_visible_in_tree():
                visible_segments += 1
        if visible_segments != 0:
            _fail("fail-closed target %d unexpectedly has %d visible OSM road segments" % [target_osm_id, visible_segments])
            return
        if resolver._road_is_rendered(main, target_osm_id):
            _fail("hidden OSM road target %d was accepted as rendered" % target_osm_id)
            return
        if resolver.apply_to_player(player, target_osm_id):
            _fail("resolver accepted fail-closed hidden OSM road target %d" % target_osm_id)
            return
        print("BRUSSELS_ROAD_MATERIAL_PLAYER_WITNESS_BLOCKED: osm_id=%d name_fragment=%s segments=%d visible_segments=0 reason=%s destination_advertisable=false jouable=false" % [target_osm_id, target_name_fragment, target_roads.size(), str(target.get("blocked_reason", ""))])
        quit(0)
        return

    if not resolver.apply_to_player(player, target_osm_id):
        _fail("source-backed resolver refused target %d" % target_osm_id)
        return
    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != target_osm_id:
        _fail("resolver target identity missing")
        return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains(target_name_fragment):
        _fail("resolver target name drifted")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("resolver source sightline proof missing")
        return
    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("resolver ground proof missing")
        return

    for _frame: int in range(4):
        await process_frame
        await physics_frame
    var active_camera := root.get_camera_3d()
    if active_camera == null:
        _fail("production player camera missing after source-backed road resolve")
        return

    var review_camera := Camera3D.new()
    review_camera.name = "RoadMaterialPlayerWitnessCamera_%d" % target_osm_id
    review_camera.global_transform = active_camera.global_transform
    review_camera.fov = active_camera.fov
    review_camera.near = active_camera.near
    review_camera.far = active_camera.far
    main.add_child(review_camera)
    review_camera.current = true
    _hide_dynamic_review_noise(main, player)

    if target_roads.is_empty():
        _fail("rendered target road segments missing for %d" % target_osm_id)
        return
    var original_materials: Array[Material] = []
    for road: CSGBox3D in target_roads:
        original_materials.append(road.material)

    var before := await _capture(before_path)
    if before == null:
        _fail("failed to capture 1280x720 production road frame")
        return

    var control := _control_material()
    for road: CSGBox3D in target_roads:
        road.material = control
    var control_image := await _capture(control_path)
    for index: int in range(target_roads.size()):
        target_roads[index].material = original_materials[index]
    if control_image == null:
        _fail("failed to capture 1280x720 target-road control frame")
        return

    var metrics := _diff_metrics(before, control_image)
    if float(metrics["changed_fraction"]) < MIN_CHANGED_FRACTION:
        _fail("source-backed road %d occupies too little of player frame: %.6f" % [target_osm_id, float(metrics["changed_fraction"])])
        return
    if int(metrics["bbox_width"]) < MIN_BBOX_WIDTH or int(metrics["bbox_height"]) < MIN_BBOX_HEIGHT:
        _fail("source-backed road %d footprint too small: %dx%d" % [target_osm_id, int(metrics["bbox_width"]), int(metrics["bbox_height"])])
        return

    var report := {
        "schema": "grand-bruxelles-road-material-player-witness-v2",
        "target_osm_id": target_osm_id,
        "target_name": str(player.get_meta("automatic_road_direct_source_name", "")),
        "source_path": SOURCE_PATH,
        "source_sha256": SOURCE_SHA256,
        "source_license": "ODbL-1.0",
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "ground_y": ground_y,
        "camera_transform": review_camera.global_transform,
        "camera_fov": review_camera.fov,
        "resolution": [1280, 720],
        "dynamic_review_noise_hidden": true,
        "road_control_is_test_only": true,
        "camera_copied_from_legitimate_player_witness": true,
        "geometry_changed": false,
        "runtime_material_changed": false,
        "destination_advertisable": false,
        "playability_claimed": false,
        "jouable_authorized": false,
        "human_review_status": "pending",
        "control_diff_threshold": DIFF_THRESHOLD,
        "metrics": metrics,
    }
    var file := FileAccess.open(report_path, FileAccess.WRITE)
    if file == null:
        _fail("could not write witness report")
        return
    file.store_string(JSON.stringify(report, "  "))
    file.close()

    print("BRUSSELS_ROAD_MATERIAL_PLAYER_WITNESS_OK: osm_id=%d segments=%d changed_fraction=%.6f bbox=%dx%d ground_y=%.3f fov=%.2f human_review=pending" % [target_osm_id, target_roads.size(), float(metrics["changed_fraction"]), int(metrics["bbox_width"]), int(metrics["bbox_height"]), ground_y, review_camera.fov])
    quit(0)
