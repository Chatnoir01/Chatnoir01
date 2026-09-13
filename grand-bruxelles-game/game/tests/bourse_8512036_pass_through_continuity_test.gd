extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const PHYSICS_HZ := 60
const MOVEMENT_STEP_LIMIT := 180
const POST_TARGET_STEP_COUNT := PHYSICS_HZ
const OWNER_META := "grand_bruxelles_owner"
const OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_IDS_META := "road_support_osm_ids"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_pass_through_continuity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_PASS_THROUGH_FAIL: %s" % message)
    quit(1)

func _write_receipt(data: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open(RECEIPT_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(data, "  ") + "\n")
    file.close()
    return true

func _owned_ids(node: Node) -> Array[int]:
    var raw: Variant = node.get_meta(ROAD_IDS_META, null)
    if not raw is Array or raw.is_empty():
        return []
    var result: Array[int] = []
    var seen: Dictionary = {}
    for value: Variant in raw:
        if typeof(value) != TYPE_INT:
            return []
        var road_id := int(value)
        if road_id <= 0 or seen.has(road_id):
            return []
        seen[road_id] = true
        result.append(road_id)
    return result

func _canonical_floor_support(player: CharacterBody3D) -> bool:
    if not player.is_on_floor():
        return false
    var up := player.up_direction.normalized()
    var distance := player.floor_snap_length
    if not is_finite(distance) or distance <= 0.0:
        distance = player.safe_margin
    if not is_finite(distance) or distance <= 0.0:
        return false
    var collision := player.move_and_collide(-up * distance, true, player.safe_margin, true, 8)
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
        if str(node.get_meta(OWNER_META, "")) != OWNER_ID:
            continue
        if _owned_ids(node).has(ROAD_ID):
            return true
    return false

func _advance_sprint_frame(player: CharacterBody3D, forward: Vector2, sprint_speed: float, gravity: float, dt: float) -> void:
    var vertical_velocity := player.velocity.y
    if player.is_on_floor() and vertical_velocity < 0.0:
        vertical_velocity = -0.05
    elif not player.is_on_floor():
        vertical_velocity -= gravity * dt
    player.velocity = Vector3(forward.x * sprint_speed, vertical_velocity, forward.y * sprint_speed)
    player.move_and_slide()

func _run() -> void:
    var scene := MAIN_SCENE.instantiate()
    root.add_child(scene)
    for _i: int in range(48):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("authoritative Player missing")
        return
    var collision_shape := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if collision_shape == null or collision_shape.disabled or not collision_shape.shape is CapsuleShape3D:
        _fail("authoritative player capsule unavailable")
        return
    var capsule := collision_shape.shape as CapsuleShape3D
    var capsule_radius := float(capsule.radius)
    var gravity := float(player.get("gravity"))
    var sprint_speed := float(player.get("sprint_speed"))
    var safe_margin := float(player.safe_margin)
    var max_slides := int(player.max_slides)
    if not is_finite(capsule_radius) or capsule_radius <= 0.0:
        _fail("authoritative capsule radius invalid")
        return
    if not is_finite(gravity) or gravity <= 0.0 or not is_finite(sprint_speed) or sprint_speed <= 0.0:
        _fail("authoritative Player parameters invalid")
        return
    if not is_finite(safe_margin) or safe_margin < 0.0 or max_slides < 1:
        _fail("authoritative CharacterBody recovery parameters invalid")
        return

    var resolver := RESOLVER_SCRIPT.new()
    scene.add_child(resolver)
    if not resolver.call("apply_to_player", player, ROAD_ID):
        _fail("shared road resolver rejected road-8512036")
        return
    for _i: int in range(12):
        await process_frame
        await physics_frame

    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != ROAD_ID:
        _fail("resolved OSM identity drifted")
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
    var recovery_budget := safe_margin * float(max_slides)
    var max_forward_step := sprint_speed * dt + recovery_budget
    var max_backward_step := recovery_budget
    var max_horizontal_step := sprint_speed * dt + recovery_budget

    player.set_physics_process(false)
    player.velocity = Vector3.ZERO

    var first_target_step := 0
    for step_index: int in range(MOVEMENT_STEP_LIMIT):
        _advance_sprint_frame(player, forward, sprint_speed, gravity, dt)
        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var progress := (current_xz - spawn_xz).dot(forward)
        if progress >= source_length:
            first_target_step = step_index + 1
            await physics_frame
            break
        await physics_frame

    if first_target_step == 0:
        _fail("player never crossed the source-backed target plane within the movement budget")
        return

    var initial_post_target_xz := Vector2(player.global_position.x, player.global_position.z)
    var initial_post_target_progress := (initial_post_target_xz - spawn_xz).dot(forward)
    var previous_xz := initial_post_target_xz
    var previous_progress := initial_post_target_progress
    var post_target_frames := 0
    var post_target_grounded_frames := 0
    var post_target_canonical_support_frames := 0
    var post_target_within_capsule_frames := 0
    var first_post_target_failure_step := 0
    var first_progress_violation_step := 0
    var progress_violation_count := 0
    var first_horizontal_step_violation_step := 0
    var horizontal_step_violation_count := 0
    var max_post_target_lateral_error := 0.0
    var max_observed_forward_step := 0.0
    var max_observed_backward_step := 0.0
    var max_observed_horizontal_step := 0.0

    # Dedicated continuation phase: keep the same authoritative sprint input for a
    # full second after crossing. Bound both longitudinal progress and the complete
    # XZ displacement vector per physics frame. The latter closes a proof gap where
    # a large lateral snap could stay inside the absolute capsule corridor while its
    # longitudinal projection remained legal.
    for post_index: int in range(POST_TARGET_STEP_COUNT):
        _advance_sprint_frame(player, forward, sprint_speed, gravity, dt)
        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var horizontal_step := current_xz.distance_to(previous_xz)
        var offset := current_xz - spawn_xz
        var progress := offset.dot(forward)
        var progress_delta := progress - previous_progress
        var lateral_error := (offset - forward * progress).length()
        var grounded := player.is_on_floor()
        var canonical := _canonical_floor_support(player)
        var within_capsule := lateral_error <= capsule_radius + 1e-6
        var progress_ok := progress_delta <= max_forward_step + 1e-6 and progress_delta >= -max_backward_step - 1e-6
        var horizontal_step_ok := horizontal_step <= max_horizontal_step + 1e-6

        post_target_frames += 1
        max_post_target_lateral_error = maxf(max_post_target_lateral_error, lateral_error)
        max_observed_forward_step = maxf(max_observed_forward_step, progress_delta)
        max_observed_backward_step = maxf(max_observed_backward_step, -progress_delta)
        max_observed_horizontal_step = maxf(max_observed_horizontal_step, horizontal_step)
        if grounded:
            post_target_grounded_frames += 1
        if canonical:
            post_target_canonical_support_frames += 1
        if within_capsule:
            post_target_within_capsule_frames += 1
        if not progress_ok:
            progress_violation_count += 1
            if first_progress_violation_step == 0:
                first_progress_violation_step = post_index + 1
        if not horizontal_step_ok:
            horizontal_step_violation_count += 1
            if first_horizontal_step_violation_step == 0:
                first_horizontal_step_violation_step = post_index + 1
        if first_post_target_failure_step == 0 and not (grounded and canonical and within_capsule and progress_ok and horizontal_step_ok):
            first_post_target_failure_step = post_index + 1
        previous_xz = current_xz
        previous_progress = progress
        await physics_frame

    var final_post_target_progress := previous_progress
    var post_target_net_progress := final_post_target_progress - initial_post_target_progress
    var required_post_target_clearance := capsule_radius
    var body_cleared_target_plane := final_post_target_progress >= source_length + required_post_target_clearance - 1e-6
    var meaningful_post_target_progress := post_target_net_progress >= required_post_target_clearance - 1e-6
    var dedicated_post_target_phase_completed := post_target_frames == POST_TARGET_STEP_COUNT
    var continuous_post_target_lateral_bound := post_target_within_capsule_frames == POST_TARGET_STEP_COUNT and max_post_target_lateral_error <= capsule_radius + 1e-6
    var continuous_post_target_progress_bound := progress_violation_count == 0 and first_progress_violation_step == 0 and max_observed_forward_step <= max_forward_step + 1e-6 and max_observed_backward_step <= max_backward_step + 1e-6
    var continuous_post_target_horizontal_step_bound := horizontal_step_violation_count == 0 and first_horizontal_step_violation_step == 0 and max_observed_horizontal_step <= max_horizontal_step + 1e-6
    var pass_through_green := (
        first_target_step > 0
        and dedicated_post_target_phase_completed
        and post_target_grounded_frames == POST_TARGET_STEP_COUNT
        and post_target_canonical_support_frames == POST_TARGET_STEP_COUNT
        and continuous_post_target_lateral_bound
        and continuous_post_target_progress_bound
        and continuous_post_target_horizontal_step_bound
        and meaningful_post_target_progress
        and body_cleared_target_plane
        and first_post_target_failure_step == 0
    )

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-pass-through-v5",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "physics_hz": PHYSICS_HZ,
        "movement_step_limit": MOVEMENT_STEP_LIMIT,
        "post_target_step_count": POST_TARGET_STEP_COUNT,
        "post_target_duration_seconds": float(POST_TARGET_STEP_COUNT) / float(PHYSICS_HZ),
        "input_mode": "continuous_authoritative_sprint_through_target_and_post_target_phase",
        "first_target_plane_step": first_target_step,
        "source_path_length_m": source_length,
        "initial_post_target_progress_m": initial_post_target_progress,
        "final_post_target_progress_m": final_post_target_progress,
        "post_target_net_progress_m": post_target_net_progress,
        "required_post_target_clearance_derivation": "authoritative_player_capsule_radius",
        "required_post_target_clearance_m": required_post_target_clearance,
        "meaningful_post_target_progress": meaningful_post_target_progress,
        "body_cleared_target_plane": body_cleared_target_plane,
        "authoritative_capsule_radius_m": capsule_radius,
        "authoritative_sprint_speed_mps": sprint_speed,
        "authoritative_safe_margin_m": safe_margin,
        "authoritative_max_slides": max_slides,
        "recovery_budget_derivation": "authoritative_safe_margin_times_max_slides",
        "recovery_budget_m": recovery_budget,
        "max_forward_step_m": max_forward_step,
        "max_backward_step_m": max_backward_step,
        "max_horizontal_step_m": max_horizontal_step,
        "max_observed_forward_step_m": max_observed_forward_step,
        "max_observed_backward_step_m": max_observed_backward_step,
        "max_observed_horizontal_step_m": max_observed_horizontal_step,
        "progress_violation_count": progress_violation_count,
        "first_progress_violation_step": first_progress_violation_step,
        "horizontal_step_violation_count": horizontal_step_violation_count,
        "first_horizontal_step_violation_step": first_horizontal_step_violation_step,
        "continuous_post_target_progress_bound": continuous_post_target_progress_bound,
        "continuous_post_target_horizontal_step_bound": continuous_post_target_horizontal_step_bound,
        "lateral_tolerance_derivation": "authoritative_player_capsule_radius",
        "post_target_frames": post_target_frames,
        "post_target_grounded_frames": post_target_grounded_frames,
        "post_target_canonical_support_frames": post_target_canonical_support_frames,
        "post_target_within_capsule_frames": post_target_within_capsule_frames,
        "first_post_target_failure_step": first_post_target_failure_step,
        "max_post_target_lateral_error_m": max_post_target_lateral_error,
        "dedicated_post_target_phase_completed": dedicated_post_target_phase_completed,
        "continuous_post_target_lateral_bound": continuous_post_target_lateral_bound,
        "support_mode": "characterbody_capsule_test_motion",
        "canonical_owner_id": OWNER_ID,
        "requested_osm_id_owned_every_post_target_frame": post_target_canonical_support_frames == POST_TARGET_STEP_COUNT,
        "actual_character_body_move_and_slide": true,
        "pass_through_green": pass_through_green,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false
    }
    if not _write_receipt(receipt):
        _fail("unable to persist pass-through receipt")
        return
    if not pass_through_green:
        _fail("post-target sprint violated grounding, canonical road support, lateral capsule bound, frame progress/vector continuity, or capsule-radius clearance")
        return

    print("BOURSE_8512036_PASS_THROUGH_GREEN: first_target_step=%d post_target_frames=%d canonical_frames=%d progress_violations=%d horizontal_violations=%d net_progress_m=%.6f max_horizontal_step_m=%.6f observed_horizontal_m=%.6f" % [first_target_step, post_target_frames, post_target_canonical_support_frames, progress_violation_count, horizontal_step_violation_count, post_target_net_progress, max_horizontal_step, max_observed_horizontal_step])
    quit(0)
