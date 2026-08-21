extends SceneTree

const GENERIC_RUNTIME := "res://game/scripts/brussels_osm_environment_runtime.gd"
const SELECTOR_RUNTIME := "res://game/scripts/zone_selector_runtime.gd"
const CATALOG_PATH := "res://data/qa/playable_zone_catalog.json"
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

func _jette_contract() -> Dictionary:
    var parsed: Variant = JSON.parse_string(_read(CATALOG_PATH))
    if not parsed is Dictionary:
        return {}
    var zones: Variant = (parsed as Dictionary).get("zones", [])
    if not zones is Array:
        return {}
    for raw: Variant in zones:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == "jette":
            return (raw as Dictionary).duplicate(true)
    return {}

func _run() -> void:
    if not FileAccess.file_exists(GENERIC_RUNTIME): _fail("generic runtime missing"); return
    if not FileAccess.file_exists(SELECTOR_RUNTIME): _fail("selector runtime missing"); return
    var generic := _read(GENERIC_RUNTIME)
    if generic.to_lower().contains("jette"): _fail("generic renderer contains Jette literal"); return
    for token in ["MultiMeshInstance3D", "tree", "street_lamp", "bollard", "loaded_ok", "_validate_document_contract"]:
        if not generic.contains(token): _fail("generic renderer missing %s" % token); return
    for forbidden in ["StaticBody3D", "CollisionShape3D"]:
        if generic.contains(forbidden): _fail("visual renderer contains %s" % forbidden); return

    var zone_source := _read(JETTE_ZONE)
    if zone_source.contains("OSM_ENVIRONMENT_DATA") or zone_source.contains("OSM_ENVIRONMENT_RUNTIME") or zone_source.contains("_build_osm_environment"):
        _fail("Jette still owns the environment mount")
        return
    var selector_source := _read(SELECTOR_RUNTIME)
    if not selector_source.contains("OSM_ENVIRONMENT_RUNTIME") or not selector_source.contains("_mount_environment_if_required") or not selector_source.contains("environment_artifact"):
        _fail("generic selector mount missing")
        return
    var jette := _jette_contract()
    if jette.is_empty(): _fail("Jette catalog contract missing"); return
    if str(jette.get("environment_artifact", "")) != JETTE_DATA: _fail("Jette environment artifact not catalog-owned"); return
    if JETTE_DATA not in jette.get("requires", []): _fail("Jette environment artifact not gated by requires"); return

    var parsed = JSON.parse_string(_read(JETTE_DATA))
    if typeof(parsed) != TYPE_DICTIONARY: _fail("artifact invalid"); return
    var document := parsed as Dictionary
    for pair: Array in [
        ["format", "grand-bruxelles-osm-zone-environment-v1"],
        ["source_crs", "EPSG:4326"],
        ["projection_crs", "EPSG:31370"],
        ["license", "ODbL-1.0"],
    ]:
        if str(document.get(str(pair[0]), "")) != str(pair[1]): _fail("artifact contract mismatch %s" % str(pair[0])); return
    var origin: Variant = document.get("game_origin", {})
    if not origin is Dictionary or str((origin as Dictionary).get("axes", "")) != "X=east, Y=up, Z=south" or str((origin as Dictionary).get("units", "")) != "metres":
        _fail("artifact game-space contract mismatch")
        return
    var points: Array = document.get("environment_points", [])
    if points.size() != 4584: _fail("expected 4584 source points"); return
    var stats: Variant = document.get("stats", {})
    if not stats is Dictionary:
        _fail("artifact stats missing")
        return
    if int((stats as Dictionary).get("tree", -1)) + int((stats as Dictionary).get("street_lamp", -1)) + int((stats as Dictionary).get("bollard", -1)) != points.size():
        _fail("artifact stats total mismatch")
        return

    var nearest_tree := Vector3.ZERO; var nearest_distance := INF
    var local := {"tree":0, "street_lamp":0, "bollard":0}
    for variant in points:
        var row := variant as Dictionary; var kind := str(row.get("kind", "")); var p: Array = row.get("position", [])
        if not local.has(kind) or p.size() < 2: _fail("bad source row"); return
        var world := Vector3(float(p[0]), 0.0, float(p[1])); var distance := Vector2(world.x-SPAWN.x, world.z-SPAWN.z).length()
        if distance <= 300.0: local[kind] = int(local[kind]) + 1
        if kind == "tree" and distance < nearest_distance: nearest_distance = distance; nearest_tree = world
    if int(local["tree"]) == 0 or int(local["street_lamp"]) == 0: _fail("spawn lacks visible source density"); return

    var selector := root.get_node_or_null("ZoneSelectorRuntime")
    if selector == null or not selector.has_method("_mount_environment_if_required"):
        _fail("selector autoload mount API missing")
        return
    var viewport := SubViewport.new(); viewport.size = Vector2i(1280,720); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS; root.add_child(viewport)
    var world_root := Node3D.new(); viewport.add_child(world_root)
    var player := CharacterBody3D.new(); player.name = "Player"; player.add_to_group("player"); player.position = SPAWN; world_root.add_child(player)
    var light := DirectionalLight3D.new(); light.rotation_degrees = Vector3(-52.0,-28.0,0.0); light.light_energy = 1.25; world_root.add_child(light)
    var environment := WorldEnvironment.new(); environment.environment = Environment.new(); environment.environment.background_mode = Environment.BG_COLOR; environment.environment.background_color = Color(0.62,0.72,0.82); environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR; environment.environment.ambient_light_color = Color(0.55,0.58,0.62); environment.environment.ambient_light_energy = 0.7; world_root.add_child(environment)
    var mounted := bool(await selector.call("_mount_environment_if_required", world_root, jette))
    if not mounted: _fail("selector refused proven Jette environment"); return
    for _frame in range(12): await process_frame
    var runtime := world_root.get_node_or_null("ZoneEnvironment_jette") as Node3D
    if runtime == null: _fail("catalog-driven runtime mount missing"); return
    if not bool(runtime.call("loaded_ok")): _fail("runtime did not accept City Machine contract"); return
    var counts: Dictionary = runtime.get("last_render_counts")
    if int(counts.get("tree",0)) == 0 or int(counts.get("street_lamp",0)) == 0: _fail("runtime rendered no trees/lamps"); return
    for child in runtime.get_children():
        if not child is MultiMeshInstance3D: _fail("environment child is not MultiMeshInstance3D"); return

    var toward_spawn := Vector3(SPAWN.x-nearest_tree.x, 0.0, SPAWN.z-nearest_tree.z).normalized()
    if toward_spawn.length_squared() < 0.5: toward_spawn = Vector3.FORWARD
    var camera := Camera3D.new(); camera.position = nearest_tree + toward_spawn*12.0 + Vector3(0.0,1.65,0.0); camera.look_at_from_position(camera.position, nearest_tree + Vector3(0.0,2.8,0.0), Vector3.UP); camera.fov = 70.0; camera.current = true; world_root.add_child(camera)
    runtime.visible = false; for _frame in range(3): await process_frame
    var before := await _capture(viewport, BEFORE)
    runtime.visible = true; for _frame in range(3): await process_frame
    var after := await _capture(viewport, AFTER)
    if before == null or after == null: _fail("A/B capture failed"); return
    var changed := _changed(before, after)
    if changed < 0.0005: _fail("visible change too weak %.6f" % changed); return
    print("JETTE_OSM_ENVIRONMENT_CONTRACT_OK: total=4584 local_300m=%s rendered=%s nearest_tree=%.1fm changed=%.4f%% catalog_mount=true multimesh=true collisions=false" % [str(local), str(counts), nearest_distance, changed*100.0])
    quit(0)
