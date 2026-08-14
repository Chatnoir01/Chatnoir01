extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const TREES_SCRIPT := preload("res://game/zones/laeken_jette/atomium_official_city_trees.gd")
const OUTPUT_PATH := "res://artifacts/atomium/atomium_official_city_trees_ground_oblique.png"
const WIDTH := 1280
const HEIGHT := 960

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_OFFICIAL_TREES_FAIL: %s" % message)
    quit(1)

func _source_intersection_diagnostics(terrain: Node, trees: Node, atomium_e: float, atomium_n: float) -> Dictionary:
    var data_path := str(trees.get("data_path"))
    if not FileAccess.file_exists(data_path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var features: Variant = (parsed as Dictionary).get("features", [])
    if not features is Array:
        return {}

    var first_e := float(terrain.get("first_e"))
    var first_n := float(terrain.get("first_n"))
    var step_e := float(terrain.get("step_e"))
    var step_n := float(terrain.get("step_n"))
    var width := int(terrain.get("width"))
    var height := int(terrain.get("height"))
    var last_e := first_e + float(width - 1) * step_e
    var last_n := first_n + float(height - 1) * step_n
    var min_e := minf(first_e, last_e)
    var max_e := maxf(first_e, last_e)
    var min_n := minf(first_n, last_n)
    var max_n := maxf(first_n, last_n)
    var hero_radius := float(trees.get("hero_radius_m"))
    var hero_radius_sq := hero_radius * hero_radius

    var radius_count := 0
    var bbox_count := 0
    var intersection_count := 0
    var point_count := 0
    for raw_feature: Variant in features:
        if not raw_feature is Dictionary:
            continue
        var geometry: Variant = (raw_feature as Dictionary).get("geometry", {})
        if not geometry is Dictionary or str((geometry as Dictionary).get("type", "")) != "Point":
            continue
        var coords: Variant = (geometry as Dictionary).get("coordinates", [])
        if not coords is Array or coords.size() < 2:
            continue
        point_count += 1
        var source_e := float(coords[0])
        var source_n := float(coords[1])
        var de := source_e - atomium_e
        var dn := source_n - atomium_n
        var in_radius := de * de + dn * dn <= hero_radius_sq
        var in_bbox := source_e >= min_e and source_e <= max_e and source_n >= min_n and source_n <= max_n
        if in_radius:
            radius_count += 1
        if in_bbox:
            bbox_count += 1
        if in_radius and in_bbox:
            intersection_count += 1

    return {
        "feature_count": features.size(),
        "point_count": point_count,
        "within_radius_count": radius_count,
        "inside_dtm_bbox_count": bbox_count,
        "intersection_count": intersection_count,
        "dtm_bbox": [min_e, min_n, max_e, max_n],
        "atomium_e": atomium_e,
        "atomium_n": atomium_n,
        "hero_radius_m": hero_radius
    }

func _run() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var world := Node3D.new()
    viewport.add_child(world)

    var terrain := TERRAIN_SCRIPT.new()
    terrain.build_collision = false
    world.add_child(terrain)
    await process_frame
    await process_frame
    if not terrain.terrain_loaded:
        _fail("terrain did not load")
        return

    var hero := HERO_SCRIPT.new()
    world.add_child(hero)
    if not hero.build_on_terrain(terrain):
        _fail("hero core did not build")
        return

    var trees := TREES_SCRIPT.new()
    world.add_child(trees)

    # Regression: public-tree GeoJSON is absolute EPSG:31370, while the DTM
    # runtime is local metres about game_origin_e/game_origin_n. Prove that the
    # same conversion maps the Atomium's reconstructed Lambert coordinate back
    # to the already-validated local anchor before consuming any tree feature.
    var reconstructed_atomium_e := float(terrain.origin_e) + hero.anchor_position.x
    var reconstructed_atomium_n := float(terrain.origin_n) - hero.anchor_position.z
    var converted_anchor := trees.source_to_game_horizontal(terrain, reconstructed_atomium_e, reconstructed_atomium_n)
    if absf(converted_anchor.x - hero.anchor_position.x) > 0.001 or absf(converted_anchor.y - hero.anchor_position.z) > 0.001:
        _fail("Lambert-to-local conversion drifted: %s vs hero %s" % [converted_anchor, Vector2(hero.anchor_position.x, hero.anchor_position.z)])
        return

    # Deterministic source-space diagnosis. This happens before renderer filtering
    # and does not alter source coordinates, source hash, terrain scope or runtime
    # behavior. It distinguishes a genuine source/terrain coverage gap from a
    # coordinate-conversion/filtering bug.
    var diagnostics := _source_intersection_diagnostics(terrain, trees, reconstructed_atomium_e, reconstructed_atomium_n)
    if diagnostics.is_empty():
        _fail("source intersection diagnostics unavailable")
        return
    print("ATOMIUM_TREE_INTERSECTION_DIAGNOSTIC: source=%d points=%d radius420=%d dtm_bbox=%d intersection=%d atomium=(%.6f,%.6f) bbox=[%.6f,%.6f,%.6f,%.6f]" % [
        int(diagnostics.get("feature_count", -1)),
        int(diagnostics.get("point_count", -1)),
        int(diagnostics.get("within_radius_count", -1)),
        int(diagnostics.get("inside_dtm_bbox_count", -1)),
        int(diagnostics.get("intersection_count", -1)),
        float(diagnostics.get("atomium_e", 0.0)),
        float(diagnostics.get("atomium_n", 0.0)),
        float((diagnostics.get("dtm_bbox", []) as Array)[0]),
        float((diagnostics.get("dtm_bbox", []) as Array)[1]),
        float((diagnostics.get("dtm_bbox", []) as Array)[2]),
        float((diagnostics.get("dtm_bbox", []) as Array)[3])
    ])
    if int(diagnostics.get("feature_count", -1)) != 8236 or int(diagnostics.get("point_count", -1)) != 8236:
        _fail("official source point count drifted before filtering")
        return
    if int(diagnostics.get("intersection_count", -1)) <= 0:
        _fail("source/DTM Lambert intersection is zero; vegetation cannot be rendered without changing validated scope")
        return

    if not trees.build_on_terrain(terrain):
        _fail("official tree context did not build")
        return
    if not trees.source_coordinate_conversion_verified:
        _fail("source coordinates were not converted from EPSG:31370")
        return
    if trees.source_feature_count != 8236:
        _fail("official source count drifted: %d" % trees.source_feature_count)
        return
    if trees.rendered_tree_count < 50:
        _fail("hero context selected too few trees: %d" % trees.rendered_tree_count)
        return
    if trees.source_dimensions_claimed or trees.collision_created:
        _fail("presentation-only trees acquired unsupported physical semantics")
        return
    for i: int in range(trees.rendered_tree_count):
        var p := trees.instance_position(i)
        if not terrain.contains_game_point(p.x, p.z):
            _fail("tree %d left official terrain" % i)
            return
        var sampled := terrain.sample_height(p.x, p.z)
        if absf(sampled - p.y) > 0.01:
            _fail("tree %d is not terrain anchored" % i)
            return
        if Vector2(p.x - hero.anchor_position.x, p.z - hero.anchor_position.z).length() > trees.hero_radius_m + 0.01:
            _fail("tree %d escaped hero radius" % i)
            return

    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.62, 0.69, 0.78)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.88, 0.90, 0.93)
    env.ambient_light_energy = 0.62
    environment.environment = env
    world.add_child(environment)
    var sun := DirectionalLight3D.new()
    sun.rotation_degrees = Vector3(-46.0, -28.0, 0.0)
    sun.light_energy = 1.25
    sun.shadow_enabled = true
    world.add_child(sun)
    var camera := Camera3D.new()
    camera.position = hero.anchor_position + Vector3(-185.0, 86.0, 235.0)
    camera.fov = 48.0
    camera.current = true
    world.add_child(camera)
    camera.look_at(hero.anchor_position + Vector3(0.0, 50.0, 0.0), Vector3.UP)

    for _frame: int in range(16):
        await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid")
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("capture save failed")
        return
    print("ATOMIUM_OFFICIAL_TREES_OK: source=%d rendered=%d radius_rejected=%d terrain_rejected=%d capture=%s" % [trees.source_feature_count, trees.rendered_tree_count, trees.radius_rejected_count, trees.terrain_rejected_count, OUTPUT_PATH])
    quit(0)
