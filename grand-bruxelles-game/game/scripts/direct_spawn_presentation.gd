extends Node

## Presentation/direct-entry handling for browser location links.
## Source geography is read from the shipped OSM payload; this script never
## mutates road/building geometry or promotes a zone.

const ATOMIUM_DIRECT_FOV_DEGREES := 48.0
const CAMERA_PATH := "CameraPivot/SpringArm3D/Camera3D"
const BASE_VISUAL_PATH := "MeshInstance3D"
const UPGRADE_VISUAL_PATH := "VisualUpgrade"

const LEMONNIER_OSM_PATH := "res://data/osm/vertical_slice_01.game.json"
const LEMONNIER_OSM_ID := 359177328
const LEMONNIER_EXPECTED_NAME := "Boulevard Maurice Lemonnier - Maurice Lemonnierlaan"
const LEMONNIER_PLAYER_BODY_Y := 1.05
const LEMONNIER_LABEL := "BOULEVARD MAURICE LEMONNIER · MAURICE LEMONNIERLAAN"


func _ready() -> void:
    call_deferred("_apply_startup_args")


func _apply_startup_args() -> void:
    var args := OS.get_cmdline_user_args()
    var requested := _direct_spawn_value(args)
    if requested not in ["atomium", "lemonnier"]:
        return
    for _frame: int in range(24):
        var player := get_tree().root.find_child("Player", true, false)
        if player != null and apply_to_player(player, args):
            return
        await get_tree().process_frame
    push_warning("DirectSpawnPresentation: %s player/direct-entry unavailable" % requested)


func _direct_spawn_value(args: PackedStringArray) -> String:
    for arg: String in args:
        var normalized := arg.strip_edges().to_lower()
        if normalized.begins_with("spawn="):
            return normalized.trim_prefix("spawn=")
    return ""


func _wants_atomium(args: PackedStringArray) -> bool:
    return _direct_spawn_value(args) == "atomium"


func _wants_lemonnier(args: PackedStringArray) -> bool:
    return _direct_spawn_value(args) == "lemonnier"


func apply_to_player(player: Node, args: PackedStringArray) -> bool:
    if player == null:
        return false
    if _wants_atomium(args):
        return _apply_atomium_presentation(player)
    if _wants_lemonnier(args):
        return _apply_lemonnier_direct_spawn(player)
    return false


func _apply_atomium_presentation(player: Node) -> bool:
    var camera := player.get_node_or_null(CAMERA_PATH) as Camera3D
    if camera == null:
        return false
    camera.fov = ATOMIUM_DIRECT_FOV_DEGREES

    # The direct Atomium URL is a presentation witness. Keep the third-person
    # camera position but remove the avatar occluder so the landmark itself is
    # judgeable. This does not alter player collision, movement or world data.
    var base_visual := player.get_node_or_null(BASE_VISUAL_PATH) as Node3D
    if base_visual != null:
        base_visual.visible = false
    var upgrade_visual := player.get_node_or_null(UPGRADE_VISUAL_PATH) as Node3D
    if upgrade_visual != null:
        upgrade_visual.visible = false

    player.set_meta("atomium_direct_presentation_fov_degrees", ATOMIUM_DIRECT_FOV_DEGREES)
    player.set_meta("atomium_direct_presentation_avatar_hidden", true)
    print("ATOMIUM_DIRECT_PRESENTATION_READY: fov=%.1f avatar_hidden=true" % ATOMIUM_DIRECT_FOV_DEGREES)
    return true


func _load_lemonnier_source() -> Dictionary:
    if not FileAccess.file_exists(LEMONNIER_OSM_PATH):
        push_error("Lemonnier direct spawn: OSM source payload missing")
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEMONNIER_OSM_PATH))
    if not parsed is Dictionary:
        push_error("Lemonnier direct spawn: OSM source payload invalid")
        return {}
    return parsed as Dictionary


func _lemonnier_road(document: Dictionary) -> Dictionary:
    var roads: Variant = document.get("roads", [])
    if not roads is Array:
        return {}
    for raw: Variant in roads:
        if not raw is Dictionary:
            continue
        var road := raw as Dictionary
        if int(road.get("osm_id", 0)) == LEMONNIER_OSM_ID:
            return road
    return {}


func _road_points(road: Dictionary) -> PackedVector2Array:
    var result := PackedVector2Array()
    var raw_points: Variant = road.get("points", [])
    if not raw_points is Array:
        return result
    for raw: Variant in raw_points:
        if not raw is Array or raw.size() < 2:
            return PackedVector2Array()
        result.append(Vector2(float(raw[0]), float(raw[1])))
    return result


func _point_inside_any_source_building(document: Dictionary, point: Vector2) -> bool:
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


func _display_road_width(road: Dictionary) -> float:
    var width := float(road.get("width", 4.5))
    var road_class := str(road.get("class", ""))
    if road_class == "primary":
        return maxf(width, 10.5)
    if road_class == "secondary":
        return maxf(width, 8.5)
    if road_class == "tertiary":
        return maxf(width, 7.2)
    return width


func _lemonnier_viewpoint(document: Dictionary, road: Dictionary) -> Dictionary:
    var points := _road_points(road)
    if points.size() < 2:
        return {}

    # Use the longest exact source segment so the arrival looks along a
    # meaningful stretch of the street rather than at a tiny endpoint chord.
    var longest_index := -1
    var longest_length := -1.0
    for index: int in range(points.size() - 1):
        var length := points[index].distance_to(points[index + 1])
        if length > longest_length:
            longest_length = length
            longest_index = index
    if longest_index < 0 or longest_length < 1.0:
        return {}

    var start := points[longest_index]
    var finish := points[longest_index + 1]
    var target := start.lerp(finish, 0.5)
    var direction := (finish - start).normalized()
    var perpendicular := Vector2(-direction.y, direction.x)
    var half_road := _display_road_width(road) * 0.5
    var offsets: Array[float] = [half_road + 1.10, half_road + 2.00, half_road + 3.50, half_road + 5.00, half_road + 7.50]

    # Both sides are tried, nearest-to-road first. The first point outside every
    # source building footprint becomes the presentation/player viewpoint.
    for offset: float in offsets:
        for side: float in [1.0, -1.0]:
            var candidate := target + perpendicular * offset * side
            if absf(candidate.x) > 890.0 or absf(candidate.y) > 890.0:
                continue
            if _point_inside_any_source_building(document, candidate):
                continue
            return {
                "spawn": candidate,
                "target": target,
                "offset_m": offset,
                "side": side,
                "segment_index": longest_index,
                "segment_length_m": longest_length,
            }
    return {}


func _apply_lemonnier_direct_spawn(player: Node) -> bool:
    var body := player as CharacterBody3D
    if body == null:
        return false
    var document := _load_lemonnier_source()
    if document.is_empty():
        return false
    var road := _lemonnier_road(document)
    if road.is_empty():
        push_error("Lemonnier direct spawn: exact OSM way 359177328 missing")
        return false
    if str(road.get("name", "")) != LEMONNIER_EXPECTED_NAME or not bool(road.get("drivable", false)):
        push_error("Lemonnier direct spawn: source identity/drivable contract drifted")
        return false
    var points := _road_points(road)
    if points.size() != 6:
        push_error("Lemonnier direct spawn: expected six exact source points")
        return false
    var viewpoint := _lemonnier_viewpoint(document, road)
    if viewpoint.is_empty():
        push_error("Lemonnier direct spawn: no source-building-safe viewpoint resolved")
        return false

    var spawn_xz: Vector2 = viewpoint["spawn"]
    var target_xz: Vector2 = viewpoint["target"]
    body.global_position = Vector3(spawn_xz.x, LEMONNIER_PLAYER_BODY_Y, spawn_xz.y)
    body.velocity = Vector3.ZERO
    var to_target := target_xz - spawn_xz
    body.rotation_degrees.y = rad_to_deg(atan2(-to_target.x, -to_target.y))

    body.set_meta("lemonnier_direct_osm_id", LEMONNIER_OSM_ID)
    body.set_meta("lemonnier_direct_source_name", LEMONNIER_EXPECTED_NAME)
    body.set_meta("lemonnier_direct_spawn_xz", spawn_xz)
    body.set_meta("lemonnier_direct_target_xz", target_xz)
    body.set_meta("lemonnier_direct_offset_m", float(viewpoint["offset_m"]))
    body.set_meta("lemonnier_direct_segment_index", int(viewpoint["segment_index"]))

    var world := body.get_parent()
    if world != null:
        var location_label := world.get_node_or_null("LocationLabel")
        if location_label != null and location_label.has_method("set_forced_label"):
            location_label.call("set_forced_label", LEMONNIER_LABEL)
        elif location_label is Label:
            (location_label as Label).text = LEMONNIER_LABEL

    print(
        "LEMONNIER_DIRECT_SPAWN_READY: osm_id=%d segment=%d offset=%.3f spawn=(%.3f, %.3f) target=(%.3f, %.3f)" % [
            LEMONNIER_OSM_ID,
            int(viewpoint["segment_index"]),
            float(viewpoint["offset_m"]),
            spawn_xz.x,
            spawn_xz.y,
            target_xz.x,
            target_xz.y,
        ]
    )
    return true
