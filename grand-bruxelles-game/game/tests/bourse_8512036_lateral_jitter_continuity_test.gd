extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const PHYSICS_HZ := 60
const MOVEMENT_STEP_LIMIT := 180
const POST_TARGET_STEP_COUNT := PHYSICS_HZ
const NUMERIC_EPSILON_M := 1e-6
const OWNER_META := "grand_bruxelles_owner"
const OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_IDS_META := "road_support_osm_ids"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_lateral_jitter_continuity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_LATERAL_JITTER_FAIL: %s" % message)
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
        if normal.normalized().dot(up) + NUMERIC_EPSILON_M < cos(player.floor_max_angle):
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
        _fail("authoritative Player movement parameters invalid")
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
    var lateral_axis := Vector2(-forward.y, forward.x)
    var dt := 1.0 / float(PHYSICS_HZ)
    var recovery_budget := safe_margin * float(max_slides)
    var max_lateral_step := recovery_budget
    var lateral_envelope_tolerance := capsule_radius

    player.set_physics_process(false)
    player.velocity = Vector3.ZERO

    var first_target_step := 0
    var target_crossing_lateral_step := -1.0
    var target_crossing_lateral_offset := -1.0
    var target_crossing_grounded := false
    var target_crossing_canonical_support := false
    var previous_motion_xz := Vector2(player.global_position.x, player.global_position.z)
    for step_index: int in range(MOVEMENT_STEP_LIMIT):
        _advance_sprint_frame(player, forward, sprint_speed, gravity, dt)
        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var frame_delta := current_xz - previous_motion_xz
        var source_offset := current_xz - spawn_xz
        var progress := source_offset.dot(forward)
        if progress >= source_length:
            first_target_step = step_index + 1
            target_crossing_lateral_step = absf(frame_delta.dot(lateral_axis))
            target_crossing_lateral_offset = absf(source_offset.dot(lateral_axis))
            target_crossing_grounded = player.is_on_floor()
            target_crossing_canonical_support = _canonical_floor_support(player)
            await physics_frame
            break
        previous_motion_xz = current_xz
        await physics_frame

    if first_target_step == 0:
        _fail("player never crossed the source-backed target plane within movement budget")
        return
    if target_crossing_lateral_step < 0.0 or not is_finite(target_crossing_lateral_step):
        _fail("target-crossing lateral step was not measured")
        return
    if target_crossing_lateral_offset < 0.0 or not is_finite(target_crossing_lateral_offset):
        _fail("target-crossing lateral offset was not measured")
        return

    var previous_xz := Vector2(player.global_position.x, player.global_position.z)
    var post_target_frames := 0
    var lateral_step_violation_count := 0
    var first_lateral_step_violation_step := 0
    var target_crossing_lateral_step_within_bound := target_crossing_lateral_step <= max_lateral_step + NUMERIC_EPSILON_M
    var max_observed_lateral_step := target_crossing_lateral_step

    var lateral_envelope_checked_step_count := 1
    var lateral_envelope_within_bound_step_count := 0
    var lateral_envelope_violation_count := 0
    var first_lateral_envelope_violation_step := 0
    var target_crossing_lateral_offset_within_bound := target_crossing_lateral_offset <= lateral_envelope_tolerance + NUMERIC_EPSILON_M
    var max_observed_lateral_offset := target_crossing_lateral_offset

    var grounded_checked_step_count := 1
    var grounded_within_bound_step_count := 1 if target_crossing_grounded else 0
    var grounded_failure_count := 0 if target_crossing_grounded else 1
    var first_grounded_failure_step := 0 if target_crossing_grounded else first_target_step

    var canonical_support_checked_step_count := 1
    var canonical_support_within_bound_step_count := 1 if target_crossing_canonical_support else 0
    var canonical_support_failure_count := 0 if target_crossing_canonical_support else 1
    var first_canonical_support_failure_step := 0 if target_crossing_canonical_support else first_target_step

    if not target_crossing_lateral_step_within_bound:
        lateral_step_violation_count = 1
        first_lateral_step_violation_step = first_target_step
    if target_crossing_lateral_offset_within_bound:
        lateral_envelope_within_bound_step_count = 1
    else:
        lateral_envelope_violation_count = 1
        first_lateral_envelope_violation_step = first_target_step

    # Zero lateral command must satisfy three independent invariants over the exact
    # target-crossing frame plus a full second of continuation: bounded recovery
    # steps, bounded cumulative centerline drift, and real grounded contact with the
    # canonical collision owner for the requested OSM road on every checked frame.
    for post_index: int in range(POST_TARGET_STEP_COUNT):
        _advance_sprint_frame(player, forward, sprint_speed, gravity, dt)
        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var frame_delta := current_xz - previous_xz
        var lateral_step := absf(frame_delta.dot(lateral_axis))
        var lateral_offset := absf((current_xz - spawn_xz).dot(lateral_axis))
        var grounded := player.is_on_floor()
        var canonical_support := _canonical_floor_support(player)
        max_observed_lateral_step = maxf(max_observed_lateral_step, lateral_step)
        max_observed_lateral_offset = maxf(max_observed_lateral_offset, lateral_offset)
        if lateral_step > max_lateral_step + NUMERIC_EPSILON_M:
            lateral_step_violation_count += 1
            if first_lateral_step_violation_step == 0:
                first_lateral_step_violation_step = first_target_step + post_index + 1
        lateral_envelope_checked_step_count += 1
        if lateral_offset <= lateral_envelope_tolerance + NUMERIC_EPSILON_M:
            lateral_envelope_within_bound_step_count += 1
        else:
            lateral_envelope_violation_count += 1
            if first_lateral_envelope_violation_step == 0:
                first_lateral_envelope_violation_step = first_target_step + post_index + 1
        grounded_checked_step_count += 1
        if grounded:
            grounded_within_bound_step_count += 1
        else:
            grounded_failure_count += 1
            if first_grounded_failure_step == 0:
                first_grounded_failure_step = first_target_step + post_index + 1
        canonical_support_checked_step_count += 1
        if canonical_support:
            canonical_support_within_bound_step_count += 1
        else:
            canonical_support_failure_count += 1
            if first_canonical_support_failure_step == 0:
                first_canonical_support_failure_step = first_target_step + post_index + 1
        post_target_frames += 1
        previous_xz = current_xz
        await physics_frame

    var lateral_checked_step_count := post_target_frames + 1
    var continuous_lateral_jitter_bound := (
        target_crossing_lateral_step_within_bound
        and lateral_checked_step_count == POST_TARGET_STEP_COUNT + 1
        and post_target_frames == POST_TARGET_STEP_COUNT
        and lateral_step_violation_count == 0
        and first_lateral_step_violation_step == 0
        and max_observed_lateral_step <= max_lateral_step + NUMERIC_EPSILON_M
    )
    var continuous_lateral_envelope_bound := (
        target_crossing_lateral_offset_within_bound
        and lateral_envelope_checked_step_count == lateral_checked_step_count
        and lateral_envelope_within_bound_step_count == lateral_checked_step_count
        and lateral_envelope_violation_count == 0
        and first_lateral_envelope_violation_step == 0
        and max_observed_lateral_offset <= lateral_envelope_tolerance + NUMERIC_EPSILON_M
    )
    var continuous_grounded_support := (
        target_crossing_grounded
        and grounded_checked_step_count == lateral_checked_step_count
        and grounded_within_bound_step_count == lateral_checked_step_count
        and grounded_failure_count == 0
        and first_grounded_failure_step == 0
    )
    var continuous_canonical_road_support := (
        target_crossing_canonical_support
        and canonical_support_checked_step_count == lateral_checked_step_count
        and canonical_support_within_bound_step_count == lateral_checked_step_count
        and canonical_support_failure_count == 0
        and first_canonical_support_failure_step == 0
    )
    var lateral_jitter_green := (
        continuous_lateral_jitter_bound
        and continuous_lateral_envelope_bound
        and continuous_grounded_support
        and continuous_canonical_road_support
    )

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-lateral-jitter-v4",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "physics_hz": PHYSICS_HZ,
        "movement_step_limit": MOVEMENT_STEP_LIMIT,
        "post_target_step_count": POST_TARGET_STEP_COUNT,
        "lateral_checked_step_count": lateral_checked_step_count,
        "input_mode": "continuous_authoritative_sprint_zero_lateral_command",
        "first_target_plane_step": first_target_step,
        "authoritative_sprint_speed_mps": sprint_speed,
        "authoritative_safe_margin_m": safe_margin,
        "authoritative_max_slides": max_slides,
        "authoritative_capsule_radius_m": capsule_radius,
        "recovery_budget_derivation": "authoritative_safe_margin_times_max_slides",
        "recovery_budget_m": recovery_budget,
        "lateral_step_bound_derivation": "authoritative_safe_margin_times_max_slides",
        "max_lateral_step_m": max_lateral_step,
        "target_crossing_lateral_step_m": target_crossing_lateral_step,
        "target_crossing_lateral_step_within_bound": target_crossing_lateral_step_within_bound,
        "max_observed_lateral_step_m": max_observed_lateral_step,
        "lateral_step_violation_count": lateral_step_violation_count,
        "first_lateral_step_violation_step": first_lateral_step_violation_step,
        "continuous_lateral_jitter_bound": continuous_lateral_jitter_bound,
        "lateral_envelope_derivation": "authoritative_player_capsule_radius",
        "lateral_envelope_tolerance_m": lateral_envelope_tolerance,
        "lateral_envelope_checked_step_count": lateral_envelope_checked_step_count,
        "lateral_envelope_within_bound_step_count": lateral_envelope_within_bound_step_count,
        "target_crossing_lateral_offset_m": target_crossing_lateral_offset,
        "target_crossing_lateral_offset_within_bound": target_crossing_lateral_offset_within_bound,
        "max_observed_lateral_offset_m": max_observed_lateral_offset,
        "lateral_envelope_violation_count": lateral_envelope_violation_count,
        "first_lateral_envelope_violation_step": first_lateral_envelope_violation_step,
        "continuous_lateral_envelope_bound": continuous_lateral_envelope_bound,
        "support_mode": "characterbody_capsule_test_motion",
        "canonical_owner_id": OWNER_ID,
        "grounded_checked_step_count": grounded_checked_step_count,
        "grounded_within_bound_step_count": grounded_within_bound_step_count,
        "target_crossing_grounded": target_crossing_grounded,
        "grounded_failure_count": grounded_failure_count,
        "first_grounded_failure_step": first_grounded_failure_step,
        "continuous_grounded_support": continuous_grounded_support,
        "canonical_support_checked_step_count": canonical_support_checked_step_count,
        "canonical_support_within_bound_step_count": canonical_support_within_bound_step_count,
        "target_crossing_canonical_support": target_crossing_canonical_support,
        "canonical_support_failure_count": canonical_support_failure_count,
        "first_canonical_support_failure_step": first_canonical_support_failure_step,
        "continuous_canonical_road_support": continuous_canonical_road_support,
        "requested_osm_id_owned_every_checked_frame": continuous_canonical_road_support,
        "post_target_frames": post_target_frames,
        "actual_character_body_move_and_slide": true,
        "lateral_jitter_green": lateral_jitter_green,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false
    }

    if not _write_receipt(receipt):
        _fail("unable to persist lateral-jitter receipt")
        return
    if not lateral_jitter_green:
        _fail("target-crossing or post-target sprint violated lateral recovery, capsule envelope, grounding, or canonical road support")
        return

    print("BOURSE_8512036_LATERAL_JITTER_GREEN: first_target_step=%d checked_frames=%d lateral_violations=%d envelope_violations=%d grounded_failures=%d canonical_failures=%d crossing_lateral_m=%.6f max_lateral_step_m=%.6f observed_step_max_m=%.6f observed_offset_max_m=%.6f" % [first_target_step, lateral_checked_step_count, lateral_step_violation_count, lateral_envelope_violation_count, grounded_failure_count, canonical_support_failure_count, target_crossing_lateral_step, max_lateral_step, max_observed_lateral_step, max_observed_lateral_offset])
    quit(0)