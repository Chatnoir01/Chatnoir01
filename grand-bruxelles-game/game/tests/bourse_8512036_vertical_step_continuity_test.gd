extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const PHYSICS_HZ := 60
const STEP_COUNT := 180
const NUMERIC_EPSILON_M := 1e-6
const OWNER_META := "grand_bruxelles_owner"
const OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_IDS_META := "road_support_osm_ids"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_vertical_step_continuity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_VERTICAL_STEP_FAIL: %s" % message)
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
    if not up.is_finite() or up.length_squared() <= 0.0:
        return false
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
    var sprint_speed := float(player.get("sprint_speed"))
    var gravity := float(player.get("gravity"))
    var safe_margin := player.safe_margin
    var floor_snap := player.floor_snap_length
    var floor_max_angle := player.floor_max_angle
    var max_slides := player.max_slides
    if not is_finite(sprint_speed) or sprint_speed <= 0.0:
        _fail("invalid authoritative sprint speed")
        return
    if not is_finite(gravity) or gravity <= 0.0:
        _fail("invalid authoritative gravity")
        return
    if not is_finite(safe_margin) or safe_margin < 0.0:
        _fail("invalid authoritative safe margin")
        return
    if not is_finite(floor_snap) or floor_snap < 0.0:
        _fail("invalid authoritative floor snap")
        return
    if not is_finite(floor_max_angle) or floor_max_angle <= 0.0 or floor_max_angle >= PI / 2.0:
        _fail("invalid authoritative floor max angle")
        return
    if max_slides < 1:
        _fail("invalid authoritative max slides")
        return

    var resolver: Node = RESOLVER_SCRIPT.new()
    scene.add_child(resolver)
    if not resolver.call("apply_to_player", player, ROAD_ID):
        _fail("resolver rejected road-8512036")
        return
    for _frame: int in range(12):
        await process_frame
        await physics_frame

    if int(player.get_meta("automatic_road_direct_osm_id", 0)) != ROAD_ID:
        _fail("requested OSM identity was not preserved")
        return
    if str(player.get_meta("automatic_road_direct_lookup_mode", "")) != "deterministic_runtime_index":
        _fail("deterministic runtime-index lookup missing")
        return

    var spawn_raw: Variant = player.get_meta("automatic_road_direct_spawn_xz", null)
    var target_raw: Variant = player.get_meta("automatic_road_direct_target_xz", null)
    if not spawn_raw is Vector2 or not target_raw is Vector2:
        _fail("spawn/target metadata missing")
        return
    var spawn_xz := spawn_raw as Vector2
    var target_xz := target_raw as Vector2
    var delta := target_xz - spawn_xz
    var path_length := delta.length()
    if not is_finite(path_length) or path_length <= 0.0:
        _fail("invalid source-backed path length")
        return
    var forward := delta / path_length

    var dt := 1.0 / float(PHYSICS_HZ)
    var horizontal_step := sprint_speed * dt
    var recovery_budget := safe_margin * float(max_slides)
    var max_vertical_step := horizontal_step * tan(floor_max_angle) + floor_snap + recovery_budget
    if not is_finite(max_vertical_step) or max_vertical_step <= 0.0:
        _fail("invalid derived vertical-step bound")
        return

    player.set_physics_process(false)
    player.velocity = Vector3.ZERO
    var previous_y := player.global_position.y
    var max_observed_vertical_step := 0.0
    var vertical_checked_step_count := 0
    var vertical_step_violation_count := 0
    var first_vertical_step_violation_step := 0
    var grounded_step_count := 0
    var grounded_failure_count := 0
    var canonical_support_step_count := 0
    var canonical_support_failure_count := 0

    for step_index: int in range(STEP_COUNT):
        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var progress := (current_xz - spawn_xz).dot(forward)
        var horizontal_speed := sprint_speed if progress < path_length else 0.0
        var vertical_velocity := player.velocity.y
        if player.is_on_floor() and vertical_velocity < 0.0:
            vertical_velocity = -0.05
        elif not player.is_on_floor():
            vertical_velocity -= gravity * dt
        player.velocity = Vector3(forward.x * horizontal_speed, vertical_velocity, forward.y * horizontal_speed)
        player.move_and_slide()

        var vertical_step := absf(player.global_position.y - previous_y)
        max_observed_vertical_step = maxf(max_observed_vertical_step, vertical_step)
        vertical_checked_step_count += 1
        if vertical_step > max_vertical_step + NUMERIC_EPSILON_M:
            vertical_step_violation_count += 1
            if first_vertical_step_violation_step == 0:
                first_vertical_step_violation_step = step_index + 1
        if player.is_on_floor():
            grounded_step_count += 1
        else:
            grounded_failure_count += 1
        if _canonical_floor_support(player):
            canonical_support_step_count += 1
        else:
            canonical_support_failure_count += 1
        previous_y = player.global_position.y
        await physics_frame

    var continuous_vertical_step_bound := (
        vertical_checked_step_count == STEP_COUNT
        and vertical_step_violation_count == 0
        and first_vertical_step_violation_step == 0
        and max_observed_vertical_step <= max_vertical_step + NUMERIC_EPSILON_M
    )
    var continuous_grounded_support := grounded_step_count == STEP_COUNT and grounded_failure_count == 0
    var continuous_canonical_road_support := canonical_support_step_count == STEP_COUNT and canonical_support_failure_count == 0
    var vertical_step_green := continuous_vertical_step_bound and continuous_grounded_support and continuous_canonical_road_support

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-vertical-step-continuity-v1",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "physics_hz": PHYSICS_HZ,
        "step_count": STEP_COUNT,
        "authoritative_sprint_speed_mps": sprint_speed,
        "authoritative_gravity_mps2": gravity,
        "authoritative_floor_snap_length_m": floor_snap,
        "authoritative_safe_margin_m": safe_margin,
        "authoritative_max_slides": max_slides,
        "authoritative_floor_max_angle_rad": floor_max_angle,
        "authoritative_horizontal_step_m": horizontal_step,
        "authoritative_recovery_budget_m": recovery_budget,
        "vertical_step_bound_derivation": "horizontal_step_times_tan_floor_max_angle_plus_floor_snap_plus_safe_margin_times_max_slides",
        "max_vertical_step_m": max_vertical_step,
        "max_observed_vertical_step_m": max_observed_vertical_step,
        "vertical_checked_step_count": vertical_checked_step_count,
        "vertical_step_violation_count": vertical_step_violation_count,
        "first_vertical_step_violation_step": first_vertical_step_violation_step,
        "grounded_step_count": grounded_step_count,
        "grounded_failure_count": grounded_failure_count,
        "canonical_support_step_count": canonical_support_step_count,
        "canonical_support_failure_count": canonical_support_failure_count,
        "support_mode": "characterbody_capsule_test_motion",
        "canonical_owner_id": OWNER_ID,
        "continuous_vertical_step_bound": continuous_vertical_step_bound,
        "continuous_grounded_support": continuous_grounded_support,
        "continuous_canonical_road_support": continuous_canonical_road_support,
        "actual_character_body_move_and_slide": true,
        "vertical_step_green": vertical_step_green,
        "source_geometry_changed": false,
        "collision_geometry_changed": false,
        "camera_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write_receipt(receipt):
        _fail("unable to persist vertical-step receipt")
        return
    if not vertical_step_green:
        _fail("three-second traversal violated vertical-step, grounding, or canonical road-support continuity")
        return

    print("BOURSE_8512036_VERTICAL_STEP_GREEN: checked=%d vertical_violations=%d grounded_failures=%d canonical_failures=%d max_vertical_step_m=%.6f observed_max_m=%.6f" % [vertical_checked_step_count, vertical_step_violation_count, grounded_failure_count, canonical_support_failure_count, max_vertical_step, max_observed_vertical_step])
    quit(0)
