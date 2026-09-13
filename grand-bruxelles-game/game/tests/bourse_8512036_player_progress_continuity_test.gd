extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const SIMULATION_SECONDS := 3.0
const PHYSICS_HZ := 60
const STEP_COUNT := int(SIMULATION_SECONDS * PHYSICS_HZ)
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_player_progress_continuity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_PLAYER_PROGRESS_CONTINUITY_FAIL: %s" % message)
    quit(1)

func _write_receipt(receipt: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open(RECEIPT_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(receipt, "  ") + "\n")
    file.close()
    return true

func _run() -> void:
    var scene := MAIN_SCENE.instantiate()
    root.add_child(scene)
    for _frame: int in range(48):
        await process_frame
        await physics_frame

    var player := scene.get_node_or_null("Player") as CharacterBody3D
    if player == null:
        _fail("authoritative player unavailable")
        return
    var gravity := float(player.get("gravity"))
    var sprint_speed := float(player.get("sprint_speed"))
    var safe_margin := float(player.safe_margin)
    var max_slides := int(player.max_slides)
    if not is_finite(gravity) or gravity <= 0.0:
        _fail("authoritative gravity invalid")
        return
    if not is_finite(sprint_speed) or sprint_speed <= 0.0:
        _fail("authoritative sprint speed invalid")
        return
    if not is_finite(safe_margin) or safe_margin <= 0.0:
        _fail("authoritative safe margin invalid")
        return
    if max_slides <= 0:
        _fail("authoritative max_slides invalid")
        return

    var resolver := RESOLVER_SCRIPT.new()
    scene.add_child(resolver)
    if not resolver.call("apply_to_player", player, ROAD_ID):
        _fail("shared resolver rejected road-8512036")
        return
    for _frame: int in range(12):
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
    var path := target_xz - spawn_xz
    var path_length := path.length()
    if not is_finite(path_length) or path_length <= 0.0:
        _fail("source-backed path length invalid")
        return
    var forward := path / path_length
    var dt := 1.0 / float(PHYSICS_HZ)

    # Godot's grounded move_and_slide loop may perform up to max_slides collision
    # iterations in one physics tick. Each iteration invokes collision recovery with
    # CharacterBody.safe_margin before the remaining motion is slid. A teleport gate
    # must therefore include the engine-configured worst-case recovery budget rather
    # than pretending recovery can occur only once per tick.
    #
    # This remains fail-closed and runtime-derived: no corridor-specific tolerance is
    # introduced. A displacement beyond requested horizontal motion plus the maximum
    # recovery budget still fails immediately.
    var requested_step_m := sprint_speed * dt
    var recovery_budget_m := safe_margin * float(max_slides)
    var max_horizontal_step_allowed_m := requested_step_m + recovery_budget_m
    var max_forward_step_allowed_m := max_horizontal_step_allowed_m
    var max_backward_step_allowed_m := recovery_budget_m

    player.set_physics_process(false)
    player.velocity = Vector3.ZERO
    var previous_xz := Vector2(player.global_position.x, player.global_position.z)
    var previous_progress := (previous_xz - spawn_xz).dot(forward)
    var max_progress_m := previous_progress
    var target_reached := false
    var first_target_reach_step := 0
    var first_target_reach_time_s := 0.0
    var first_target_reach_progress_m := 0.0
    var max_horizontal_step_m := 0.0
    var max_forward_step_m := 0.0
    var max_backward_step_m := 0.0
    var horizontal_step_violations := 0
    var forward_step_violations := 0
    var backward_step_violations := 0
    var first_violation: Dictionary = {}
    var floor_frames := 0

    for step_index: int in range(STEP_COUNT):
        var horizontal_speed := sprint_speed if previous_progress < path_length else 0.0
        var vertical_velocity := player.velocity.y
        if player.is_on_floor() and vertical_velocity < 0.0:
            vertical_velocity = -0.05
        elif not player.is_on_floor():
            vertical_velocity -= gravity * dt
        player.velocity = Vector3(forward.x * horizontal_speed, vertical_velocity, forward.y * horizontal_speed)
        player.move_and_slide()

        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var horizontal_step_m := current_xz.distance_to(previous_xz)
        var current_progress := (current_xz - spawn_xz).dot(forward)
        var progress_step := current_progress - previous_progress
        max_progress_m = maxf(max_progress_m, current_progress)
        if not target_reached and current_progress >= path_length:
            target_reached = true
            first_target_reach_step = step_index + 1
            first_target_reach_time_s = float(step_index + 1) * dt
            first_target_reach_progress_m = current_progress
        max_horizontal_step_m = maxf(max_horizontal_step_m, horizontal_step_m)
        max_forward_step_m = maxf(max_forward_step_m, progress_step)
        max_backward_step_m = maxf(max_backward_step_m, -progress_step)
        var horizontal_violation := horizontal_step_m > max_horizontal_step_allowed_m + 1e-6
        var forward_violation := progress_step > max_forward_step_allowed_m + 1e-6
        var backward_violation := progress_step < -max_backward_step_allowed_m - 1e-6
        if horizontal_violation:
            horizontal_step_violations += 1
        if forward_violation:
            forward_step_violations += 1
        if backward_violation:
            backward_step_violations += 1
        if (horizontal_violation or forward_violation or backward_violation) and first_violation.is_empty():
            first_violation = {
                "step": step_index + 1,
                "time_s": float(step_index + 1) * dt,
                "previous_progress_m": previous_progress,
                "current_progress_m": current_progress,
                "progress_step_m": progress_step,
                "horizontal_step_m": horizontal_step_m,
                "horizontal_violation": horizontal_violation,
                "forward_violation": forward_violation,
                "backward_violation": backward_violation,
                "position": [player.global_position.x, player.global_position.y, player.global_position.z],
            }
        if player.is_on_floor():
            floor_frames += 1
        previous_xz = current_xz
        previous_progress = current_progress
        await physics_frame

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-player-progress-continuity-v4",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "simulation_seconds": SIMULATION_SECONDS,
        "physics_hz": PHYSICS_HZ,
        "step_count": STEP_COUNT,
        "source_path_length_m": path_length,
        "authoritative_sprint_speed_mps": sprint_speed,
        "authoritative_safe_margin_m": safe_margin,
        "authoritative_max_slides": max_slides,
        "requested_step_m": requested_step_m,
        "recovery_budget_m": recovery_budget_m,
        "max_horizontal_step_allowed_m": max_horizontal_step_allowed_m,
        "max_forward_step_allowed_m": max_forward_step_allowed_m,
        "max_backward_step_allowed_m": max_backward_step_allowed_m,
        "limit_derivation": "sprint_speed_times_dt_plus_safe_margin_times_max_slides",
        "max_horizontal_step_m": max_horizontal_step_m,
        "max_forward_step_m": max_forward_step_m,
        "max_backward_step_m": max_backward_step_m,
        "horizontal_step_violations": horizontal_step_violations,
        "forward_step_violations": forward_step_violations,
        "backward_step_violations": backward_step_violations,
        "first_violation": first_violation,
        "floor_frames_measurement": floor_frames,
        "max_progress_m": max_progress_m,
        "final_progress_m": previous_progress,
        "source_target_reached": target_reached,
        "first_target_reach_step": first_target_reach_step,
        "first_target_reach_time_s": first_target_reach_time_s,
        "first_target_reach_progress_m": first_target_reach_progress_m,
        "actual_character_body_move_and_slide": true,
        "engine_recovery_budget_used": true,
        "full_horizontal_step_bounded": horizontal_step_violations == 0,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write_receipt(receipt):
        _fail("unable to persist progress continuity receipt")
        return
    if horizontal_step_violations != 0:
        _fail("per-frame horizontal displacement exceeded authoritative motion plus engine recovery budget")
        return
    if forward_step_violations != 0:
        _fail("per-frame forward progress exceeded authoritative motion plus engine recovery budget")
        return
    if backward_step_violations != 0:
        _fail("per-frame backward correction exceeded authoritative engine recovery budget")
        return
    if not target_reached:
        _fail("player never reached the source-backed resolver target")
        return

    print("BOURSE_8512036_PLAYER_PROGRESS_CONTINUITY_GREEN: steps=%d path_length_m=%.6f target_reach_step=%d max_progress_m=%.6f max_horizontal_step_m=%.6f allowed_horizontal_m=%.6f max_forward_step_m=%.6f allowed_forward_m=%.6f max_backward_step_m=%.6f allowed_backward_m=%.6f max_slides=%d final_progress_m=%.6f" % [STEP_COUNT, path_length, first_target_reach_step, max_progress_m, max_horizontal_step_m, max_horizontal_step_allowed_m, max_forward_step_m, max_forward_step_allowed_m, max_backward_step_m, max_backward_step_allowed_m, max_slides, previous_progress])
    quit(0)
