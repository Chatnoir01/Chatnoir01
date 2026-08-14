extends SceneTree

const TERRAIN_SCRIPT := preload("res://game/zones/laeken_jette/atomium_dtm_terrain.gd")
const HERO_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_core.gd")
const REFLECTION_SCRIPT := preload("res://game/zones/laeken_jette/atomium_hero_reflection_environment.gd")
const SOURCE_META_PATH := "res://data/sources/laeken_jette/orthophoto_phase1_runtime.json"
const ORTHO_PATH := "res://data/orthophoto/laeken_jette/phase1_ortho.jpg"
const OUTPUT_PATH := "res://artifacts/atomium/atomium_orthophoto_hero.png"
const WIDTH := 1280
const HEIGHT := 960
const EXPECTED_CRS := "EPSG:31370"
const EXPECTED_YEAR := 2024
const EXPECTED_SHA256 := "c23ab90490d78acb6accc0d4ce8a1bad5821b8b478b3643744382c4f13f57d95"
const EXPECTED_BBOX := [147300.0, 173650.0, 149100.0, 176750.0]
const EXPECTED_SOURCE_WIDTH := 2048
const EXPECTED_SOURCE_HEIGHT := 3527
const EXPECTED_RESOLUTION := 0.87890625
const EXPECTED_SURFACE_OFFSET_M := 0.025

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_ORTHOPHOTO_HERO_FAIL: %s" % message)
    quit(1)

func _sha256(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var context := HashingContext.new()
    if context.start(HashingContext.HASH_SHA256) != OK:
        return ""
    while file.get_position() < file.get_length():
        context.update(file.get_buffer(mini(1048576, file.get_length() - file.get_position())))
    return context.finish().hex_encode()

func _run() -> void:
    if str(ProjectSettings.get_setting("autoload/AtomiumOrthophotoOverlay", "")) != "*res://game/zones/laeken_jette/atomium_orthophoto_autoload.gd":
        _fail("orthophoto autoload registration missing")
        return
    if not FileAccess.file_exists(SOURCE_META_PATH) or not FileAccess.file_exists(ORTHO_PATH):
        _fail("locked orthophoto source files missing")
        return
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_META_PATH))
    if typeof(parsed) != TYPE_DICTIONARY:
        _fail("source metadata is not a dictionary")
        return
    var meta := parsed as Dictionary
    if str(meta.get("crs", "")) != EXPECTED_CRS:
        _fail("source CRS drifted")
        return
    var abstract_text := str(meta.get("layer_abstract", ""))
    if not abstract_text.contains("currently 2024"):
        _fail("source year contract drifted")
        return
    if int(meta.get("width", 0)) != EXPECTED_SOURCE_WIDTH or int(meta.get("height", 0)) != EXPECTED_SOURCE_HEIGHT:
        _fail("source raster dimensions drifted")
        return
    if absf(float(meta.get("approx_ground_resolution_m_per_pixel", 0.0)) - EXPECTED_RESOLUTION) > 0.0000001:
        _fail("source ground resolution drifted")
        return
    var bbox: Array = meta.get("bbox_epsg31370", [])
    if bbox.size() != 4:
        _fail("source bbox missing")
        return
    for i: int in range(4):
        if absf(float(bbox[i]) - float(EXPECTED_BBOX[i])) > 0.0001:
            _fail("source bbox drifted at index %d" % i)
            return
    if str(meta.get("sha256", "")) != EXPECTED_SHA256 or _sha256(ORTHO_PATH) != EXPECTED_SHA256:
        _fail("orthophoto content hash drifted")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)
    var world := Node3D.new()
    viewport.add_child(world)

    var terrain := TERRAIN_SCRIPT.new()
    terrain.name = "OrthophotoTestTerrain"
    terrain.build_collision = false
    world.add_child(terrain)
    for _frame: int in range(20):
        await process_frame
        if bool(terrain.get("terrain_loaded")) and terrain.get_node_or_null("OfficialAtomiumOrthophotoDrape") != null:
            break
    if not bool(terrain.get("terrain_loaded")):
        _fail("official Atomium DTM did not load")
        return
    var overlay := terrain.get_node_or_null("OfficialAtomiumOrthophotoDrape") as MeshInstance3D
    if overlay == null:
        _fail("orthophoto overlay was not mounted by autoload")
        return
    if not bool(overlay.get_meta("presentation_only", false)):
        _fail("overlay lost presentation-only marker")
        return
    if str(overlay.get_meta("source_crs", "")) != EXPECTED_CRS or int(overlay.get_meta("source_year", 0)) != EXPECTED_YEAR:
        _fail("mounted overlay source metadata drifted")
        return

    var mesh := overlay.mesh as ArrayMesh
    if mesh == null or mesh.get_surface_count() != 1:
        _fail("orthophoto overlay mesh invalid")
        return
    var arrays := mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
    var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
    var width := int(terrain.get("width"))
    var height := int(terrain.get("height"))
    if vertices.size() != width * height or uvs.size() != vertices.size():
        _fail("overlay vertex/UV topology drifted")
        return

    var first_e := float(terrain.get("first_e"))
    var first_n := float(terrain.get("first_n"))
    var step_e := float(terrain.get("step_e"))
    var step_n := float(terrain.get("step_n"))
    var expected_uv0 := Vector2(
        (first_e - EXPECTED_BBOX[0]) / (EXPECTED_BBOX[2] - EXPECTED_BBOX[0]),
        (EXPECTED_BBOX[3] - first_n) / (EXPECTED_BBOX[3] - EXPECTED_BBOX[1])
    )
    if uvs[0].distance_to(expected_uv0) > 0.000001:
        _fail("north-west UV origin is not source-coordinate exact")
        return
    if uvs[1].x <= uvs[0].x or signf(uvs[1].x - uvs[0].x) != signf(step_e):
        _fail("east-west UV orientation is flipped")
        return
    if uvs[width].y <= uvs[0].y or step_n >= 0.0:
        _fail("north-south UV orientation is flipped")
        return

    var covered_count := 0
    var fallback_count := 0
    for uv: Vector2 in uvs:
        var covered := uv.x >= 0.0 and uv.x <= 1.0 and uv.y >= 0.0 and uv.y <= 1.0
        if covered:
            covered_count += 1
        else:
            fallback_count += 1
    if covered_count <= 0 or fallback_count <= 0:
        _fail("source-bound coverage/fallback split is not exercised")
        return

    var heights: PackedFloat32Array = terrain.get("heights")
    if absf(vertices[0].y - heights[0] - EXPECTED_SURFACE_OFFSET_M) > 0.0001:
        _fail("overlay surface offset drifted from anti-z-fighting contract")
        return
    var material := overlay.material_override as ShaderMaterial
    if material == null or material.shader == null:
        _fail("orthophoto shader material missing")
        return
    var shader_code := material.shader.code
    if not shader_code.contains("repeat_disable") or not shader_code.contains("covered ? texture(ortho_texture, UV).rgb : fallback_color"):
        _fail("source-bound shader fallback contract drifted")
        return

    var hero := HERO_SCRIPT.new()
    world.add_child(hero)
    if not hero.build_on_terrain(terrain):
        _fail("Atomium hero did not build on official DTM")
        return
    var reflection := REFLECTION_SCRIPT.new()
    world.add_child(reflection)
    if not reflection.build():
        _fail("Atomium reflection environment did not build")
        return

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
        _fail("orthophoto hero capture invalid")
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("orthophoto hero capture save failed")
        return

    print("ATOMIUM_ORTHOPHOTO_HERO_OK: crs=%s year=%d sha256=%s bbox=%s source=%dx%d covered_uv=%d fallback_uv=%d offset=%.3f capture=%s size=%dx%d" % [EXPECTED_CRS, EXPECTED_YEAR, EXPECTED_SHA256, str(EXPECTED_BBOX), EXPECTED_SOURCE_WIDTH, EXPECTED_SOURCE_HEIGHT, covered_count, fallback_count, EXPECTED_SURFACE_OFFSET_M, OUTPUT_PATH, WIDTH, HEIGHT])
    quit(0)
