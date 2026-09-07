extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const BOURSE_ANCHOR_ID := "bourse"
const ROAD_SUPPORT_COLLISION_MASK := 1 << 19
const CANONICAL_GROUND_COLLISION_MASK := 1
const SAFE_GROUND_COLLISION_MASK := ROAD_SUPPORT_COLLISION_MASK | CANONICAL_GROUND_COLLISION_MASK
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"
const CANONICAL_GROUND_NAME := "Ground"
const MAX_RAY_HITS := 32
const GROUND_EPSILON_M := 0.01
const UNIQUE_ROUTE_EPSILON_M := 0.01
const PLAYER_CLEARANCE_M := 1.05
const WITNESS_PATH := "/tmp/bourse-automatic-road-player.png"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_AUTOMATIC_ROAD_PLAYER_WITNESS_FAIL: %s" % message)
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

func _distance_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
    var ab := b - a
    var denom := ab.length_squared()
    if denom <= 0.0000001:
        return point.distance_to(a)
    var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
    return point.distance_to(a + ab * t)

func _road_distance(anchor: Vector2, raw_points: Variant) -> float:
    if not raw_points is Array:
        return INF
    var points := raw_points as Array
    if points.is_empty():
        return INF
    var parsed: Array[Vector2] = []
    for raw: Variant in points:
        if not raw is Array or (raw as Array).size() != 2:
            return INF
        var pair := raw as Array
        if not (pair[0] is float or pair[0] is int) or not (pair[1] is float or pair[1] is int):
            return INF
        parsed.append(Vector2(float(pair[0]), float(pair[1])))
    if parsed.size() == 1:
        return anchor.distance_to(parsed[0])
    var best := INF
    for i: int in range(parsed.size() - 1):
        best = minf(best, _distance_to_segment(anchor, parsed[i], parsed[i + 1]))
    return best

func _source_bourse_road() -> Dictionary:
    var file := FileAccess.open(SOURCE_PATH, FileAccess.READ)
    if file == null:
        return {}
    var parsed: Variant = JSON.parse_string(file.get_as_text())
    if not parsed is Dictionary:
        return {}
    var doc := parsed as Dictionary
    if str(doc.get("format", "")) != "grand-bruxelles-osm-v1":
        return {}
    if str(doc.get("source", "")) != "OpenStreetMap contributors via Overpass API":
        return {}
    if str(doc.get("license", "")) != "ODbL-1.0":
        return {}
    var corridor: Variant = doc.get("corridor", {})
    if not corridor is Dictionary:
        return {}
    var anchor := Vector2(INF, INF)
    for raw_anchor: Variant in (corridor as Dictionary).get("anchors", []):
        if not raw_anchor is Dictionary:
            continue
        var entry := raw_anchor as Dictionary
        if str(entry.get("id", "")) == BOURSE_ANCHOR_ID:
            anchor = Vector2(float(entry.get("x", INF)), float(entry.get("z", INF)))
            break
    if not is_finite(anchor.x) or not is_finite(anchor.y):
        return {}

    var ranked: Array[Dictionary] = []
    for raw_road: Variant in doc.get("roads", []):
        if not raw_road is Dictionary:
            continue
        var road := raw_road as Dictionary
        if road.get("drivable", false) != true:
            continue
        var raw_id: Variant = road.get("osm_id")
        if not (raw_id is int or raw_id is float):
            continue
        var numeric_id := float(raw_id)
        if not is_finite(numeric_id) or floor(numeric_id) != numeric_id:
            continue
        var distance := _road_distance(anchor, road.get("points", []))
        if not is_finite(distance):
            continue
        ranked.append({
            "osm_id": int(numeric_id),
            "name": str(road.get("name", "")),
            "class": str(road.get("class", "")),
            "distance_m": distance,
            "anchor_x": anchor.x,
            "anchor_z": anchor.y,
        })
    if ranked.size() < 2:
        return {}
    ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if absf(float(a["distance_m"]) - float(b["distance_m"])) > 0.000001:
            return float(a["distance_m"]) < float(b["distance_m"])
        return int(a["osm_id"]) < int(b["osm_id"])
    )
    var first := ranked[0]
    var second := ranked[1]
    if int(first["osm_id"]) == int(second["osm_id"]):
        return {}
    if float(second["distance_m"]) - float(first["distance_m"]) <= UNIQUE_ROUTE_EPSILON_M:
        return {}
    first["runner_up_osm_id"] = int(second["osm_id"])
    first["runner_up_distance_m"] = float(second["distance_m"])
    return first

func _contains_osm_id(raw_ids: Variant, osm_id: int) -> bool:
    if not raw_ids is Array:
        return false
    for raw: Variant in raw_ids:
        if not (raw is int or raw is float):
            return false
        var numeric := float(raw)
        if not is_finite(numeric) or floor(numeric) != numeric:
            return false
        if int(numeric) == osm_id:
            return true
    return false

func _authorized_support(collider: Object, osm_id: int) -> Dictionary:
    if collider == null or not collider is Node:
        return {}
    var node := collider as Node
    if str(node.name) == CANONICAL_GROUND_NAME:
        if not node is CollisionObject3D:
            return {}
        var body := node as CollisionObject3D
        if (body.collision_layer & CANONICAL_GROUND_COLLISION_MASK) == 0:
            return {}
        return {"kind": "canonical_ground", "path": str(node.get_path()), "layer": body.collision_layer}
    if str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")) != ROAD_SUPPORT_OWNER_ID:
        return {}
    if not node is CollisionObject3D:
        return {}
    var support := node as CollisionObject3D
    if (support.collision_layer & ROAD_SUPPORT_COLLISION_MASK) == 0:
        return {}
    if not _contains_osm_id(node.get_meta(ROAD_SUPPORT_OSM_IDS_META, []), osm_id):
        return {}
    return {
        "kind": "source_road_support",
        "path": str(node.get_path()),
        "layer": support.collision_layer,
        "owner": str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")),
    }

func _support_below(player: CharacterBody3D, osm_id: int) -> Dictionary:
    var world := player.get_world_3d()
    if world == null:
        return {}
    var excluded: Array[RID] = []
    for _attempt: int in range(MAX_RAY_HITS):
        var query := PhysicsRayQueryParameters3D.create(
            player.global_position + Vector3(0.0, 25.0, 0.0),
            Vector3(player.global_position.x, -200.0, player.global_position.z)
        )
        query.collision_mask = SAFE_GROUND_COLLISION_MASK
        query.collide_with_areas = false
        query.collide_with_bodies = true
        query.exclude = excluded
        var hit := world.direct_space_state.intersect_ray(query)
        if hit.is_empty():
            return {}
        var collider: Variant = hit.get("collider")
        var position: Variant = hit.get("position")
        if collider is Object and position is Vector3:
            var identity := _authorized_support(collider as Object, osm_id)
            if not identity.is_empty():
                identity["y"] = (position as Vector3).y
                return identity
        var rid: Variant = hit.get("rid")
        if not rid is RID or not (rid as RID).is_valid():
            return {}
        excluded.append(rid as RID)
    return {}

func _image_sha256(image: Image) -> String:
    var ctx := HashingContext.new()
    ctx.start(HashingContext.HASH_SHA256)
    ctx.update(image.get_data())
    return ctx.finish().hex_encode()

func _run() -> void:
    var source_road := _source_bourse_road()
    if source_road.is_empty():
        _fail("Bourse source anchor did not yield one unique nearest drivable OSM road")
        return
    var osm_id := int(source_road["osm_id"])

    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.own_world_3d = true
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
    if not resolver.apply_to_player(player, osm_id):
        _fail("source-derived road-%d did not resolve into a rendered collision-safe destination" % osm_id)
        return

    var expected_ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(expected_ground_y):
        _fail("resolver did not record physics-backed ground height")
        return
    await physics_frame
    var support := _support_below(player, osm_id)
    if support.is_empty():
        _fail("no independently verified authorized support collider below Bourse automatic-road spawn")
        return
    var observed_ground_y := float(support.get("y", INF))
    if not is_finite(observed_ground_y) or absf(observed_ground_y - expected_ground_y) > GROUND_EPSILON_M:
        _fail("support height disagrees with resolver ground_y")
        return
    if absf(player.global_position.y - (observed_ground_y + PLAYER_CLEARANCE_M)) > GROUND_EPSILON_M:
        _fail("player clearance is not tied to independently verified ground support")
        return

    for _frame: int in range(8):
        await process_frame
    await RenderingServer.frame_post_draw
    var image := viewport.get_texture().get_image()
    if image == null or image.get_width() != 1280 or image.get_height() != 720:
        _fail("player-view witness is not an exact 1280x720 production frame")
        return
    var bytes := image.get_data()
    if bytes.is_empty():
        _fail("player-view witness has no pixel data")
        return
    var min_byte := 255
    var max_byte := 0
    for value: int in bytes:
        min_byte = mini(min_byte, value)
        max_byte = maxi(max_byte, value)
    if max_byte - min_byte < 8:
        _fail("player-view witness is effectively flat/blank")
        return
    var image_sha := _image_sha256(image)
    if image.save_png(WITNESS_PATH) != OK:
        _fail("failed to save exact player-view witness")
        return

    print("BOURSE_AUTOMATIC_ROAD_PLAYER_WITNESS_GREEN: source=OpenStreetMap_contributors_via_Overpass_API license=ODbL-1.0 anchor=(%.2f,%.2f) osm_id=%d road_name=%s road_class=%s anchor_distance_m=%.4f runner_up_osm_id=%d runner_up_distance_m=%.4f support_kind=%s support_path=%s collision_layer=%d ground_y=%.4f player_clearance_match=true frame=1280x720 frame_pixel_sha256=%s dynamic_state_frozen=true human_full_frame_review_required=true destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [
        float(source_road["anchor_x"]), float(source_road["anchor_z"]), osm_id,
        str(source_road["name"]), str(source_road["class"]), float(source_road["distance_m"]),
        int(source_road["runner_up_osm_id"]), float(source_road["runner_up_distance_m"]),
        str(support.get("kind", "")), str(support.get("path", "")), int(support.get("layer", 0)),
        observed_ground_y, image_sha,
    ])
    quit(0)
