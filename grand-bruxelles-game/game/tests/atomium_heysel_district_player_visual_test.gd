extends SceneTree

const MAIN_SCENE := "res://game/main.tscn"
const OUT_PATH := "res://artifacts/qa/atomium_heysel_district/player.png"
const WIDTH := 1280
const HEIGHT := 720
const EXPECTED_LOCATION := "ATOMIUM · HEYSEL / HEIZEL"
const EXPECTED_BUILDINGS := 225
const EXPECTED_STREET_SURFACES := 254
const EXPECTED_STREET_AXES := 96
const EXPECTED_TRAM := 66
const EXPECTED_TRAIN := 66

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ATOMIUM_HEYSEL_DISTRICT_PLAYER_FAIL: %s" % message)
    quit(1)

func _mask_canvas(node: Node) -> void:
    if node is CanvasLayer:
        (node as CanvasLayer).visible = false
    if node is CanvasItem:
        (node as CanvasItem).visible = false
    for child: Node in node.get_children():
        _mask_canvas(child)

func _freeze_dynamic_groups() -> void:
    for group_name: StringName in [&"vehicle", &"npc", &"ambient", &"traffic"]:
        for node: Node in get_nodes_in_group(group_name):
            node.set_process(false)
            node.set_physics_process(false)

func _run() -> void:
    var error := change_scene_to_file(MAIN_SCENE)
    if error != OK:
        _fail("main scene load failed: %s" % error)
        return

    var main: Node = null
    var player: CharacterBody3D = null
    for _attempt: int in range(240):
        await process_frame
        main = current_scene
        if main != null:
            player = main.get_node_or_null("Player") as CharacterBody3D
            if player != null:
                break
    if main == null or player == null:
        _fail("main/player unavailable")
        return

    player.call_deferred("_activate_atomium_direct_spawn")
    var atomium_ready := false
    for _attempt: int in range(600):
        await process_frame
        var terrain := main.get_node_or_null("AtomiumDirectTerrain")
        var hero := main.get_node_or_null("AtomiumDirectHero")
        var reflection := main.get_node_or_null("AtomiumDirectReflectionEnvironment")
        var location := main.get_node_or_null("LocationLabel")
        if terrain == null or hero == null or reflection == null or location == null:
            continue
        if not bool(terrain.get("terrain_loaded")) or not bool(hero.get("hero_built")):
            continue
        if location.has_method("get_current_location_text") and str(location.call("get_current_location_text")) == EXPECTED_LOCATION:
            atomium_ready = true
            break
    if not atomium_ready:
        _fail("production Atomium direct spawn did not become ready")
        return

    var bootstrap := root.get_node_or_null("AtomiumHeyselDirectSpawnBootstrap")
    if bootstrap == null or not bootstrap.has_method("_mount_district"):
        _fail("Heysel direct-spawn bootstrap unavailable")
        return
    bootstrap.call_deferred("_mount_district")

    var district: Node = null
    for _attempt: int in range(600):
        await process_frame
        district = main.get_node_or_null("AtomiumHeyselDistrictRuntime")
        if district != null and bool(district.get("runtime_loaded")):
            break
    if district == null or not bool(district.get("runtime_loaded")):
        _fail("Heysel district runtime did not become ready")
        return
    if not bool(district.get("compact_payload_used")):
        _fail("player witness did not use committed compact Heysel payload")
        return
    if str(district.get_meta("vertical_owner", "")) != "official_atomium_dtm":
        _fail("district vertical owner is not official Atomium DTM")
        return
    if bool(district.get_meta("invented_building_height_fallback", true)):
        _fail("invented building height fallback is enabled")
        return

    var stats: Dictionary = district.get("last_stats")
    var expected := {
        "buildings": EXPECTED_BUILDINGS,
        "street_surfaces": EXPECTED_STREET_SURFACES,
        "street_axes": EXPECTED_STREET_AXES,
        "tram_network": EXPECTED_TRAM,
        "train_network": EXPECTED_TRAIN,
    }
    for key: String in expected:
        if int(stats.get(key, -1)) != int(expected[key]):
            _fail("%s count drifted: got=%s expected=%s" % [key, str(stats.get(key, -1)), str(expected[key])])
            return
    if int(stats.get("rendered_buildings", -1)) + int(stats.get("unresolved_height_buildings", -1)) != EXPECTED_BUILDINGS:
        _fail("building truth accounting does not cover all source footprints")
        return

    for required_node: String in ["AtomiumHeyselStreetSurfaces", "AtomiumHeyselStreetAxes", "AtomiumHeyselUnresolvedBuildingFootprints"]:
        if district.get_node_or_null(required_node) == null:
            _fail("required visible district layer missing: %s" % required_node)
            return

    _freeze_dynamic_groups()
    player.velocity = Vector3.ZERO
    player.set_process(false)
    player.set_physics_process(false)
    for _frame: int in range(32):
        _mask_canvas(root)
        await process_frame

    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("1280x720 player capture unavailable")
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH.get_base_dir()))
    if image.save_png(ProjectSettings.globalize_path(OUT_PATH)) != OK:
        _fail("player capture write failed")
        return

    print("ATOMIUM_HEYSEL_DISTRICT_PLAYER_OK: compact=true terrain=official_dtm buildings=%d unresolved_height=%d roads=%d axes=%d tram=%d train=%d screenshot=%s jouable_claim=false" % [
        int(stats["buildings"]),
        int(stats["unresolved_height_buildings"]),
        int(stats["street_surfaces"]),
        int(stats["street_axes"]),
        int(stats["tram_network"]),
        int(stats["train_network"]),
        OUT_PATH,
    ])
    quit(0)
