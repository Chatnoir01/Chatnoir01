extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const PHYSICS_HZ := 60
const STEP_COUNT := 180
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_target_proximity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_TARGET_PROXIMITY_FAIL: %s" % message)
    quit(1)

func _write_receipt(receipt: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var f := FileAccess.open(RECEIPT_PATH, FileAccess.WRITE)
    if f == null:
        return false
    f.store_string(JSON.stringify(receipt, "  ") + "\n")
    f.close()
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

func _support_from_collider(collider: Object) -> Dictionary:
    var result := {
        "hit": false,
        "canonical_owner": false,
        "requested_osm_id_owned": false,
        "collider_owner_id": "",
        "collider_road_support_osm_ids": [],
    }
    if collider == null or not collider is Node:
        return result
    var collider_node := collider as Node
    var owner_id := str(collider_node.get_meta(ROAD_SUPPORT_OWNER_META, ""))
    var owned_road_ids := _exact_owned_road_ids(collider_node)
    result["hit"] = true
    result["collider_owner_id"] = owner_id
    result["collider_road_support_osm_ids"] = owned_road_ids
    result["canonical_owner"] = owner_id == ROAD_SUPPORT_OWNER_ID
    result["requested_osm_id_owned"] = owned_road_ids.has(ROAD_ID)
    return result

func _floor_normal_valid(player: CharacterBody3D, normal: Vector3) -> bool:
    if not normal.is_finite() or normal.length_squared() <= 0.0:
        return false
    var up := player.up_direction.normalized()
    return normal.normalized().dot(up) + 1e-6 >= cos(player.floor_max_angle)

func _capsule_floor_support(player: CharacterBody3D) -> Dictionary:
    var fallback := _support_from_collider(null)
    if not player.is_on_floor():
        return fallback
    var up := player.up_direction.normalized()
    var probe_distance := player.floor_snap_length
    var probe_source := "floor_snap_length"
    if not is_finite(probe_distance) or probe_distance <= 0.0:
        probe_distance = player.safe_margin
        probe_source = "safe_margin"
    if not is_finite(probe_distance) or probe_distance <= 0.0:
        return fallback
    var collision := player.move_and_collide(-up * probe_distance, true, player.safe_margin, true, 8)
    if collision == null:
        return fallback
    for index: int in range(collision.get_collision_count()):
        var normal := collision.get_normal(index)
        if not _floor_normal_valid(player, normal):
            continue
        var support := _support_from_collider(collision.get_collider(index))
        support["support_mode"] = "characterbody_capsule_test_motion"
        support["probe_distance_m"] = probe_distance
        support["probe_distance_source"] = probe_source
        if bool(support["canonical_owner"]) and bool(support["requested_osm_id_owned"]):
            return support
        if not bool(fallback["hit"]):
            fallback = support
    return fallback

func _run() -> void:
    var scene := MAIN_SCENE.instantiate()
    root.add_child(scene)
    for _i: int in range(48):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("authoritative player unavailable")
        return
    var collision_shape := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collision_shape == null or not collision_shape.shape is CapsuleShape3D:
        _fail("authoritative player capsule unavailable")
        return
    var capsule := collision_shape.shape as CapsuleShape3D
    var capsule_radius := float(capsule.radius)
    var gravity := float(player.get("gravity"))
    var sprint_speed := float(player.get("sprint_speed"))
    if not is_finite(capsule_radius) or capsule_radius <= 0.0 or not is_finite(gravity) or gravity <= 0.0 or not is_finite(sprint_speed) or sprint_speed <= 0.0:
        _fail("authoritative player parameters invalid")
        return

    var resolver := RESOLVER_SCRIPT.new()
    scene.add_child(resolver)
    if not resolver.call("apply_to_player", player, ROAD_ID):
        _fail("shared resolver rejected road-8512036")
        return
    for _i: int in range(12):
        await process_frame
        await physics_frame

    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != ROAD_ID:
        _fail("requested OSM identity drifted")
        return
    if str(player.get_meta("automatic_road_direct_lookup_mode", "")) != "deterministic_runtime_index":
        _fail("deterministic runtime-index lookup missing")
        return

    var spawn_raw: Variant = player.get_meta("automatic_road_direct_spawn_xz", null)
    var target_raw: Variant = player.get_meta("automatic_road_direct_target_xz", null)
    if not spawn_raw is Vector2 or not target_raw is Vector2:
        _fail("source-backed spawn/target metadata missing")
        return
    var spawn_xz := spawn_raw as Vector2
    var target_xz := target_raw as Vector2
    var source_vector := target_xz - spawn_xz
    var source_length := source_vector.length()
    if not is_finite(source_length) or source_length <= 0.0:
        _fail("source-backed target vector invalid")
        return
    var forward := source_vector / source_length
    var dt := 1.0 / float(PHYSICS_HZ)

    player.set_physics_process(false)
    player.velocity = Vector3.ZERO
    var min_target_distance := INF
    var target_plane_crossed := false
    var first_target_plane_step := 0
    var first_target_plane_distance := INF
    var first_target_plane_lateral := INF
    var first_target_plane_on_floor := false
    var target_support: Dictionary = _support_from_collider(null)
    var floor_frames := 0

    for step_index: int in range(STEP_COUNT):
        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var progress := (current_xz - spawn_xz).dot(forward)
        var horizontal_speed := sprint_speed if progress < source_length else 0.0
        var vertical_velocity := player.velocity.y
        if player.is_on_floor() and vertical_velocity < 0.0:
            vertical_velocity = -0.05
        elif not player.is_on_floor():
            vertical_velocity -= gravity * dt
        player.velocity = Vector3(forward.x * horizontal_speed, vertical_velocity, forward.y * horizontal_speed)
        player.move_and_slide()

        current_xz = Vector2(player.global_position.x, player.global_position.z)
        progress = (current_xz - spawn_xz).dot(forward)
        var lateral := ((current_xz - spawn_xz) - forward * progress).length()
        var distance_to_target := current_xz.distance_to(target_xz)
        min_target_distance = minf(min_target_distance, distance_to_target)
        var on_floor_now := player.is_on_floor()
        if not target_plane_crossed and progress >= source_length:
            target_plane_crossed = true
            first_target_plane_step = step_index + 1
            first_target_plane_distance = distance_to_target
            first_target_plane_lateral = lateral
            first_target_plane_on_floor = on_floor_now
            target_support = _capsule_floor_support(player)
        if on_floor_now:
            floor_frames += 1
        await physics_frame

    var target_contact := target_plane_crossed and first_target_plane_distance <= capsule_radius + 1e-6
    var grounded_target_contact := target_contact and first_target_plane_on_floor
    var canonical_target_support := bool(target_support.get("hit", false)) and bool(target_support.get("canonical_owner", false)) and bool(target_support.get("requested_osm_id_owned", false))
    var grounded_canonical_target_contact := grounded_target_contact and canonical_target_support
    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-target-proximity-v3",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "physics_hz": PHYSICS_HZ,
        "step_count": STEP_COUNT,
        "source_path_length_m": source_length,
        "authoritative_capsule_radius_m": capsule_radius,
        "target_tolerance_derivation": "authoritative_player_capsule_radius",
        "target_plane_crossed": target_plane_crossed,
        "first_target_plane_step": first_target_plane_step,
        "first_target_plane_distance_m": first_target_plane_distance,
        "first_target_plane_lateral_deviation_m": first_target_plane_lateral,
        "first_target_plane_on_floor": first_target_plane_on_floor,
        "min_target_distance_m": min_target_distance,
        "source_target_capsule_contact": target_contact,
        "grounded_source_target_capsule_contact": grounded_target_contact,
        "target_support_mode": str(target_support.get("support_mode", "")),
        "target_support_hit": bool(target_support.get("hit", false)),
        "target_support_canonical_owner": bool(target_support.get("canonical_owner", false)),
        "target_support_requested_osm_id_owned": bool(target_support.get("requested_osm_id_owned", false)),
        "target_support_owner_id": str(target_support.get("collider_owner_id", "")),
        "target_support_road_support_osm_ids": target_support.get("collider_road_support_osm_ids", []),
        "target_support_probe_distance_m": float(target_support.get("probe_distance_m", 0.0)),
        "target_support_probe_distance_source": str(target_support.get("probe_distance_source", "")),
        "grounded_source_target_canonical_road_contact": grounded_canonical_target_contact,
        "floor_frames_measurement": floor_frames,
        "actual_character_body_move_and_slide": true,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write_receipt(receipt):
        _fail("unable to persist target proximity receipt")
        return
    if not target_plane_crossed:
        _fail("player never crossed the source-backed resolver target plane")
        return
    if not target_contact:
        _fail("longitudinal target crossing occurred outside the authoritative player capsule radius")
        return
    if not first_target_plane_on_floor:
        _fail("source-backed target crossing occurred while the authoritative player was airborne")
        return
    if not canonical_target_support:
        _fail("source-backed target crossing lacked canonical road-8512036 floor support")
        return

    print("BOURSE_8512036_TARGET_PROXIMITY_GREEN: target_step=%d target_distance_m=%.6f capsule_radius_m=%.6f min_target_distance_m=%.6f target_on_floor=true canonical_road_support=true floor_frames=%d" % [first_target_plane_step, first_target_plane_distance, capsule_radius, min_target_distance, floor_frames])
    quit(0)
