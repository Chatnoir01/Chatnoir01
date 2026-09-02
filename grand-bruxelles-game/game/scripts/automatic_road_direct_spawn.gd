extends Node

## Generic source-backed direct-entry resolver for rendered Brussels roads.
## URL/user arg format: spawn=road-<OSM way id>.
## No arbitrary coordinates are accepted. Unknown, non-drivable, unrendered or
## source-unsafe roads fail closed.

const RUNTIME_INDEX_PATH := "res://data/runtime/road_destination_runtime_index.json"
const RUNTIME_INDEX_FORMAT := "grand-bruxelles-road-runtime-index-v1"
const REQUEST_PREFIX := "road-"
const PLAYER_BODY_CLEARANCE_M := 1.05
const MAX_WORLD_ABS_M := 890.0
const MIN_SOURCE_AXIS_ALIGNMENT := 0.90
const CAMERA_PATH := "CameraPivot/SpringArm3D/Camera3D"
const ROAD_SUPPORT_COLLISION_MASK := 1 << 19
const CANONICAL_GROUND_COLLISION_MASK := 1
const SAFE_GROUND_COLLISION_MASK := ROAD_SUPPORT_COLLISION_MASK | CANONICAL_GROUND_COLLISION_MASK
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const CANONICAL_GROUND_NAME := "Ground"
const MAX_GROUND_RAY_HITS := 32

var _runtime_index_attempted := false
var _runtime_index_valid := false
var _road_source_path_by_id: Dictionary = {}
var _source_sha_by_path: Dictionary = {}


func _ready() -> void:
    call_deferred("_apply_startup_args")


func _is_authoritative_main(candidate: Node, root: Node) -> bool:
    if candidate == null or root == null or str(candidate.name) != "Main":
        return false
    var parent := candidate.get_parent()
    if parent == root:
        return true
    return parent is Viewport and parent.get_parent() == root


func _authoritative_main(root: Node) -> Node:
    if root == null:
        return null
    var current := get_tree().current_scene
    if _is_authoritative_main(current, root):
        return current
    var direct := root.get_node_or_null("Main")
    if _is_authoritative_main(direct, root):
        return direct
    for child: Node in root.get_children():
        if not child is Viewport:
            continue
        var candidate := child.get_node_or_null("Main")
        if _is_authoritative_main(candidate, root):
            return candidate
    return null


func _authoritative_player(root: Node) -> CharacterBody3D:
    var main := _authoritative_main(root)
    if main == null:
        return null
    var player := main.get_node_or_null("Player")
    if player == null or player.get_parent() != main:
        return null
    return player as CharacterBody3D


func _apply_startup_args() -> void:
    var road_id := requested_road_id(OS.get_cmdline_user_args())
    if road_id <= 0:
        return
    for _frame: int in range(36):
        var player := _authoritative_player(get_tree().root)
        if player != null and apply_to_player(player, road_id):
            return
        await get_tree().process_frame
    push_warning("AutomaticRoadDirectSpawn: road-%d unavailable or not safely playable" % road_id)


func requested_road_id(args: PackedStringArray) -> int:
    for arg: String in args:
        var normalized := arg.strip_edges().to_lower()
        if not normalized.begins_with("spawn="):
            continue
        var value := normalized.trim_prefix("spawn=")
        if not value.begins_with(REQUEST_PREFIX):
            return 0
        var raw_id := value.trim_prefix(REQUEST_PREFIX)
        if raw_id.is_empty() or not raw_id.is_valid_int():
            return 0
        var road_id := int(raw_id)
        return road_id if road_id > 0 else 0
    return 0


func _parse_document(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
    return parsed as Dictionary if parsed is Dictionary else {}


func _load_runtime_index() -> bool:
    if _runtime_index_attempted:
        return _runtime_index_valid
    _runtime_index_attempted = true
    _runtime_index_valid = false
    _road_source_path_by_id.clear()
    _source_sha_by_path.clear()

    var index := _parse_document(RUNTIME_INDEX_PATH)
    if index.is_empty() or str(index.get("format", "")) != RUNTIME_INDEX_FORMAT:
        return false
    if not bool(index.get("source_lookup_only", false)):
        return false
    var authorization: Variant = index.get("authorization", {})
    if not authorization is Dictionary:
        return false
    var auth := authorization as Dictionary
    if not bool(auth.get("source_lookup_only", false)):
        return false
    for forbidden: String in ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"]:
        if bool(auth.get(forbidden, true)):
            return false

    var documents: Variant = index.get("documents", [])
    if not documents is Array or documents.is_empty():
        return false
    for raw_document: Variant in documents:
        if not raw_document is Dictionary:
            return false
        var descriptor := raw_document as Dictionary
        var source_path := str(descriptor.get("path", "")).strip_edges()
        var expected_sha := str(descriptor.get("sha256", "")).strip_edges().to_lower()
        var road_ids: Variant = descriptor.get("road_ids", [])
        if source_path.is_empty() or expected_sha.length() != 64 or not road_ids is Array or road_ids.is_empty():
            return false
        if not source_path.begins_with("res://"):
            source_path = "res://" + source_path.trim_prefix("/")
        if _source_sha_by_path.has(source_path) and str(_source_sha_by_path[source_path]) != expected_sha:
            return false
        _source_sha_by_path[source_path] = expected_sha
        for raw_id: Variant in road_ids:
            var osm_id := int(raw_id)
            if osm_id <= 0 or _road_source_path_by_id.has(osm_id):
                return false
            _road_source_path_by_id[osm_id] = source_path

    _runtime_index_valid = not _road_source_path_by_id.is_empty()
    return _runtime_index_valid


func runtime_index_road_count() -> int:
    return _road_source_path_by_id.size() if _load_runtime_index() else 0


func runtime_index_source_document_count() -> int:
    return _source_sha_by_path.size() if _load_runtime_index() else 0


func _source_bundle_by_id(osm_id: int) -> Dictionary:
    if osm_id <= 0 or not _load_runtime_index() or not _road_source_path_by_id.has(osm_id):
        return {}
    var path := str(_road_source_path_by_id[osm_id])
    var expected_sha := str(_source_sha_by_path.get(path, ""))
    var actual_sha := FileAccess.get_sha256(path).to_lower()
    if expected_sha.is_empty() or actual_sha.is_empty() or actual_sha != expected_sha:
        return {}
    var document := _parse_document(path)
    if document.is_empty() or not document.has("roads") or not document.has("buildings"):
        return {}
    var roads: Variant = document.get("roads", [])
    if not roads is Array:
        return {}
    for raw: Variant in roads:
        if not raw is Dictionary:
            continue
        var road := raw as Dictionary
        if int(road.get("osm_id", 0)) != osm_id:
            continue
        var source_name := str(road.get("name", "")).strip_edges()
        if source_name.is_empty() or not bool(road.get("drivable", false)) or _road_points(road).size() < 2:
            return {}
        return {
            "document": document,
            "road": road,
            "source_path": path,
            "source_sha256": actual_sha,
            "lookup_mode": "deterministic_runtime_index",
        }
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


func _point_inside_any_source_building(document: Dictionary, point: Vector2) -> bool:
    for polygon: PackedVector2Array in _source_building_polygons(document):
        if Geometry2D.is_point_in_polygon(point, polygon):
            return true
    return false


func _segment_clear_of_source_buildings(document: Dictionary, start: Vector2, finish: Vector2) -> bool:
    if _point_inside_any_source_building(document, start) or _point_inside_any_source_building(document, finish):
        return false
    for polygon: PackedVector2Array in _source_building_polygons(document):
        for index: int in range(polygon.size()):
            var edge_start := polygon[index]
            var edge_finish := polygon[(index + 1) % polygon.size()]
            if Geometry2D.segment_intersects_segment(start, finish, edge_start, edge_finish) != null:
                return false
    return true


func _display_road_width(road: Dictionary) -> float:
    var width := maxf(float(road.get("width", 4.5)), 2.5)
    match str(road.get("class", "")):
        "primary":
            return maxf(width, 10.5)
        "secondary":
            return maxf(width, 8.5)
        "tertiary":
            return maxf(width, 7.2)
    return width


func _safe_viewpoint(document: Dictionary, road: Dictionary) -> Dictionary:
    var points := _road_points(road)
    if points.size() < 2:
        return {}
    var best_index := -1
    var best_length := -1.0
    for index: int in range(points.size() - 1):
        var length := points[index].distance_to(points[index + 1])
        if length > best_length:
            best_length = length
            best_index = index
    if best_index < 0 or best_length < 1.0:
        return {}
    var start := points[best_index]
    var finish := points[best_index + 1]
    var midpoint := start.lerp(finish, 0.5)
    if _point_inside_any_source_building(document, midpoint):
        return {}
    var direction := (finish - start).normalized()
    if direction == Vector2.ZERO:
        return {}
    var perpendicular := Vector2(-direction.y, direction.x)
    var half_road := _display_road_width(road) * 0.5
    var offsets: Array[float] = [half_road + 1.10, half_road + 2.00, half_road + 3.50, half_road + 5.00, half_road + 7.50]
    for offset: float in offsets:
        # Keep the target on the exact source segment and enforce the actual
        # player-view invariant directly. The old 45% proxy could reject a
        # valid segment by centimeters even when its true source-axis alignment
        # was >= 0.90. Half the segment length is the exact geometric boundary
        # from the midpoint; the explicit alignment gate remains fail-closed.
        var required_lookahead := offset * 2.10
        var max_segment_lookahead := best_length * 0.5
        var lookahead := minf(22.0, max_segment_lookahead)
        if lookahead < required_lookahead:
            continue
        for side: float in [1.0, -1.0]:
            var candidate := midpoint + perpendicular * offset * side
            if absf(candidate.x) > MAX_WORLD_ABS_M or absf(candidate.y) > MAX_WORLD_ABS_M:
                continue
            if _point_inside_any_source_building(document, candidate):
                continue
            for along_sign: float in [1.0, -1.0]:
                var target := midpoint + direction * lookahead * along_sign
                if absf(target.x) > MAX_WORLD_ABS_M or absf(target.y) > MAX_WORLD_ABS_M:
                    continue
                if _point_inside_any_source_building(document, target):
                    continue
                var view_axis := target - candidate
                if view_axis == Vector2.ZERO:
                    continue
                var axis_alignment := absf(view_axis.normalized().dot(direction))
                if axis_alignment < MIN_SOURCE_AXIS_ALIGNMENT:
                    continue
                if not _segment_clear_of_source_buildings(document, candidate, target):
                    continue
                return {
                    "spawn": candidate,
                    "target": target,
                    "offset_m": offset,
                    "side": side,
                    "segment_index": best_index,
                    "source_sightline_clear": true,
                    "axis_lookahead_m": lookahead,
                    "axis_alignment": axis_alignment,
                }
    return {}


func _geometry_has_renderable_content(node: GeometryInstance3D) -> bool:
    if not node.is_visible_in_tree():
        return false
    if node is MeshInstance3D:
        return (node as MeshInstance3D).mesh != null
    if node is MultiMeshInstance3D:
        var multimesh := (node as MultiMeshInstance3D).multimesh
        if multimesh == null or multimesh.mesh == null or multimesh.instance_count <= 0:
            return false
        return multimesh.visible_instance_count != 0
    if node is CSGShape3D:
        return true
    return false


func _road_is_rendered(world: Node, osm_id: int) -> bool:
    var prefix := "Road_%d_" % osm_id
    var stack: Array[Node] = [world]
    while not stack.is_empty():
        var node: Node = stack.pop_back()
        if str(node.name).begins_with(prefix) and node is GeometryInstance3D and _geometry_has_renderable_content(node as GeometryInstance3D):
            return true
        for child: Node in node.get_children():
            stack.append(child)
    return false


func _ground_hit_is_authorized(collider: Object, canonical_ground: Node) -> bool:
    if canonical_ground != null and collider == canonical_ground:
        return true
    if collider is Node:
        return str((collider as Node).get_meta(ROAD_SUPPORT_OWNER_META, "")) == ROAD_SUPPORT_OWNER_ID
    return false


func _ground_y(body: CharacterBody3D, xz: Vector2) -> float:
    var world_3d := body.get_world_3d()
    if world_3d == null:
        return INF
    var scene_root := body.get_parent()
    var canonical_ground := scene_root.get_node_or_null(CANONICAL_GROUND_NAME) if scene_root != null else null
    var excluded: Array[RID] = [body.get_rid()]
    for _hit_index: int in range(MAX_GROUND_RAY_HITS):
        var query := PhysicsRayQueryParameters3D.create(
            Vector3(xz.x, 200.0, xz.y),
            Vector3(xz.x, -200.0, xz.y)
        )
        query.exclude = excluded
        query.collision_mask = SAFE_GROUND_COLLISION_MASK
        query.collide_with_areas = false
        query.collide_with_bodies = true
        var hit := world_3d.direct_space_state.intersect_ray(query)
        if hit.is_empty():
            return INF
        var collider: Variant = hit.get("collider")
        var position: Variant = hit.get("position")
        if collider is Object and _ground_hit_is_authorized(collider as Object, canonical_ground):
            return float((position as Vector3).y) if position is Vector3 else INF
        var hit_rid: Variant = hit.get("rid")
        if not hit_rid is RID or not (hit_rid as RID).is_valid():
            return INF
        excluded.append(hit_rid as RID)
    return INF


func _label_for_road(road: Dictionary) -> String:
    return str(road.get("name", "")).replace(" - ", " · ").to_upper()


func _orient_and_label(body: CharacterBody3D, spawn_xz: Vector2, target_xz: Vector2, label_text: String) -> void:
    body.velocity = Vector3.ZERO
    var to_target := target_xz - spawn_xz
    body.rotation_degrees.y = rad_to_deg(atan2(-to_target.x, -to_target.y))
    var world := body.get_parent()
    if world == null:
        return
    var location_label := world.get_node_or_null("LocationLabel")
    if location_label != null and location_label.has_method("set_forced_label"):
        location_label.call("set_forced_label", label_text)
    elif location_label is Label:
        (location_label as Label).text = label_text


func apply_to_player(player: Node, osm_id: int) -> bool:
    var body := player as CharacterBody3D
    if body == null or osm_id <= 0:
        return false
    var bundle := _source_bundle_by_id(osm_id)
    if bundle.is_empty():
        return false
    var document: Dictionary = bundle["document"]
    var road: Dictionary = bundle["road"]
    var source_path := str(bundle["source_path"])
    var source_name := str(road.get("name", "")).strip_edges()
    if source_name.is_empty() or not bool(road.get("drivable", false)):
        return false
    var points := _road_points(road)
    if points.size() < 2:
        return false
    var world := body.get_parent()
    if world == null or not _road_is_rendered(world, osm_id):
        return false
    var viewpoint := _safe_viewpoint(document, road)
    if viewpoint.is_empty():
        return false
    var spawn_xz: Vector2 = viewpoint["spawn"]
    var target_xz: Vector2 = viewpoint["target"]
    var ground_y := _ground_y(body, spawn_xz)
    if not is_finite(ground_y):
        return false
    body.global_position = Vector3(spawn_xz.x, ground_y + PLAYER_BODY_CLEARANCE_M, spawn_xz.y)
    _orient_and_label(body, spawn_xz, target_xz, _label_for_road(road))
    body.set_meta("automatic_road_direct_osm_id", osm_id)
    body.set_meta("automatic_road_direct_source_path", source_path)
    body.set_meta("automatic_road_direct_source_name", source_name)
    body.set_meta("automatic_road_direct_source_sha256", str(bundle.get("source_sha256", "")))
    body.set_meta("automatic_road_direct_lookup_mode", str(bundle.get("lookup_mode", "")))
    body.set_meta("automatic_road_direct_spawn_xz", spawn_xz)
    body.set_meta("automatic_road_direct_target_xz", target_xz)
    body.set_meta("automatic_road_direct_ground_y", ground_y)
    body.set_meta("automatic_road_direct_offset_m", float(viewpoint["offset_m"]))
    body.set_meta("automatic_road_direct_segment_index", int(viewpoint["segment_index"]))
    body.set_meta("automatic_road_direct_source_sightline_clear", bool(viewpoint.get("source_sightline_clear", false)))
    body.set_meta("automatic_road_direct_axis_lookahead_m", float(viewpoint.get("axis_lookahead_m", 0.0)))
    body.set_meta("automatic_road_direct_axis_alignment", float(viewpoint.get("axis_alignment", 0.0)))
    print("AUTOMATIC_ROAD_DIRECT_SPAWN_READY: osm_id=%d lookup=deterministic_runtime_index source=%s name=%s spawn=(%.3f, %.3f, %.3f) target=(%.3f, %.3f) axis_lookahead_m=%.3f axis_alignment=%.6f" % [osm_id, source_path, source_name, body.global_position.x, body.global_position.y, body.global_position.z, target_xz.x, target_xz.y, float(viewpoint.get("axis_lookahead_m", 0.0)), float(viewpoint.get("axis_alignment", 0.0))])
    return true
