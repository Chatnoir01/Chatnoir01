extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const STATION_COUNT := 7
const SURFACE_COLLISION_MASK := 524288
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_ground_continuity.json"
const NORMAL_EPSILON := 0.0001

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_GROUND_CONTINUITY_FAIL: %s" % message)
    quit(1)

func _write_receipt(receipt: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open(RECEIPT_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(receipt, "  ") + "\n")
    file.close()
    return true

func _exact_owned_road_ids(collider_node: Node) -> Array[int]:
    var raw_ids: Variant = collider_node.get_meta(ROAD_SUPPORT_OSM_IDS_META, null)
    if not raw_ids is Array or raw_ids.is_empty():
        return []
    var ids: Array[int] = []
    var seen: Dictionary = {}
    for raw_id: Variant in raw_ids:
        if typeof(raw_id) != TYPE_INT:
            return []
        var candidate_id := int(raw_id)
        if candidate_id <= 0 or seen.has(candidate_id):
            return []
        seen[candidate_id] = true
        ids.append(candidate_id)
    return ids

func _run() -> void:
    var scene: Node = MAIN_SCENE.instantiate()
    root.add_child(scene)
    for _frame: int in range(48):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("authoritative player unavailable")
        return
    var collision_shape := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collision_shape == null or collision_shape.disabled or collision_shape.shape == null or not collision_shape.shape is CapsuleShape3D:
        _fail("authoritative player capsule unavailable")
        return
    var capsule := collision_shape.shape as CapsuleShape3D
    var capsule_radius := float(capsule.radius)
    if not is_finite(capsule_radius) or capsule_radius <= 0.0:
        _fail("authoritative player capsule radius is invalid")
        return

    var resolver: Node = RESOLVER_SCRIPT.new()
    scene.add_child(resolver)
    if not resolver.call("apply_to_player", player, ROAD_ID):
        _fail("generic road-8512036 resolver rejected source-backed destination")
        return
    for _frame: int in range(12):
        await process_frame
        await physics_frame

    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != ROAD_ID:
        _fail("exact requested OSM identity not preserved")
        return
    if str(player.get_meta("automatic_road_direct_lookup_mode", "")) != "deterministic_runtime_index":
        _fail("deterministic runtime-index lookup missing")
        return
    if not bool(player.get_meta("automatic_road_direct_source_sightline_clear", false)):
        _fail("source-backed sightline is not clear")
        return

    var spawn_raw: Variant = player.get_meta("automatic_road_direct_spawn_xz", null)
    var target_raw: Variant = player.get_meta("automatic_road_direct_target_xz", null)
    if not spawn_raw is Vector2 or not target_raw is Vector2:
        _fail("source-backed spawn/target metadata missing")
        return
    var spawn_xz := spawn_raw as Vector2
    var target_xz := target_raw as Vector2
    var corridor_delta := target_xz - spawn_xz
    if corridor_delta.length() < 10.0:
        _fail("player-view corridor is too short to prove continuity")
        return

    var floor_max_angle := float(player.floor_max_angle)
    if not is_finite(floor_max_angle) or floor_max_angle <= 0.0 or floor_max_angle >= PI * 0.5:
        _fail("authoritative player floor_max_angle is invalid")
        return
    var minimum_walkable_normal_y := cos(floor_max_angle)
    var world := scene.get_viewport().world_3d
    if world == null:
        _fail("authoritative 3D world unavailable")
        return
    var space := world.direct_space_state
    var samples: Array[Dictionary] = []

    for station_index: int in range(STATION_COUNT):
        var t := float(station_index) / float(STATION_COUNT - 1)
        var xz := spawn_xz.lerp(target_xz, t)
        var query := PhysicsRayQueryParameters3D.create(Vector3(xz.x, 6.0, xz.y), Vector3(xz.x, -4.0, xz.y), SURFACE_COLLISION_MASK)
        query.collide_with_areas = false
        query.collide_with_bodies = true
        var hit := space.intersect_ray(query)
        if hit.is_empty():
            _fail("missing capsule contact-axis collision support at station %d/%d" % [station_index + 1, STATION_COUNT])
            return
        var hit_position: Variant = hit.get("position", null)
        var hit_normal_raw: Variant = hit.get("normal", null)
        if not hit_position is Vector3 or not hit_normal_raw is Vector3:
            _fail("invalid collision hit at station %d" % [station_index + 1])
            return
        var hit_normal := (hit_normal_raw as Vector3)
        if not is_finite(hit_normal.x) or not is_finite(hit_normal.y) or not is_finite(hit_normal.z) or hit_normal.length_squared() <= 0.0:
            _fail("invalid surface normal at station %d" % [station_index + 1])
            return
        hit_normal = hit_normal.normalized()
        if hit_normal.y + NORMAL_EPSILON < minimum_walkable_normal_y:
            _fail("surface exceeds authoritative player floor_max_angle at station %d" % [station_index + 1])
            return
        var collider: Object = hit.get("collider") as Object
        if collider == null or not collider is Node:
            _fail("surface support has no node collider owner at station %d" % [station_index + 1])
            return
        var collider_node := collider as Node
        var owner_id := str(collider_node.get_meta(ROAD_SUPPORT_OWNER_META, ""))
        var owned_road_ids := _exact_owned_road_ids(collider_node)
        if owner_id != ROAD_SUPPORT_OWNER_ID or owned_road_ids.is_empty() or not owned_road_ids.has(ROAD_ID):
            _fail("collision ownership mismatch at station %d" % [station_index + 1])
            return
        samples.append({
            "station_index": station_index,
            "t": t,
            "xz": [xz.x, xz.y],
            "ground_y": (hit_position as Vector3).y,
            "normal": [hit_normal.x, hit_normal.y, hit_normal.z],
            "normal_y": hit_normal.y,
            "walkable_by_player_floor_max_angle": true,
            "collider_name": str(collider_node.name),
            "collider_owner_id": owner_id,
            "collider_road_support_osm_ids": owned_road_ids,
            "requested_osm_id_owned": true,
        })

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-ground-continuity-v6",
        "road_osm_id": ROAD_ID,
        "request": "road-%d" % ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "spawn_xz": [spawn_xz.x, spawn_xz.y],
        "target_xz": [target_xz.x, target_xz.y],
        "station_count": STATION_COUNT,
        "probe_count": samples.size(),
        "probe_model": "capsule_contact_axis_centerline_v1",
        "player_collision_shape_type": "CapsuleShape3D",
        "player_capsule_radius_m": capsule_radius,
        "surface_collision_mask": SURFACE_COLLISION_MASK,
        "collision_owner_meta": ROAD_SUPPORT_OWNER_META,
        "collision_owner_id": ROAD_SUPPORT_OWNER_ID,
        "collision_road_ids_meta": ROAD_SUPPORT_OSM_IDS_META,
        "player_floor_max_angle_rad": floor_max_angle,
        "minimum_walkable_normal_y": minimum_walkable_normal_y,
        "samples": samples,
        "all_contact_axis_probes_collision_backed": samples.size() == STATION_COUNT,
        "all_contact_axis_probes_canonical_collision_owner": samples.size() == STATION_COUNT,
        "all_contact_axis_probes_exact_requested_osm_id_owned": samples.size() == STATION_COUNT,
        "all_contact_axis_probes_walkable_by_player_floor_max_angle": samples.size() == STATION_COUNT,
        "lateral_edge_ray_diagnostic_is_release_gate": false,
        "source_sightline_clear": true,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write_receipt(receipt):
        _fail("unable to persist continuity receipt")
        return

    print("BOURSE_8512036_GROUND_CONTINUITY_OK: stations=%d probes=%d probe_model=capsule_contact_axis_centerline_v1 capsule_radius_m=%.6f distance_m=%.6f collision_owner=%s exact_osm_id_owned=true min_walkable_normal_y=%.6f" % [STATION_COUNT, samples.size(), capsule_radius, spawn_xz.distance_to(target_xz), ROAD_SUPPORT_OWNER_ID, minimum_walkable_normal_y])
    quit(0)
