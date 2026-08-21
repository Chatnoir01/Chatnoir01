extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const DIRECT_SPAWN_SCRIPT := preload("res://game/scripts/direct_spawn_presentation.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const EXPECTED_SOURCE_SHA256 := "a96123a6098c2a94dcef2622b6ea099c831f426e1ebfeb28a2edda74675c2493"
const EXPECTED_OSM_ID := 1382734012
const EXPECTED_NAME := "Place Anneessens - Anneessensplein"
const EXPECTED_ANCHOR := Vector2(-272.04, -217.07)
const OUTPUT_PATH := "res://artifacts/anneessens/anneessens_direct_spawn.png"
const WIDTH := 1280
const HEIGHT := 720

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_DIRECT_SPAWN_FAIL: %s" % message)
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
    if roads is Array:
        for raw: Variant in roads:
            if raw is Dictionary and int((raw as Dictionary).get("osm_id", 0)) == EXPECTED_OSM_ID:
                return raw as Dictionary
    return {}

func _anchor(document: Dictionary) -> Dictionary:
    var corridor: Variant = document.get("corridor", {})
    if not corridor is Dictionary:
        return {}
    var anchors: Variant = (corridor as Dictionary).get("anchors", [])
    if anchors is Array:
        for raw: Variant in anchors:
            if raw is Dictionary and str((raw as Dictionary).get("id", "")) == "anneessens":
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

func _source_building_polygons(document: Dictionary) -> Array[PackedVector2Array]:
    var result: Array[PackedVector2Array] = []
    var buildings: Variant = document.get("buildings", [])
    if not buildings is Array:
        return result
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
        if polygon.size() >= 3:
            result.append(polygon)
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
    for polygon: PackedVector2Array in _source_building_polygons(document):
        if Geometry2D.is_point_in_polygon(point, polygon):
            return true
    return false

func _source_sightline_clear(document: Dictionary, start: Vector2, finish: Vector2) -> bool:
    if _inside_source_building(document, start) or _inside_source_building(document, finish):
        return false
    for polygon: PackedVector2Array in _source_building_polygons(document):
        for index: int in range(polygon.size()):
            var intersection: Variant = Geometry2D.segment_intersects_segment(start, finish, polygon[index], polygon[(index + 1) % polygon.size()])
            if intersection != null:
                return false
    return true

func _run() -> void:
    if _sha256_file(SOURCE_PATH) != EXPECTED_SOURCE_SHA256:
        _fail("locked OSM source hash drifted")
        return
    var document := _source_document()
    var road := _road(document)
    if road.is_empty() or str(road.get("name", "")) != EXPECTED_NAME or not bool(road.get("drivable", false)):
        _fail("Anneessens OSM road identity/drivable contract drifted")
        return
    var points := _road_points(road)
    if points.size() < 2:
        _fail("Anneessens exact road points missing")
        return
    var anchor := _anchor(document)
    if anchor.is_empty():
        _fail("corridor Anneessens anchor missing")
        return
    var anchor_xz := Vector2(float(anchor.get("x", INF)), float(anchor.get("z", INF)))
    if anchor_xz.distance_to(EXPECTED_ANCHOR) > 0.001:
        _fail("corridor Anneessens anchor drifted: %s" % anchor_xz)
        return

    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    for _frame: int in range(8):
        await process_frame
    var player := main.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("player missing")
        return
    var presentation := DIRECT_SPAWN_SCRIPT.new()
    if not presentation.apply_to_player(player, PackedStringArray(["spawn=anneessens"])):
        _fail("Anneessens direct spawn refused")
        return
    await physics_frame
    await physics_frame

    var spawn_xz := Vector2(player.global_position.x, player.global_position.z)
    if spawn_xz.distance_to(EXPECTED_ANCHOR) > 45.0:
        _fail("spawn too far from official corridor anchor: %.3f m" % spawn_xz.distance_to(EXPECTED_ANCHOR))
        return
    if _inside_source_building(document, spawn_xz):
        _fail("spawn intersects a source building footprint")
        return
    if int(player.get_meta("anneessens_direct_osm_id", 0)) != EXPECTED_OSM_ID:
        _fail("source-backed Anneessens metadata missing")
        return

    var target_meta: Variant = player.get_meta("anneessens_direct_target_xz", Vector2(INF, INF))
    if not target_meta is Vector2:
        _fail("target metadata missing")
        return
    var target_xz := target_meta as Vector2
    var target_road_distance := _distance_to_road(target_xz, points)
    if target_road_distance > 0.01:
        _fail("camera target is not on exact OSM Place Anneessens road: %.3f m" % target_road_distance)
        return
    if _inside_source_building(document, target_xz):
        _fail("camera target intersects a source building footprint")
        return
    if not bool(player.get_meta("anneessens_direct_source_sightline_clear", false)):
        _fail("runtime did not prove a source-building-clear sightline")
        return
    if not _source_sightline_clear(document, spawn_xz, target_xz):
        _fail("spawn-to-Place-Anneessens target sightline crosses a source building footprint")
        return

    var camera := player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
    if camera == null:
        _fail("player camera missing")
        return
    for _frame: int in range(6):
        await process_frame
    var target_world := Vector3(target_xz.x, 0.12, target_xz.y)
    if camera.is_position_behind(target_world):
        _fail("Anneessens target behind camera")
        return
    var screen := camera.unproject_position(target_world)
    if screen.x < 0.0 or screen.x > WIDTH or screen.y < 0.0 or screen.y > HEIGHT:
        _fail("Anneessens target outside player frame: %s" % screen)
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
    print("ANNEESSENS_DIRECT_SPAWN_OK: osm_id=%d anchor_distance=%.3f target_road_distance=%.3f source_sightline_clear=true spawn=(%.3f, %.3f) target_screen=(%.1f, %.1f) capture=%s" % [EXPECTED_OSM_ID, spawn_xz.distance_to(EXPECTED_ANCHOR), target_road_distance, spawn_xz.x, spawn_xz.y, screen.x, screen.y, OUTPUT_PATH])
    quit(0)
