extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ANNEESSENS_OSM_ID := 1382734012
const ROAD_SUPPORT_COLLISION_MASK := 1 << 19
const CANONICAL_GROUND_COLLISION_MASK := 1
const SAFE_GROUND_COLLISION_MASK := ROAD_SUPPORT_COLLISION_MASK | CANONICAL_GROUND_COLLISION_MASK
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"
const CANONICAL_GROUND_NAME := "Ground"
const MAX_RAY_HITS := 32
const GROUND_EPSILON_M := 0.01

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("ANNEESSENS_AUTOMATIC_ROAD_GROUND_SUPPORT_FAIL: %s" % message)
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

func _contains_osm_id(raw_ids: Variant, osm_id: int) -> bool:
    if not raw_ids is Array:
        return false
    for raw: Variant in raw_ids:
        if typeof(raw) != TYPE_INT and typeof(raw) != TYPE_FLOAT:
            return false
        var numeric := float(raw)
        if not is_finite(numeric) or floor(numeric) != numeric:
            return false
        if int(numeric) == osm_id:
            return true
    return false

func _authorized_support(collider: Object) -> Dictionary:
    if collider == null or not collider is Node:
        return {}
    var node := collider as Node
    if str(node.name) == CANONICAL_GROUND_NAME:
        if not node is CollisionObject3D:
            return {}
        var body := node as CollisionObject3D
        if (body.collision_layer & CANONICAL_GROUND_COLLISION_MASK) == 0:
            return {}
        return {
            "kind": "canonical_ground",
            "path": str(node.get_path()),
            "name": str(node.name),
            "layer": body.collision_layer,
        }
    if str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")) != ROAD_SUPPORT_OWNER_ID:
        return {}
    if not node is CollisionObject3D:
        return {}
    var support := node as CollisionObject3D
    if (support.collision_layer & ROAD_SUPPORT_COLLISION_MASK) == 0:
        return {}
    if not _contains_osm_id(node.get_meta(ROAD_SUPPORT_OSM_IDS_META, []), ANNEESSENS_OSM_ID):
        return {}
    return {
        "kind": "source_road_support",
        "path": str(node.get_path()),
        "name": str(node.name),
        "layer": support.collision_layer,
        "owner": str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")),
    }

func _support_below(player: CharacterBody3D) -> Dictionary:
    var world := player.get_world_3d()
    if world == null:
        return {}
    var xz := Vector2(player.global_position.x, player.global_position.z)
    var excluded: Array[RID] = []
    for _attempt: int in range(MAX_RAY_HITS):
        var query := PhysicsRayQueryParameters3D.create(
            Vector3(xz.x, player.global_position.y + 25.0, xz.y),
            Vector3(xz.x, -200.0, xz.y)
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
            var identity := _authorized_support(collider as Object)
            if not identity.is_empty():
                identity["y"] = (position as Vector3).y
                return identity
        var rid: Variant = hit.get("rid")
        if not rid is RID or not (rid as RID).is_valid():
            return {}
        excluded.append(rid as RID)
    return {}

func _run() -> void:
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
    if not resolver.apply_to_player(player, ANNEESSENS_OSM_ID):
        _fail("road-1382734012 did not resolve into a rendered collision-safe destination")
        return

    var expected_ground_y := float(player.get_meta("automatic_road_direct_ground_y", INF))
    if not is_finite(expected_ground_y):
        _fail("resolver did not record physics-backed ground height")
        return

    await physics_frame
    var support := _support_below(player)
    if support.is_empty():
        _fail("no independently verified authorized support collider below resolved spawn")
        return
    var observed_ground_y := float(support.get("y", INF))
    if not is_finite(observed_ground_y) or absf(observed_ground_y - expected_ground_y) > GROUND_EPSILON_M:
        _fail("independent support height disagrees with resolver ground_y: expected=%.4f observed=%.4f" % [expected_ground_y, observed_ground_y])
        return
    if absf(player.global_position.y - (observed_ground_y + 1.05)) > GROUND_EPSILON_M:
        _fail("player clearance is not tied to independently verified ground support")
        return

    print("ANNEESSENS_AUTOMATIC_ROAD_GROUND_SUPPORT_GREEN: osm_id=%d kind=%s collider_path=%s collider_name=%s collision_layer=%d ground_y=%.4f resolver_ground_match=true player_clearance_match=true destination_advertisable=false jouable_authorized=false" % [
        ANNEESSENS_OSM_ID,
        str(support.get("kind", "")),
        str(support.get("path", "")),
        str(support.get("name", "")),
        int(support.get("layer", 0)),
        observed_ground_y,
    ])
    quit(0)
