extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const DIRECT_SPAWN_SCRIPT := preload("res://game/scripts/direct_spawn_presentation.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const EXPECTED_SOURCE_SHA256 := "a96123a6098c2a94dcef2622b6ea099c831f426e1ebfeb28a2edda74675c2493"
const EXPECTED_OSM_ID := 359177328
const EXPECTED_NAME := "Boulevard Maurice Lemonnier - Maurice Lemonnierlaan"
const OUTPUT_PATH := "res://artifacts/lemonnier/lemonnier_direct_spawn.png"
const WIDTH := 1280
const HEIGHT := 720


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("LEMONNIER_DIRECT_SPAWN_FAIL: %s" % message)
    quit(1)


func _sha256_file(path: String) -> String:
    var file := FileAccess.open(path, FileAccess.READ)
    if file == null:
        return ""
    var context := HashingContext.new()
    if context.start(HashingContext.HASH_SHA256) != OK:
        return ""
    while file.get_position() < file.get_length():
        context.update(file.get_buffer(mini(1024 * 1024, file.get_length() - file.get_position())))
    return context.finish().hex_encode()


func _source_document() -> Dictionary:
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    return parsed as Dictionary if parsed is Dictionary else {}


func _road(document: Dictionary) -> Dictionary:
    var roads: Variant = document.get("roads", [])
    if not roads is Array:
        return {}
    for raw: Variant in roads:
        if raw is Dictionary and int((raw as Dictionary).get("osm_id", 0)) == EXPECTED_OSM_ID:
            return raw as Dictionary
    return {}


func _road_points(road: Dictionary) -> PackedVector2Array:
    var result := PackedVector2Array()
    var points: Variant = road.get("points", [])
    if not points is Array:
        return result
    for raw: Variant in points:
        if not raw is Array or raw.size() < 2:
            return PackedVector2Array()
        result.append(Vector2(float(raw[0]), float(raw[1])))
    return result


func _point_segment_distance(point: Vector2, start: Vector2, finish: Vector2) -> float:
    var segment := finish - start
    var length_squared := segment.length_squared()
    if length_squared <= 0.000001:
        return point.distance_to(start)
    var amount := clampf((point - start).dot(segment) / length_squared, 0.0, 1.0)
    return point.distance_to(start + segment * amount)


func _distance_to_road(point: Vector2, points: PackedVector2Array) -> float:
    var result := INF
    for index: int in range(points.size() - 1):
        result = minf(result, _point_segment_distance(point, points[index], points[index + 1]))
    return result


func _inside_source_building(document: Dictionary, point: Vector2) -> bool:
    var buildings: Variant = document.get("buildings", [])
    if not buildings is Array:
        return false
    for raw: Variant in buildings:
        if not raw is Dictionary:
            continue
        var footprint_raw: Variant = (raw as Dictionary).get("footprint", [])
        if not footprint_raw is Array or footprint_raw.size() < 3:
            continue
        var polygon := PackedVector2Array()
        for pair: Variant in footprint_raw:
            if pair is Array and pair.size() >= 2:
                polygon.append(Vector2(float(pair[0]), float(pair[1])))
        if polygon.size() >= 3 and Geometry2D.is_point_in_polygon(point, polygon):
            return true
    return false


func _run() -> void:
    if _sha256_file(SOURCE_PATH) != EXPECTED_SOURCE_SHA256:
        _fail("locked OSM source hash drifted")
        return
    var document := _source_document()
    var road := _road(document)
    if road.is_empty():
        _fail("OSM way 359177328 missing")
        return
    if str(road.get("name", "")) != EXPECTED_NAME or not bool(road.get("drivable", false)):
        _fail("road identity/drivable source contract drifted")
        return
    var points := _road_points(road)
    if points.size() != 6:
        _fail("expected six exact Lemonnier source points")
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(8):
        await process_frame

    var rendered_road := main.find_child("Road_359177328_0", true, false)
    if rendered_road == null:
        _fail("OSM way 359177328 is source-present but not rendered in the production scene")
        return

    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing")
        return
    var original_position := player.global_position
    var presentation := DIRECT_SPAWN_SCRIPT.new()
    if presentation.apply_to_player(player, PackedStringArray(["spawn=unknown-destination"])):
        _fail("unknown direct spawn was accepted")
        return
    if player.global_position.distance_to(original_position) > 0.001:
        _fail("unknown direct spawn moved the player")
        return
    if not presentation.apply_to_player(player, PackedStringArray(["spawn=lemonnier"])):
        _fail("Lemonnier direct spawn refused")
        return

    await physics_frame
    await physics_frame
    var spawn_xz := Vector2(player.global_position.x, player.global_position.z)
    var distance_to_road := _distance_to_road(spawn_xz, points)
    var rendered_width := maxf(float(road.get("width", 0.0)), 7.2)
    if distance_to_road < rendered_width * 0.5 + 0.75:
        _fail("player spawn is too close to/on the rendered roadway: %.3f m" % distance_to_road)
        return
    if distance_to_road > rendered_width * 0.5 + 8.0:
        _fail("player spawn is too far from the tested street: %.3f m" % distance_to_road)
        return
    if _inside_source_building(document, spawn_xz):
        _fail("player spawn intersects a source building footprint")
        return
    if int(player.get_meta("lemonnier_direct_osm_id", 0)) != EXPECTED_OSM_ID:
        _fail("source-backed player metadata missing")
        return

    var label := main.get_node_or_null("LocationLabel") as Label
    if label == null or not label.text.contains("MAURICE LEMONNIER"):
        _fail("street identity label missing")
        return

    var target_meta: Variant = player.get_meta("lemonnier_direct_target_xz", Vector2(INF, INF))
    if not target_meta is Vector2:
        _fail("camera target metadata missing")
        return
    var target_xz := target_meta as Vector2
    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null:
        _fail("player camera missing")
        return
    for _frame: int in range(6):
        await process_frame
    var target_world := Vector3(target_xz.x, 0.12, target_xz.y)
    if camera.is_position_behind(target_world):
        _fail("tested street target is behind the camera")
        return
    var screen := camera.unproject_position(target_world)
    if screen.x < 0.0 or screen.x > WIDTH or screen.y < 0.0 or screen.y > HEIGHT:
        _fail("tested street target is outside the 1280x720 player frame: %s" % screen)
        return

    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty() or image.get_width() != WIDTH or image.get_height() != HEIGHT:
        _fail("capture invalid")
        return
    var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute_output.get_base_dir())
    if image.save_png(absolute_output) != OK:
        _fail("capture save failed")
        return

    print(
        "LEMONNIER_DIRECT_SPAWN_OK: osm_id=%d distance_to_road=%.3f spawn=(%.3f, %.3f, %.3f) target_screen=(%.1f, %.1f) capture=%s" % [
            EXPECTED_OSM_ID,
            distance_to_road,
            player.global_position.x,
            player.global_position.y,
            player.global_position.z,
            screen.x,
            screen.y,
            OUTPUT_PATH,
        ]
    )
    quit(0)
