extends SceneTree

const JETTE_ZONE := "res://game/zones/laeken_jette/jette_phase2_zone.gd"
const BEFORE := "res://artifacts/visual/jette_urbis_finish_before.png"
const AFTER := "res://artifacts/visual/jette_urbis_finish_after.png"
const SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)

func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void: print("JETTE_URBIS_FINISH_FAIL: %s" % message); quit(1)

func _capture(viewport: SubViewport, path: String) -> Image:
    RenderingServer.force_draw(); await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty(): return null
    var absolute := ProjectSettings.globalize_path(path)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image if image.save_png(absolute) == OK else null

func _changed(before: Image, after: Image) -> float:
    var changed := 0
    var total := 0
    for y in range(0, before.get_height(), 4):
        for x in range(0, before.get_width(), 4):
            total += 1
            var a := before.get_pixel(x, y); var b := after.get_pixel(x, y)
            if max(abs(a.r-b.r), max(abs(a.g-b.g), abs(a.b-b.b))) > 0.02: changed += 1
    return float(changed) / float(max(total, 1))

func _run() -> void:
    var viewport := SubViewport.new(); viewport.size = Vector2i(1280,720); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
    var world_root := Node3D.new(); viewport.add_child(world_root)
    var player := CharacterBody3D.new(); player.name = "Player"; player.add_to_group("player"); player.position = SPAWN; world_root.add_child(player)
    var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-48.0,-32.0,0.0); light.light_energy = 1.3; world_root.add_child(light)
    var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(0.60,0.69,0.80); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color(0.58,0.59,0.60); environment.environment.ambient_light_energy = 0.72; world_root.add_child(environment)
    var zone_script := load(JETTE_ZONE) as Script; var zone := zone_script.new() as Node3D; world_root.add_child(zone)
    for _frame in range(16): await process_frame

    var runtime := root.get_node_or_null("BrusselsUrbisFinishRuntime")
    if runtime == null: _fail("autoload missing"); return
    for _frame in range(12):
        if str(runtime.call("applied_zone")) == "jette": break
        await process_frame
    if str(runtime.call("applied_zone")) != "jette": _fail("Jette finish did not bind"); return
    if not bool(runtime.call("geometry_unchanged")): _fail("geometry changed while binding"); return
    if str(runtime.call("material_family")) != "brussels_urbis_finish_v1": _fail("wrong material family"); return

    var road := zone.find_child("JetteOfficialStreetSurfaces", true, false) as MeshInstance3D
    var buildings := zone.find_child("JetteOfficialBuildings", true, false) as MeshInstance3D
    if road == null or buildings == null: _fail("Jette source meshes missing"); return
    var road_transform := road.global_transform
    var building_transform := buildings.global_transform

    var camera := Camera3D.new(); camera.position = SPAWN + Vector3(0.0, 7.5, 18.0); camera.look_at_from_position(camera.position, SPAWN + Vector3(0.0, 4.0, -28.0), Vector3.UP); camera.fov = 70.0; camera.current = true; world_root.add_child(camera)
    runtime.call("set_enhanced_enabled", false); for _frame in range(3): await process_frame
    var before := await _capture(viewport, BEFORE)
    runtime.call("set_enhanced_enabled", true); for _frame in range(3): await process_frame
    var after := await _capture(viewport, AFTER)
    if before == null or after == null: _fail("A/B capture failed"); return
    if not road.global_transform.is_equal_approx(road_transform) or not buildings.global_transform.is_equal_approx(building_transform): _fail("A/B moved source geometry"); return
    var changed := _changed(before, after)
    if changed < 0.003: _fail("visible material finish too weak %.6f" % changed); return
    print("JETTE_URBIS_FINISH_OK: family=brussels_urbis_finish_v1 changed=%.4f%% geometry_changed=false source=UrbIS material_identity_claimed=false" % [changed*100.0])
    quit(0)
