extends SceneTree

const SIZE := Vector2i(1280, 960)
const EVIDENCE := "res://data/qa/photo_match/bourse_2019_geotagged_camera_evidence.json"
const BEFORE := "res://artifacts/visual/bourse_context_facade_before.png"
const AFTER := "res://artifacts/visual/bourse_context_facade_after.png"
const RETREAT_M := 90.0
const TARGET_Y := 14.0

func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void:
    push_error("BOURSE_CONTEXT_FACADE_AB_FAIL: %s" % message); quit(1)

func _v3(raw: Array) -> Vector3:
    return Vector3(float(raw[0]), float(raw[1]), float(raw[2])) if raw.size() == 3 else Vector3.ZERO

func _v2(raw: Array) -> Vector2:
    return Vector2(float(raw[0]), float(raw[1])) if raw.size() == 2 else Vector2.ZERO

func _hide(node: Node) -> void:
    if node is Label3D: (node as Label3D).visible = false
    if node is Control: (node as Control).visible = false
    for child: Node in node.get_children(): _hide(child)

func _quiet(scene: Node) -> void:
    for path: String in ["Player", "PrototypeCar", "PhysicalCarB", "MidiHeroZone", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial: spatial.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D: (traffic as Node3D).visible = false
    _hide(scene)

func _capture(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw(); await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty(): return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image if image.save_png(absolute) == OK else null

func _changed(a: Image, b: Image, threshold: int) -> float:
    var changed := 0; var limit := float(threshold) / 255.0
    for y: int in range(a.get_height()):
        for x: int in range(a.get_width()):
            var ca := a.get_pixel(x, y); var cb := b.get_pixel(x, y)
            if max(abs(ca.r-cb.r), max(abs(ca.g-cb.g), abs(ca.b-cb.b))) > limit: changed += 1
    return float(changed) / float(a.get_width() * a.get_height())

func _run() -> void:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(EVIDENCE))
    if typeof(parsed) != TYPE_DICTIONARY: _fail("camera evidence missing"); return
    var evidence := parsed as Dictionary
    var candidate := evidence.get("candidate_game_camera_transform", {}) as Dictionary
    var hero := evidence.get("hero_witness", {}) as Dictionary
    var hfov := float(candidate.get("horizontal_fov_degrees", 0.0))
    var source_position := _v3(candidate.get("position", []))
    var target_xz := _v2(hero.get("hero_bbox_center_game_x_z_m", []))
    if hfov <= 0.0 or target_xz == Vector2.ZERO: _fail("invalid Bourse camera evidence"); return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null: _fail("main scene missing"); return
    var scene := packed.instantiate(); var viewport := SubViewport.new()
    viewport.size = SIZE; viewport.own_world_3d = true; viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport); _quiet(scene); viewport.add_child(scene)
    var existing := scene.get_viewport().get_camera_3d()
    if existing: existing.current = false

    var source_xz := Vector2(source_position.x, source_position.z)
    var away := (source_xz - target_xz).normalized()
    var witness_xz := source_xz + away * RETREAT_M
    var camera := Camera3D.new()
    camera.position = Vector3(witness_xz.x, 1.68, witness_xz.y)
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(hfov) * 0.5) / (float(SIZE.x) / SIZE.y)))
    camera.current = true; scene.add_child(camera)
    camera.look_at(Vector3(target_xz.x, TARGET_Y, target_xz.y), Vector3.UP)
    for _frame: int in range(90): await process_frame
    _quiet(scene)

    var art := scene.get_node_or_null("BourseContextFacadeArticulation")
    if art == null or not art.has_method("set_articulation_enabled"): _fail("production articulation missing"); return
    var buildings := int(art.call("diagnostic_building_count")); var trims := int(art.call("diagnostic_trim_count"))
    if buildings < 8 or trims < 80: _fail("coverage too small: buildings=%d trims=%d" % [buildings, trims]); return
    art.call("set_articulation_enabled", false)
    for _frame: int in range(8): await process_frame
    var before := await _capture(viewport, BEFORE)
    art.call("set_articulation_enabled", true)
    for _frame: int in range(8): await process_frame
    var after := await _capture(viewport, AFTER)
    if before == null or after == null: _fail("capture failed"); return
    var d4 := _changed(before, after, 4); var d10 := _changed(before, after, 10)
    print("BOURSE_CONTEXT_FACADE_AB_METRICS: changed_gt4=%.6f changed_gt10=%.6f buildings=%d trims=%d retreat_m=%.1f" % [d4, d10, buildings, trims, RETREAT_M])
    if d4 < 0.004 or d10 < 0.001 or d4 > 0.14: _fail("visual gate failed: gt4=%.4f%% gt10=%.4f%%" % [d4*100.0, d10*100.0]); return
    print("BOURSE_CONTEXT_FACADE_AB_OK: same_camera=true source_derived_player_witness=true buildings=%d trims=%d changed_gt4=%.4f%% changed_gt10=%.4f%%" % [buildings, trims, d4*100.0, d10*100.0]); viewport.queue_free(); quit(0)
