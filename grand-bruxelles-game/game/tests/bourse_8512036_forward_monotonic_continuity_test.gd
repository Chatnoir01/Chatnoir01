extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const PHYSICS_HZ := 60
const MOVEMENT_STEP_LIMIT := 180
const POST_TARGET_STEP_COUNT := PHYSICS_HZ
const NUMERIC_PROGRESS_EPSILON_M := 1e-6
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_forward_monotonic_continuity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_FORWARD_MONOTONIC_FAIL: %s" % message)
    quit(1)

func _write_receipt(data: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open(RECEIPT_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(data, "  ") + "\n")
    file.close()
    return true

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

    var gravity := float(player.get("gravity"))
    var sprint_speed := float(player.get("sprint_speed"))
    var safe_margin := float(player.safe_margin)
    var max_slides := int(player.max_slides)
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
    var dt := 1.0 / float(PHYSICS_HZ)
    var post_target_duration := float(POST_TARGET_STEP_COUNT) / float(PHYSICS_HZ)
    var recovery_budget := safe_margin * float(max_slides)
    var minimum_expected_post_target_progress := maxf(
        0.0,
        sprint_speed * post_target_duration - recovery_budget * float(POST_TARGET_STEP_COUNT)
    )

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
        _fail("player never crossed the source-backed target plane within movement budget")
        return

    var initial_post_target_xz := Vector2(player.global_position.x, player.global_position.z)
    var initial_post_target_progress := (initial_post_target_xz - spawn_xz).dot(forward)
    var previous_progress := initial_post_target_progress
    var post_target_frames := 0
    var reverse_progress_frame_count := 0
    var first_reverse_progress_step := 0
    var max_reverse_progress := 0.0
    var advancing_frame_count := 0
    var non_advancing_frame_count := 0
    var first_non_advancing_step := 0
    var minimum_advancing_delta := INF
    var positive_post_slide_forward_velocity_frames := 0
    var non_positive_post_slide_forward_velocity_frames := 0
    var first_non_positive_post_slide_velocity_step := 0
    var minimum_post_slide_forward_velocity := INF

    # The command remains the authoritative sprint for a full second. Position
    # monotonicity and merely-positive retained velocity are not enough by
    # themselves: an almost-stalled body could advance by microscopic amounts on
    # all 60 frames and still pass. Reuse the already-established CharacterBody
    # recovery budget (safe_margin * max_slides) to derive a fail-closed minimum
    # one-second net progress without inventing a Bourse-specific threshold.
    for post_index: int in range(POST_TARGET_STEP_COUNT):
        _advance_sprint_frame(player, forward, sprint_speed, gravity, dt)
        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var progress := (current_xz - spawn_xz).dot(forward)
        var progress_delta := progress - previous_progress
        if progress_delta < -NUMERIC_PROGRESS_EPSILON_M:
            reverse_progress_frame_count += 1
            max_reverse_progress = maxf(max_reverse_progress, -progress_delta)
            if first_reverse_progress_step == 0:
                first_reverse_progress_step = post_index + 1
        if progress_delta > NUMERIC_PROGRESS_EPSILON_M:
            advancing_frame_count += 1
            minimum_advancing_delta = minf(minimum_advancing_delta, progress_delta)
        else:
            non_advancing_frame_count += 1
            if first_non_advancing_step == 0:
                first_non_advancing_step = post_index + 1

        var post_slide_velocity_xz := Vector2(player.velocity.x, player.velocity.z)
        var post_slide_forward_velocity := post_slide_velocity_xz.dot(forward)
        if is_finite(post_slide_forward_velocity) and post_slide_forward_velocity > 0.0:
            positive_post_slide_forward_velocity_frames += 1
            minimum_post_slide_forward_velocity = minf(minimum_post_slide_forward_velocity, post_slide_forward_velocity)
        else:
            non_positive_post_slide_forward_velocity_frames += 1
            if first_non_positive_post_slide_velocity_step == 0:
                first_non_positive_post_slide_velocity_step = post_index + 1

        post_target_frames += 1
        previous_progress = progress
        await physics_frame

    var final_post_target_progress := previous_progress
    var post_target_net_progress := final_post_target_progress - initial_post_target_progress
    var positive_net_forward_progress := post_target_net_progress > 0.0
    var meaningful_sprint_progress := post_target_net_progress + NUMERIC_PROGRESS_EPSILON_M >= minimum_expected_post_target_progress
    if advancing_frame_count == 0:
        minimum_advancing_delta = 0.0
    if positive_post_slide_forward_velocity_frames == 0:
        minimum_post_slide_forward_velocity = 0.0

    var continuous_forward_progress := (
        post_target_frames == POST_TARGET_STEP_COUNT
        and advancing_frame_count == POST_TARGET_STEP_COUNT
        and non_advancing_frame_count == 0
        and first_non_advancing_step == 0
        and minimum_advancing_delta > NUMERIC_PROGRESS_EPSILON_M
    )
    var continuous_post_slide_forward_velocity := (
        positive_post_slide_forward_velocity_frames == POST_TARGET_STEP_COUNT
        and non_positive_post_slide_forward_velocity_frames == 0
        and first_non_positive_post_slide_velocity_step == 0
        and minimum_post_slide_forward_velocity > 0.0
    )
    var monotonic_forward_progress := (
        continuous_forward_progress
        and continuous_post_slide_forward_velocity
        and reverse_progress_frame_count == 0
        and first_reverse_progress_step == 0
        and max_reverse_progress == 0.0
        and final_post_target_progress >= initial_post_target_progress - NUMERIC_PROGRESS_EPSILON_M
        and positive_net_forward_progress
        and meaningful_sprint_progress
    )

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-forward-monotonic-v5",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "physics_hz": PHYSICS_HZ,
        "movement_step_limit": MOVEMENT_STEP_LIMIT,
        "post_target_step_count": POST_TARGET_STEP_COUNT,
        "post_target_duration_seconds": post_target_duration,
        "numeric_progress_epsilon_m": NUMERIC_PROGRESS_EPSILON_M,
        "input_mode": "continuous_authoritative_sprint_through_target_and_post_target_phase",
        "first_target_plane_step": first_target_step,
        "source_path_length_m": source_length,
        "initial_post_target_progress_m": initial_post_target_progress,
        "final_post_target_progress_m": final_post_target_progress,
        "post_target_net_progress_m": post_target_net_progress,
        "authoritative_sprint_speed_mps": sprint_speed,
        "authoritative_safe_margin_m": safe_margin,
        "authoritative_max_slides": max_slides,
        "recovery_budget_derivation": "authoritative_safe_margin_times_max_slides",
        "recovery_budget_m": recovery_budget,
        "minimum_expected_progress_derivation": "sprint_speed_times_duration_minus_per_frame_recovery_budget",
        "minimum_expected_post_target_progress_m": minimum_expected_post_target_progress,
        "meaningful_sprint_progress": meaningful_sprint_progress,
        "positive_net_forward_progress": positive_net_forward_progress,
        "advancing_frame_count": advancing_frame_count,
        "non_advancing_frame_count": non_advancing_frame_count,
        "first_non_advancing_step": first_non_advancing_step,
        "minimum_advancing_delta_m": minimum_advancing_delta,
        "continuous_forward_progress": continuous_forward_progress,
        "positive_post_slide_forward_velocity_frames": positive_post_slide_forward_velocity_frames,
        "non_positive_post_slide_forward_velocity_frames": non_positive_post_slide_forward_velocity_frames,
        "first_non_positive_post_slide_velocity_step": first_non_positive_post_slide_velocity_step,
        "minimum_post_slide_forward_velocity_mps": minimum_post_slide_forward_velocity,
        "continuous_post_slide_forward_velocity": continuous_post_slide_forward_velocity,
        "reverse_progress_frame_count": reverse_progress_frame_count,
        "first_reverse_progress_step": first_reverse_progress_step,
        "max_reverse_progress_m": max_reverse_progress,
        "monotonic_forward_progress": monotonic_forward_progress,
        "post_target_frames": post_target_frames,
        "actual_character_body_move_and_slide": true,
        "forward_monotonic_green": monotonic_forward_progress,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false
    }

    if not _write_receipt(receipt):
        _fail("unable to persist forward-monotonic receipt")
        return
    if not monotonic_forward_progress:
        _fail("post-target sprint lost displacement, retained velocity, or meaningful authoritative-speed progress continuity")
        return

    print("BOURSE_8512036_FORWARD_MONOTONIC_GREEN: first_target_step=%d post_target_frames=%d advancing_frames=%d positive_velocity_frames=%d reverse_frames=%d net_progress_m=%.6f minimum_expected_m=%.6f min_post_slide_forward_velocity_mps=%.6f" % [first_target_step, post_target_frames, advancing_frame_count, positive_post_slide_forward_velocity_frames, reverse_progress_frame_count, post_target_net_progress, minimum_expected_post_target_progress, minimum_post_slide_forward_velocity])
    quit(0)
