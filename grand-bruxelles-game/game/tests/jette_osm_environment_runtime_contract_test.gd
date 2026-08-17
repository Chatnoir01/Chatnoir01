extends SceneTree

const GENERIC_RUNTIME := "res://game/scripts/brussels_osm_environment_runtime.gd"
const JETTE_ZONE := "res://game/zones/laeken_jette/jette_phase2_zone.gd"
const JETTE_DATA := "res://data/osm/zones/jette/environment.game.json"
const SPAWN := Vector3(-687.700268506218, 1.05, -4952.774160383269)
const BEFORE := "res://artifacts/visual/jette_osm_environment_before.png"
const AFTER := "res://artifacts/visual/jette_osm_environment_after.png"

func _initialize() -> void: call_deferred("_run")
func _fail(message: String) -> void: print("JETTE_OSM_ENVIRONMENT_CONTRACT_FAIL: %s" % message); quit(1)
func _read(path: String) -> String:
    var f := FileAccess.open(path, FileAccess.READ)
    return f.get_as_text() if f != null else ""

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
    if not FileAccess.file_exists(GENERIC_RUNTIME): _fail("generic runtime missing"); return
    var generic := _read(GENERIC_RUNTIME)
    if generic.to_lower().contains("jette"): _fail("generic renderer contains Jette literal"); return
    for token in ["MultiMeshInstance3D", "tree", "street_lamp", "bollard"]:
        if not generic.contains(token): _fail("generic renderer missing %s" % token); return
    for forbidden in ["StaticBody3D", "CollisionShape3D"]:
        if generic.contains(forbidden): _fail("visual renderer contains %s" % forbidden); return
    var zone_source := _read(JETTE_ZONE)
    if not zone_source.contains(GENERIC_RUNTIME) or not zone_source.contains(JETTE_DATA): _fail("Jette mount missing"); return

    var parsed = JSON.parse_string(_read(JETTE_DATA))
    if typeof(parsed) != TYPE_DICTIONARY: _fail("artifact invalid"); return
    var points: Array = (parsed as Dictionary).get("environment_points", [])
    if points.size() != 4584: _fail("expected 4584 source points"); return
    var nearest_tree := Vector3.ZERO; var nearest_distance := INF
    var local := {"tree":0, "street_lamp":0, "bollard":0}
    for variant in points:
        var row := variant as Dictionary; var kind := str(row.get("kind", "")); var p: Array = row.get("position", [])
        if not local.has(kind) or p.size() < 2: _fail("bad source row"); return
        var world := Vector3(float(p[0]), 0.0, float(p[1])); var distance := Vector2(world.x-SPAWN.x, world.z-SPAWN.z).length()
        if distance <= 300.0: local[kind] = int(local[kind]) + 1
        if kind == "tree" and distance < nearest_distance: nearest_distance = distance; nearest_tree = world
    if int(local["tree"]) == 0 or int(local["street_lamp"]) == 0: _fail("spawn lacks visible source density"); return

    var viewport := SubViewport.new(); viewport.size = Vector2i(1280,720); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
    var world_root := Node3D.new(); viewport.add_child(world_root)
    var player := CharacterBody3D.new(); player.name = "Player"; player.add_to_group("player"); player.position = SPAWN; world_root.add_child(player)
    var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-52.0,-28.0,0.0); light.light_energy = 1.25; world_root.add_child(light)
    var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(0.62,0.72,0.82); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color(0.55,0.58,0.62); environment.environment.ambient_light_energy = 0.7; world_root.add_child(environment)
    var zone_script := load(JETTE_ZONE) as Script; var zone := zone_script.new() as Node3D; world_root.add_child(zone)
    for _frame in range(12): await process_frame
    var runtime := zone.get_node_or_null("BrusselsOsmEnvironment") as Node3D
    if runtime == null: _fail("runtime mount missing"); return
    var counts: Dictionary = runtime.get("last_render_counts")
    if int(counts.get("tree",0)) == 0 or int(counts.get("street_lamp",0)) == 0: _fail("runtime rendered no trees/lamps"); return
    for child in runtime.get_children():
        if not child is MultiMeshInstance3D: _fail("environment child is not MultiMeshInstance3D"); return

    var camera := Camera3D.new(); camera.position = SPAWN + Vector3(0.0,0.6,0.0); camera.look_at_from_position(camera.position, nearest_tree + Vector3(0.0,2.8,0.0), Vector3.UP); camera.fov = 70.0; camera.current = true; world_root.add_child(camera)
    runtime.visible = false; for _frame in range(3): await process_frame
    var before := await _capture(viewport, BEFORE)
    runtime.visible = true; for _frame in range(3): await process_frame
    var after := await _capture(viewport, AFTER)
    if before == null or after == null: _fail("A/B capture failed"); return
    var changed := _changed(before, after)
    if changed < 0.0005: _fail("visible change too weak %.6f" % changed); return
    print("JETTE_OSM_ENVIRONMENT_CONTRACT_OK: total=4584 local_300m=%s rendered=%s nearest_tree=%.1fm changed=%.4f%% multimesh=true collisions=false" % [str(local), str(counts), nearest_distance, changed*100.0])
    quit(0)
