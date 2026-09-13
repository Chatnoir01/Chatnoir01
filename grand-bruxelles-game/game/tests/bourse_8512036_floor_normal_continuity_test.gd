extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const PHYSICS_HZ := 60
const STEP_COUNT := 180
const NUMERIC_EPSILON_RAD := 1e-6
const NUMERIC_EPSILON_M := 1e-6
const OWNER_META := "grand_bruxelles_owner"
const OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_IDS_META := "road_support_osm_ids"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_floor_normal_continuity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_FLOOR_NORMAL_CONTINUITY_FAIL: %s" % message)
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

func _is_canonical_road_owner(collider: Object) -> bool:
    if collider == null or not collider is Node:
        return false
    var node := collider as Node
    return str(node.get_meta(OWNER_META, "")) == OWNER_ID and _owned_ids(node).has(ROAD_ID)

func _canonical_floor_support(player: CharacterBody3D, floor_snap_length: float, safe_margin: float) -> Variant:
    if not player.is_on_floor():
        return null
    var up := player.up_direction.normalized()
    if not up.is_finite() or up.length_squared() <= 0.0:
        return null
    var collision := player.move_and_collide(-up * floor_snap_length, true, safe_margin, true, 8)
    if collision == null:
        return null
    var travel := collision.get_travel()
    if not travel.is_finite():
        return null
    var gap_m := travel.length()
    if not is_finite(gap_m) or gap_m < 0.0 or gap_m > floor_snap_length + NUMERIC_EPSILON_M:
        return null
    for index: int in range(collision.get_collision_count()):
        var normal := collision.get_normal(index)
        if not normal.is_finite() or normal.length_squared() <= 0.0:
            continue
        var unit_normal := normal.normalized()
        if unit_normal.dot(up) + NUMERIC_EPSILON_RAD < cos(player.floor_max_angle):
            continue
        if _is_canonical_road_owner(collision.get_collider(index)):
            return {"normal": unit_normal, "gap_m": gap_m}
    return null

func _character_floor_normal(player: CharacterBody3D) -> Variant:
    if not player.is_on_floor():
        return null
    var normal := player.get_floor_normal()
    if not normal.is_finite() or normal.length_squared() <= 0.0:
        return null
    var unit_normal := normal.normalized()
    var up := player.up_direction.normalized()
    if not up.is_finite() or up.length_squared() <= 0.0:
        return null
    if unit_normal.dot(up) + NUMERIC_EPSILON_RAD < cos(player.floor_max_angle):
        return null
    return unit_normal

func _slide_floor_support_state(player: CharacterBody3D) -> Dictionary:
    var state := {
        "has_floor_contact": false,
        "has_canonical_floor_contact": false,
        "has_noncanonical_floor_contact": false,
    }
    var up := player.up_direction.normalized()
    if not up.is_finite() or up.length_squared() <= 0.0:
        return state
    var floor_dot_min := cos(player.floor_max_angle)
    for slide_index: int in range(player.get_slide_collision_count()):
        var slide := player.get_slide_collision(slide_index)
        if slide == null:
            continue
        for collision_index: int in range(slide.get_collision_count()):
            var normal := slide.get_normal(collision_index)
            if not normal.is_finite() or normal.length_squared() <= 0.0:
                continue
            var unit_normal := normal.normalized()
            if unit_normal.dot(up) + NUMERIC_EPSILON_RAD < floor_dot_min:
                continue
            state["has_floor_contact"] = true
            if _is_canonical_road_owner(slide.get_collider(collision_index)):
                state["has_canonical_floor_contact"] = true
            else:
                state["has_noncanonical_floor_contact"] = true
    return state

func _normal_delta(previous: Vector3, current: Vector3) -> float:
    return acos(clampf(previous.dot(current), -1.0, 1.0))

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
    var floor_max_angle := float(player.floor_max_angle)
    var floor_snap_length := float(player.floor_snap_length)
    var safe_margin := float(player.safe_margin)
    if not is_finite(sprint_speed) or sprint_speed <= 0.0:
        _fail("invalid authoritative sprint speed")
        return
    if not is_finite(gravity) or gravity <= 0.0:
        _fail("invalid authoritative gravity")
        return
    if not is_finite(floor_max_angle) or floor_max_angle <= 0.0 or floor_max_angle >= PI / 2.0:
        _fail("invalid authoritative floor max angle")
        return
    if not is_finite(floor_snap_length) or floor_snap_length <= 0.0:
        _fail("invalid authoritative floor snap length")
        return
    if not is_finite(safe_margin) or safe_margin <= 0.0:
        _fail("invalid authoritative safe margin")
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

    player.set_physics_process(false)
    player.velocity = Vector3.ZERO

    var previous_normal: Variant = null
    var previous_character_normal: Variant = null
    var support_frame_count := 0
    var missing_support_frame_count := 0
    var normal_transition_count := 0
    var normal_transition_violation_count := 0
    var first_normal_transition_violation_step := 0
    var max_observed_normal_delta_rad := 0.0
    var character_floor_normal_frame_count := 0
    var missing_character_floor_normal_frame_count := 0
    var character_floor_normal_transition_count := 0
    var character_floor_normal_transition_violation_count := 0
    var first_character_floor_normal_transition_violation_step := 0
    var max_observed_character_floor_normal_delta_rad := 0.0
    var max_observed_canonical_support_gap_m := 0.0
    var max_observed_no_slide_canonical_support_gap_m := 0.0
    var no_slide_support_gap_violation_count := 0
    var first_no_slide_support_gap_violation_step := 0
    var movement_command_frame_count := 0
    var stationary_hold_frame_count := 0
    var slide_floor_contact_frame_count := 0
    var missing_slide_floor_contact_frame_count := 0
    var canonical_slide_floor_contact_frame_count := 0
    var noncanonical_slide_floor_contact_frame_count := 0
    var no_slide_floor_contact_grounded_canonical_support_frame_count := 0
    var movement_slide_floor_contact_frame_count := 0
    var missing_movement_slide_floor_contact_frame_count := 0
    var canonical_movement_slide_floor_contact_frame_count := 0
    var noncanonical_movement_slide_floor_contact_frame_count := 0
    var movement_no_slide_floor_contact_grounded_canonical_support_frame_count := 0
    var stationary_canonical_support_frame_count := 0
    var missing_stationary_canonical_support_frame_count := 0

    for step_index: int in range(STEP_COUNT):
        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var progress := (current_xz - spawn_xz).dot(forward)
        var horizontal_speed := sprint_speed if progress < path_length else 0.0
        var commanded_motion := horizontal_speed > 0.0
        if commanded_motion:
            movement_command_frame_count += 1
        else:
            stationary_hold_frame_count += 1

        var vertical_velocity := player.velocity.y
        if player.is_on_floor() and vertical_velocity < 0.0:
            vertical_velocity = -0.05
        elif not player.is_on_floor():
            vertical_velocity -= gravity * dt
        player.velocity = Vector3(forward.x * horizontal_speed, vertical_velocity, forward.y * horizontal_speed)
        player.move_and_slide()

        var slide_state := _slide_floor_support_state(player)
        var has_slide_floor := bool(slide_state.get("has_floor_contact", false))
        var has_canonical_slide_floor := bool(slide_state.get("has_canonical_floor_contact", false))
        var has_noncanonical_slide_floor := bool(slide_state.get("has_noncanonical_floor_contact", false))
        if has_slide_floor:
            slide_floor_contact_frame_count += 1
        else:
            missing_slide_floor_contact_frame_count += 1
        if has_canonical_slide_floor:
            canonical_slide_floor_contact_frame_count += 1
        if has_noncanonical_slide_floor:
            noncanonical_slide_floor_contact_frame_count += 1
        if commanded_motion:
            if has_slide_floor:
                movement_slide_floor_contact_frame_count += 1
            else:
                missing_movement_slide_floor_contact_frame_count += 1
            if has_canonical_slide_floor:
                canonical_movement_slide_floor_contact_frame_count += 1
            if has_noncanonical_slide_floor:
                noncanonical_movement_slide_floor_contact_frame_count += 1

        var support_raw: Variant = _canonical_floor_support(player, floor_snap_length, safe_margin)
        var has_canonical_support := support_raw is Dictionary
        if not has_canonical_support:
            missing_support_frame_count += 1
            if not commanded_motion:
                missing_stationary_canonical_support_frame_count += 1
            previous_normal = null
        else:
            var support: Dictionary = support_raw
            var normal: Vector3 = support["normal"]
            var support_gap_m := float(support["gap_m"])
            if not is_finite(support_gap_m) or support_gap_m < 0.0 or support_gap_m > floor_snap_length + NUMERIC_EPSILON_M:
                _fail("canonical support gap escaped authoritative floor snap length")
                return
            max_observed_canonical_support_gap_m = maxf(max_observed_canonical_support_gap_m, support_gap_m)
            support_frame_count += 1
            if not commanded_motion:
                stationary_canonical_support_frame_count += 1
            if not has_slide_floor:
                no_slide_floor_contact_grounded_canonical_support_frame_count += 1
                max_observed_no_slide_canonical_support_gap_m = maxf(max_observed_no_slide_canonical_support_gap_m, support_gap_m)
                if support_gap_m > floor_snap_length + NUMERIC_EPSILON_M:
                    no_slide_support_gap_violation_count += 1
                    if first_no_slide_support_gap_violation_step == 0:
                        first_no_slide_support_gap_violation_step = step_index + 1
                if commanded_motion:
                    movement_no_slide_floor_contact_grounded_canonical_support_frame_count += 1
            if previous_normal is Vector3:
                var normal_delta := _normal_delta(previous_normal as Vector3, normal)
                if not is_finite(normal_delta):
                    _fail("non-finite canonical floor-normal delta")
                    return
                normal_transition_count += 1
                max_observed_normal_delta_rad = maxf(max_observed_normal_delta_rad, normal_delta)
                if normal_delta > floor_max_angle + NUMERIC_EPSILON_RAD:
                    normal_transition_violation_count += 1
                    if first_normal_transition_violation_step == 0:
                        first_normal_transition_violation_step = step_index + 1
            previous_normal = normal

        var character_raw: Variant = _character_floor_normal(player)
        if not character_raw is Vector3:
            missing_character_floor_normal_frame_count += 1
            previous_character_normal = null
        else:
            var character_normal := character_raw as Vector3
            character_floor_normal_frame_count += 1
            if previous_character_normal is Vector3:
                var character_delta := _normal_delta(previous_character_normal as Vector3, character_normal)
                if not is_finite(character_delta):
                    _fail("non-finite CharacterBody floor-normal delta")
                    return
                character_floor_normal_transition_count += 1
                max_observed_character_floor_normal_delta_rad = maxf(max_observed_character_floor_normal_delta_rad, character_delta)
                if character_delta > floor_max_angle + NUMERIC_EPSILON_RAD:
                    character_floor_normal_transition_violation_count += 1
                    if first_character_floor_normal_transition_violation_step == 0:
                        first_character_floor_normal_transition_violation_step = step_index + 1
            previous_character_normal = character_normal
        await physics_frame

    var expected_transition_count := STEP_COUNT - 1
    var continuous_canonical_floor_normal := support_frame_count == STEP_COUNT and missing_support_frame_count == 0 and normal_transition_count == expected_transition_count and normal_transition_violation_count == 0 and first_normal_transition_violation_step == 0 and max_observed_normal_delta_rad <= floor_max_angle + NUMERIC_EPSILON_RAD
    var continuous_character_floor_normal := character_floor_normal_frame_count == STEP_COUNT and missing_character_floor_normal_frame_count == 0 and character_floor_normal_transition_count == expected_transition_count and character_floor_normal_transition_violation_count == 0 and first_character_floor_normal_transition_violation_step == 0 and max_observed_character_floor_normal_delta_rad <= floor_max_angle + NUMERIC_EPSILON_RAD
    var canonical_emitted_slide_floor_contacts := slide_floor_contact_frame_count > 0 and canonical_slide_floor_contact_frame_count == slide_floor_contact_frame_count and noncanonical_slide_floor_contact_frame_count == 0 and canonical_movement_slide_floor_contact_frame_count == movement_slide_floor_contact_frame_count and noncanonical_movement_slide_floor_contact_frame_count == 0
    var grounded_canonical_fallback_for_no_slide_contact := no_slide_floor_contact_grounded_canonical_support_frame_count == missing_slide_floor_contact_frame_count and movement_no_slide_floor_contact_grounded_canonical_support_frame_count == missing_movement_slide_floor_contact_frame_count and stationary_canonical_support_frame_count == stationary_hold_frame_count and missing_stationary_canonical_support_frame_count == 0
    var grounded_canonical_fallback_within_floor_snap := no_slide_support_gap_violation_count == 0 and first_no_slide_support_gap_violation_step == 0 and max_observed_no_slide_canonical_support_gap_m <= floor_snap_length + NUMERIC_EPSILON_M
    var continuous_floor_normal := continuous_canonical_floor_normal and continuous_character_floor_normal and canonical_emitted_slide_floor_contacts and grounded_canonical_fallback_for_no_slide_contact and grounded_canonical_fallback_within_floor_snap and movement_command_frame_count > 0 and movement_command_frame_count + stationary_hold_frame_count == STEP_COUNT and slide_floor_contact_frame_count + missing_slide_floor_contact_frame_count == STEP_COUNT and movement_slide_floor_contact_frame_count + missing_movement_slide_floor_contact_frame_count == movement_command_frame_count

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-floor-normal-continuity-v7",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "physics_hz": PHYSICS_HZ,
        "step_count": STEP_COUNT,
        "expected_normal_transition_count": expected_transition_count,
        "authoritative_floor_max_angle_rad": floor_max_angle,
        "normal_delta_bound_derivation": "authoritative_characterbody_floor_max_angle",
        "max_allowed_normal_delta_rad": floor_max_angle,
        "max_observed_normal_delta_rad": max_observed_normal_delta_rad,
        "authoritative_safe_margin_m": safe_margin,
        "authoritative_floor_snap_length_m": floor_snap_length,
        "support_gap_bound_derivation": "authoritative_characterbody_floor_snap_length",
        "max_allowed_no_slide_support_gap_m": floor_snap_length,
        "max_observed_canonical_support_gap_m": max_observed_canonical_support_gap_m,
        "max_observed_no_slide_canonical_support_gap_m": max_observed_no_slide_canonical_support_gap_m,
        "no_slide_support_gap_violation_count": no_slide_support_gap_violation_count,
        "first_no_slide_support_gap_violation_step": first_no_slide_support_gap_violation_step,
        "support_frame_count": support_frame_count,
        "missing_support_frame_count": missing_support_frame_count,
        "normal_transition_count": normal_transition_count,
        "normal_transition_violation_count": normal_transition_violation_count,
        "first_normal_transition_violation_step": first_normal_transition_violation_step,
        "max_observed_character_floor_normal_delta_rad": max_observed_character_floor_normal_delta_rad,
        "character_floor_normal_frame_count": character_floor_normal_frame_count,
        "missing_character_floor_normal_frame_count": missing_character_floor_normal_frame_count,
        "character_floor_normal_transition_count": character_floor_normal_transition_count,
        "character_floor_normal_transition_violation_count": character_floor_normal_transition_violation_count,
        "first_character_floor_normal_transition_violation_step": first_character_floor_normal_transition_violation_step,
        "movement_command_frame_count": movement_command_frame_count,
        "stationary_hold_frame_count": stationary_hold_frame_count,
        "slide_floor_contact_frame_count": slide_floor_contact_frame_count,
        "missing_slide_floor_contact_frame_count": missing_slide_floor_contact_frame_count,
        "canonical_slide_floor_contact_frame_count": canonical_slide_floor_contact_frame_count,
        "noncanonical_slide_floor_contact_frame_count": noncanonical_slide_floor_contact_frame_count,
        "no_slide_floor_contact_grounded_canonical_support_frame_count": no_slide_floor_contact_grounded_canonical_support_frame_count,
        "movement_slide_floor_contact_frame_count": movement_slide_floor_contact_frame_count,
        "missing_movement_slide_floor_contact_frame_count": missing_movement_slide_floor_contact_frame_count,
        "canonical_movement_slide_floor_contact_frame_count": canonical_movement_slide_floor_contact_frame_count,
        "noncanonical_movement_slide_floor_contact_frame_count": noncanonical_movement_slide_floor_contact_frame_count,
        "movement_no_slide_floor_contact_grounded_canonical_support_frame_count": movement_no_slide_floor_contact_grounded_canonical_support_frame_count,
        "stationary_canonical_support_frame_count": stationary_canonical_support_frame_count,
        "missing_stationary_canonical_support_frame_count": missing_stationary_canonical_support_frame_count,
        "support_mode": "characterbody_capsule_test_motion",
        "character_floor_normal_source": "CharacterBody3D.get_floor_normal_after_move_and_slide",
        "slide_floor_contact_source": "CharacterBody3D.get_slide_collision_after_move_and_slide",
        "slide_floor_contact_semantics": "emitted_floor_contacts_must_be_canonical; no_emitted_contact_requires_grounded_characterbody_plus_canonical_capsule_test_motion_within_floor_snap_length",
        "canonical_owner_id": OWNER_ID,
        "continuous_canonical_floor_normal": continuous_canonical_floor_normal,
        "continuous_character_floor_normal": continuous_character_floor_normal,
        "canonical_emitted_slide_floor_contacts": canonical_emitted_slide_floor_contacts,
        "grounded_canonical_fallback_for_no_slide_contact": grounded_canonical_fallback_for_no_slide_contact,
        "grounded_canonical_fallback_within_floor_snap": grounded_canonical_fallback_within_floor_snap,
        "continuous_floor_normal": continuous_floor_normal,
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
        _fail("unable to persist floor-normal receipt")
        return
    if not continuous_floor_normal:
        _fail("three-second traversal lost canonical support, escaped floor-snap fallback, emitted a noncanonical floor contact or broke floor-normal continuity")
        return

    print("BOURSE_8512036_FLOOR_NORMAL_CONTINUITY_GREEN: support_frames=%d motion_frames=%d slide_floor_frames=%d no_slide_frames=%d canonical_slide_frames=%d noncanonical_slide_frames=%d movement_no_slide_fallback_frames=%d max_no_slide_gap_m=%.6f floor_snap_m=%.6f safe_margin_m=%.6f canonical_max_delta_rad=%.6f character_max_delta_rad=%.6f floor_max_angle_rad=%.6f" % [support_frame_count, movement_command_frame_count, slide_floor_contact_frame_count, missing_slide_floor_contact_frame_count, canonical_slide_floor_contact_frame_count, noncanonical_slide_floor_contact_frame_count, movement_no_slide_floor_contact_grounded_canonical_support_frame_count, max_observed_no_slide_canonical_support_gap_m, floor_snap_length, safe_margin, max_observed_normal_delta_rad, max_observed_character_floor_normal_delta_rad, floor_max_angle])
    quit(0)
