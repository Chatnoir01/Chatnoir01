extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const PHYSICS_HZ := 60
const MOVEMENT_STEP_LIMIT := 180
const HOLD_STEP_COUNT := PHYSICS_HZ
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_arrival_hold.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_ARRIVAL_HOLD_FAIL: %s" % message)
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

func _floor_support_is_requested_road(player: CharacterBody3D) -> bool:
    if not player.is_on_floor():
        return false
    var up := player.up_direction.normalized()
    var probe_distance := player.floor_snap_length
    if not is_finite(probe_distance) or probe_distance <= 0.0:
        probe_distance = player.safe_margin
    if not is_finite(probe_distance) or probe_distance <= 0.0:
        return false
    var collision := player.move_and_collide(-up * probe_distance, true, player.safe_margin, true, 8)
    if collision == null:
        return false
    for index: int in range(collision.get_collision_count()):
        var normal := collision.get_normal(index)
        if not normal.is_finite() or normal.length_squared() <= 0.0:
            continue
        if normal.normalized().dot(up) + 1e-6 < cos(player.floor_max_angle):
            continue
        var collider := collision.get_collider(index)
        if collider == null or not collider is Node:
            continue
        var node := collider as Node
        if str(node.get_meta(ROAD_SUPPORT_OWNER_META, "")) != ROAD_SUPPORT_OWNER_ID:
            continue
        if _exact_owned_road_ids(node).has(ROAD_ID):
            return true
    return false

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

    var target_plane_crossed := false
    var first_target_plane_step := 0

    for step_index: int in range(MOVEMENT_STEP_LIMIT):
        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var progress := (current_xz - spawn_xz).dot(forward)
        var vertical_velocity := player.velocity.y
        if player.is_on_floor() and vertical_velocity < 0.0:
            vertical_velocity = -0.05
        elif not player.is_on_floor():
            vertical_velocity -= gravity * dt
        player.velocity = Vector3(forward.x * sprint_speed, vertical_velocity, forward.y * sprint_speed)
        player.move_and_slide()

        current_xz = Vector2(player.global_position.x, player.global_position.z)
        progress = (current_xz - spawn_xz).dot(forward)
        if progress >= source_length:
            target_plane_crossed = true
            first_target_plane_step = step_index + 1
            await physics_frame
            break
        await physics_frame

    if not target_plane_crossed:
        _fail("player never crossed the source-backed resolver target plane within movement budget")
        return

    var post_target_frames := 0
    var post_target_grounded_frames := 0
    var post_target_canonical_support_frames := 0
    var post_target_within_capsule_frames := 0
    var max_post_target_distance := 0.0
    var first_post_target_failure_step := 0

    for hold_index: int in range(HOLD_STEP_COUNT):
        var vertical_velocity := player.velocity.y
        if player.is_on_floor() and vertical_velocity < 0.0:
            vertical_velocity = -0.05
        elif not player.is_on_floor():
            vertical_velocity -= gravity * dt
        player.velocity = Vector3(0.0, vertical_velocity, 0.0)
        player.move_and_slide()

        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var distance_to_target := current_xz.distance_to(target_xz)
        post_target_frames += 1
        max_post_target_distance = maxf(max_post_target_distance, distance_to_target)
        var grounded := player.is_on_floor()
        var within_capsule := distance_to_target <= capsule_radius + 1e-6
        var canonical_support := _floor_support_is_requested_road(player)
        if grounded:
            post_target_grounded_frames += 1
        if within_capsule:
            post_target_within_capsule_frames += 1
        if canonical_support:
            post_target_canonical_support_frames += 1
        if first_post_target_failure_step == 0 and not (grounded and within_capsule and canonical_support):
            first_post_target_failure_step = hold_index + 1
        await physics_frame

    var full_hold_duration_completed := post_target_frames == HOLD_STEP_COUNT
    var post_target_stable := (
        full_hold_duration_completed
        and post_target_grounded_frames == HOLD_STEP_COUNT
        and post_target_canonical_support_frames == HOLD_STEP_COUNT
        and post_target_within_capsule_frames == HOLD_STEP_COUNT
        and max_post_target_distance <= capsule_radius + 1e-6
        and first_post_target_failure_step == 0
    )

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-arrival-hold-v2",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "physics_hz": PHYSICS_HZ,
        "movement_step_limit": MOVEMENT_STEP_LIMIT,
        "hold_step_count": HOLD_STEP_COUNT,
        "hold_duration_seconds": float(HOLD_STEP_COUNT) / float(PHYSICS_HZ),
        "authoritative_capsule_radius_m": capsule_radius,
        "hold_tolerance_derivation": "authoritative_player_capsule_radius",
        "first_target_plane_step": first_target_plane_step,
        "post_target_frames": post_target_frames,
        "post_target_grounded_frames": post_target_grounded_frames,
        "post_target_canonical_support_frames": post_target_canonical_support_frames,
        "post_target_within_capsule_frames": post_target_within_capsule_frames,
        "max_post_target_distance_m": max_post_target_distance,
        "first_post_target_failure_step": first_post_target_failure_step,
        "full_hold_duration_completed": full_hold_duration_completed,
        "post_target_stable_on_requested_road": post_target_stable,
        "support_mode": "characterbody_capsule_test_motion",
        "canonical_owner_id": ROAD_SUPPORT_OWNER_ID,
        "requested_osm_id_owned_every_hold_frame": post_target_canonical_support_frames == HOLD_STEP_COUNT,
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
        _fail("unable to persist arrival-hold receipt")
        return
    if not post_target_stable:
        _fail("player did not remain grounded, within capsule reach, and on canonical road-8512036 support for the full one-second hold")
        return

    print("BOURSE_8512036_ARRIVAL_HOLD_GREEN: first_target_step=%d hold_frames=%d hold_seconds=%.3f max_target_distance_m=%.6f capsule_radius_m=%.6f canonical_hold_frames=%d" % [first_target_plane_step, post_target_frames, float(HOLD_STEP_COUNT) / float(PHYSICS_HZ), max_post_target_distance, capsule_radius, post_target_canonical_support_frames])
    quit(0)
