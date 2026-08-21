extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const LEMONNIER_ID := 359177328
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const SOURCE_SHA256 := "a96123a6098c2a94dcef2622b6ea099c831f426e1ebfeb28a2edda74675c2493"
const OUTPUT_PATH := "res://artifacts/visual/automatic_road_359177328_player.png"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("AUTOMATIC_ROAD_DIRECT_SPAWN_WITNESS_FAIL: %s" % message)
    quit(1)

func _hide_dynamic(scene: Node) -> void:
    for path: String in ["MissionLabel", "PrototypeLabel", "MiniMap", "MobileControls"]:
        var item := scene.get_node_or_null(path) as CanvasItem
        if item != null:
            item.visible = false
    for path: String in ["PrototypeCar", "PhysicalCarB", "MidiUrbanLife"]:
        var spatial := scene.get_node_or_null(path) as Node3D
        if spatial != null:
            spatial.visible = false
    var traffic := scene.get_node_or_null("TrafficManager")
    if traffic != null:
        traffic.set("auto_spawn_runtime", false)
        if traffic is Node3D:
            (traffic as Node3D).visible = false

func _capture(viewport: SubViewport) -> bool:
    RenderingServer.force_draw()
    await process_frame
    var image := viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        return false
    var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    return image.save_png(absolute) == OK

func _run() -> void:
    var viewport := SubViewport.new()
    viewport.size = Vector2i(WIDTH, HEIGHT)
    viewport.own_world_3d = true
    viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    root.add_child(viewport)

    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    _hide_dynamic(scene)
    for _frame: int in range(36):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("production Player missing")
        return

    var resolver := RESOLVER_SCRIPT.new()
    viewport.add_child(resolver)
    if not resolver.apply_to_player(player, LEMONNIER_ID):
        _fail("road-359177328 did not resolve into a collision-safe rendered road")
        return

    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != LEMONNIER_ID:
        _fail("OSM identity metadata drifted")
        return
    if str(player.get_meta("automatic_road_direct_source_path", "")) != SOURCE_PATH:
        _fail("source path provenance drifted")
        return
    if str(player.get_meta("automatic_road_direct_source_sha256", "")).to_lower() != SOURCE_SHA256:
        _fail("source digest provenance drifted")
        return
    if not str(player.get_meta("automatic_road_direct_source_name", "")).contains("Maurice Lemonnier"):
        _fail("source road name drifted")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("source sightline safety proof missing")
        return
    var ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(ground_y):
        _fail("physics-backed ground height missing")
        return
    var spawn_xz: Vector2 = player.get_meta("automatic_road_direct_spawn_xz", Vector2(INF, INF))
    var target_xz: Vector2 = player.get_meta("automatic_road_direct_target_xz", Vector2(INF, INF))
    if not is_finite(spawn_xz.x) or not is_finite(spawn_xz.y) or not is_finite(target_xz.x) or not is_finite(target_xz.y):
        _fail("spawn/target coordinates are not finite")
        return
    var offset_m := float(player.get_meta("automatic_road_direct_offset_m", -1.0))
    if offset_m < 4.0 or offset_m > 20.0:
        _fail("safe player offset escaped bounded road-side envelope: %.3f" % offset_m)
        return
    if absf(player.global_position.y - (ground_y + 1.05)) > 0.01:
        _fail("player body clearance no longer matches physics-backed ground")
        return

    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null:
        _fail("production player camera missing")
        return
    camera.current = true
    for _frame: int in range(12):
        await process_frame
    if not await _capture(viewport):
        _fail("1280x720 player-view capture failed")
        return

    print("AUTOMATIC_ROAD_DIRECT_SPAWN_WITNESS_GREEN: osm_id=%d name=%s spawn=(%.3f,%.3f) target=(%.3f,%.3f) ground_y=%.3f offset_m=%.3f source_sha=%s frame=%s" % [LEMONNIER_ID, str(player.get_meta("automatic_road_direct_source_name", "")), spawn_xz.x, spawn_xz.y, target_xz.x, target_xz.y, ground_y, offset_m, SOURCE_SHA256, OUTPUT_PATH])
    quit(0)
