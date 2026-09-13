extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const SIMULATION_SECONDS := 3.0
const PHYSICS_HZ := 60
const STEP_COUNT := int(SIMULATION_SECONDS * PHYSICS_HZ)
const SURFACE_COLLISION_MASK := 524288
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_player_motion_continuity.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_PLAYER_MOTION_CONTINUITY_FAIL: %s" % message)
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

func _support_from_collider(collider: Object) -> Dictionary:
    var result := {
        "hit": false,
        "canonical_owner": false,
        "requested_osm_id_owned": false,
        "collider_name": "",
        "collider_owner_id": "",
        "collider_road_support_osm_ids": [],
    }
    if collider == null or not collider is Node:
        return result
    var collider_node := collider as Node
    var owner_id := str(collider_node.get_meta(ROAD_SUPPORT_OWNER_META, ""))
    var owned_road_ids := _exact_owned_road_ids(collider_node)
    result["hit"] = true
    result["collider_name"] = str(collider_node.name)
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

func _slide_floor_support_diagnostic(player: CharacterBody3D) -> Dictionary:
    var fallback := _support_from_collider(null)
    if not player.is_on_floor():
        return fallback
    for index: int in range(player.get_slide_collision_count()):
        var collision := player.get_slide_collision(index)
        if collision == null:
            continue
        var normal := collision.get_normal()
        if not _floor_normal_valid(player, normal):
            continue
        var support := _support_from_collider(collision.get_collider())
        support["contact_normal"] = [normal.x, normal.y, normal.z]
        support["support_mode"] = "characterbody_floor_slide_collision_diagnostic_only"
        if bool(support["canonical_owner"]) and bool(support["requested_osm_id_owned"]):
            return support
        if not bool(fallback["hit"]):
            fallback = support
    return fallback

func _capsule_floor_support(player: CharacterBody3D) -> Dictionary:
    var fallback := _support_from_collider(null)
    if not player.is_on_floor():
        return fallback
    var up := player.up_direction.normalized()
    var probe_distance := player.floor_snap_length
    if not is_finite(probe_distance) or probe_distance <= 0.0:
        probe_distance = player.safe_margin
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
        support["contact_normal"] = [normal.x, normal.y, normal.z]
        support["support_mode"] = "characterbody_capsule_test_motion"
        support["probe_distance_m"] = probe_distance
        support["probe_distance_source"] = "floor_snap_length" if player.floor_snap_length > 0.0 else "safe_margin"
        if bool(support["canonical_owner"]) and bool(support["requested_osm_id_owned"]):
            return support
        if not bool(fallback["hit"]):
            fallback = support
    return fallback

func _diagnostic_center_ray(space: PhysicsDirectSpaceState3D, position: Vector3) -> Dictionary:
    var query := PhysicsRayQueryParameters3D.create(
        Vector3(position.x, position.y + 2.0, position.z),
        Vector3(position.x, position.y - 3.0, position.z),
        SURFACE_COLLISION_MASK
    )
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var hit := space.intersect_ray(query)
    if hit.is_empty():
        return {"hit": false}
    var result := _support_from_collider(hit.get("collider") as Object)
    result["support_mode"] = "center_ray_diagnostic_only"
    var hit_position: Variant = hit.get("position", null)
    if hit_position is Vector3:
        result["ground_y"] = (hit_position as Vector3).y
    return result

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
    var shape_node := player.get_node_or_null("CollisionShape3D") as CollisionShape3D
    if shape_node == null or shape_node.shape == null or not shape_node.shape is CapsuleShape3D:
        _fail("authoritative player capsule unavailable")
        return
    var capsule := shape_node.shape as CapsuleShape3D
    var radius := float(capsule.radius)
    var height := float(capsule.height)
    var gravity := float(player.get("gravity"))
    if not is_finite(radius) or radius <= 0.0 or not is_finite(height) or height <= 0.0:
        _fail("invalid authoritative capsule dimensions")
        return
    if not is_finite(gravity) or gravity <= 0.0:
        _fail("invalid authoritative player gravity")
        return
    if player.collision_layer == 0:
        _fail("authoritative player collision layer unavailable")
        return

    var world := scene.get_viewport().world_3d
    if world == null:
        _fail("authoritative 3D world unavailable")
        return
    var space := world.direct_space_state

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
    var forward_2d := delta / path_length
    var sprint_speed := float(player.get("sprint_speed"))
    if not is_finite(sprint_speed) or sprint_speed <= 0.0:
        _fail("invalid authoritative sprint speed")
        return

    var authoritative_probe_distance := player.floor_snap_length if player.floor_snap_length > 0.0 else player.safe_margin
    if not is_finite(authoritative_probe_distance) or authoritative_probe_distance <= 0.0:
        _fail("authoritative floor support probe distance unavailable")
        return

    player.set_physics_process(false)
    player.velocity = Vector3.ZERO
    var start_position := player.global_position
    var max_progress := 0.0
    var max_vertical_delta := 0.0
    var max_lateral_deviation := 0.0
    var floor_frames := 0
    var airborne_frames := 0
    var road_support_frames := 0
    var missing_road_support_frames := 0
    var wrong_owner_support_frames := 0
    var wrong_road_support_frames := 0
    var first_invalid_road_support_frame: Dictionary = {}
    var slide_support_diagnostic_frames := 0
    var slide_support_diagnostic_misses := 0
    var diagnostic_center_ray_misses := 0
    var source_segment_frames_after_gap := 0
    var airborne_after_gap_within_source_segment := 0
    var first_airborne_after_gap_frame: Dictionary = {}
    var grounded_after_static_gap_within_source_segment := false
    var grounding_proof_frame: Dictionary = {}
    var samples: Array[Dictionary] = []
    var dt := 1.0 / float(PHYSICS_HZ)
    var station_two_progress := path_length / 6.0
    var static_gap_clear_progress := station_two_progress + radius

    for step_index: int in range(STEP_COUNT):
        var before_xz := Vector2(player.global_position.x, player.global_position.z)
        var before_progress := (before_xz - spawn_xz).dot(forward_2d)
        var horizontal_speed := sprint_speed if before_progress < path_length else 0.0
        var horizontal := Vector3(forward_2d.x, 0.0, forward_2d.y) * horizontal_speed
        var vertical_velocity := player.velocity.y
        if player.is_on_floor() and vertical_velocity < 0.0:
            vertical_velocity = -0.05
        elif not player.is_on_floor():
            vertical_velocity -= gravity * dt
        player.velocity = Vector3(horizontal.x, vertical_velocity, horizontal.z)
        player.move_and_slide()

        var current_xz := Vector2(player.global_position.x, player.global_position.z)
        var relative := current_xz - spawn_xz
        var progress := relative.dot(forward_2d)
        var lateral_vector := relative - forward_2d * progress
        var lateral_deviation := lateral_vector.length()
        max_progress = maxf(max_progress, progress)
        max_lateral_deviation = maxf(max_lateral_deviation, lateral_deviation)
        max_vertical_delta = maxf(max_vertical_delta, absf(player.global_position.y - start_position.y))
        var on_floor := player.is_on_floor()
        var support := _capsule_floor_support(player)
        var support_valid := bool(support["hit"]) and bool(support["canonical_owner"]) and bool(support["requested_osm_id_owned"])
        var slide_support := _slide_floor_support_diagnostic(player)
        var slide_support_valid := bool(slide_support["hit"]) and bool(slide_support["canonical_owner"]) and bool(slide_support["requested_osm_id_owned"])
        if slide_support_valid:
            slide_support_diagnostic_frames += 1
        else:
            slide_support_diagnostic_misses += 1
        var center_ray := _diagnostic_center_ray(space, player.global_position)
        if not bool(center_ray.get("hit", false)):
            diagnostic_center_ray_misses += 1
        if support_valid:
            road_support_frames += 1
        else:
            if not bool(support["hit"]):
                missing_road_support_frames += 1
            elif not bool(support["canonical_owner"]):
                wrong_owner_support_frames += 1
            elif not bool(support["requested_osm_id_owned"]):
                wrong_road_support_frames += 1
            if first_invalid_road_support_frame.is_empty():
                first_invalid_road_support_frame = {
                    "step": step_index + 1,
                    "time_s": float(step_index + 1) * dt,
                    "position": [player.global_position.x, player.global_position.y, player.global_position.z],
                    "progress_m": progress,
                    "support": support.duplicate(true),
                    "slide_support_diagnostic": slide_support.duplicate(true),
                    "diagnostic_center_ray": center_ray.duplicate(true),
                }
        var within_source_segment := progress >= 0.0 and progress <= path_length
        var within_capsule_centerline_tolerance := lateral_deviation <= radius
        var after_gap_within_source_segment := progress > static_gap_clear_progress and within_source_segment and within_capsule_centerline_tolerance
        if after_gap_within_source_segment:
            source_segment_frames_after_gap += 1
            if not on_floor:
                airborne_after_gap_within_source_segment += 1
                if first_airborne_after_gap_frame.is_empty():
                    first_airborne_after_gap_frame = {
                        "step": step_index + 1,
                        "time_s": float(step_index + 1) * dt,
                        "position": [player.global_position.x, player.global_position.y, player.global_position.z],
                        "progress_m": progress,
                        "lateral_deviation_m": lateral_deviation,
                        "within_source_segment": true,
                        "within_capsule_centerline_tolerance": true,
                        "on_floor": false,
                    }
        if on_floor:
            floor_frames += 1
            if after_gap_within_source_segment:
                grounded_after_static_gap_within_source_segment = true
                if grounding_proof_frame.is_empty():
                    grounding_proof_frame = {
                        "step": step_index + 1,
                        "time_s": float(step_index + 1) * dt,
                        "position": [player.global_position.x, player.global_position.y, player.global_position.z],
                        "progress_m": progress,
                        "lateral_deviation_m": lateral_deviation,
                        "within_source_segment": true,
                        "within_capsule_centerline_tolerance": true,
                        "on_floor": true,
                        "canonical_requested_road_support": support_valid,
                    }
        else:
            airborne_frames += 1
        if step_index % 15 == 0 or step_index == STEP_COUNT - 1:
            samples.append({
                "step": step_index + 1,
                "time_s": float(step_index + 1) * dt,
                "position": [player.global_position.x, player.global_position.y, player.global_position.z],
                "progress_m": progress,
                "lateral_deviation_m": lateral_deviation,
                "within_source_segment": within_source_segment,
                "within_capsule_centerline_tolerance": within_capsule_centerline_tolerance,
                "after_gap_within_source_segment": after_gap_within_source_segment,
                "on_floor": on_floor,
                "canonical_requested_road_support": support_valid,
                "road_support": support.duplicate(true),
                "slide_support_diagnostic": slide_support.duplicate(true),
                "diagnostic_center_ray": center_ray.duplicate(true),
            })
        await physics_frame

    var crossed_static_gap_station := max_progress > static_gap_clear_progress
    var expected_unobstructed_progress := minf(path_length, sprint_speed * SIMULATION_SECONDS)
    var progress_ratio := max_progress / expected_unobstructed_progress if expected_unobstructed_progress > 0.0 else 0.0
    var final_xz := Vector2(player.global_position.x, player.global_position.z)
    var final_relative := final_xz - spawn_xz
    var final_progress := final_relative.dot(forward_2d)
    var final_lateral_deviation := (final_relative - forward_2d * final_progress).length()
    var final_distance_to_target := final_xz.distance_to(target_xz)
    var continuous_grounding_after_gap := source_segment_frames_after_gap > 0 and airborne_after_gap_within_source_segment == 0
    var continuous_requested_road_support := road_support_frames == STEP_COUNT and missing_road_support_frames == 0 and wrong_owner_support_frames == 0 and wrong_road_support_frames == 0

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-player-motion-continuity-v6",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "spawn_xz": [spawn_xz.x, spawn_xz.y],
        "target_xz": [target_xz.x, target_xz.y],
        "path_length_m": path_length,
        "simulation_seconds": SIMULATION_SECONDS,
        "physics_hz": PHYSICS_HZ,
        "step_count": STEP_COUNT,
        "authoritative_sprint_speed_mps": sprint_speed,
        "authoritative_gravity_mps2": gravity,
        "capsule_radius_m": radius,
        "capsule_height_m": height,
        "authoritative_floor_snap_length_m": player.floor_snap_length,
        "authoritative_safe_margin_m": player.safe_margin,
        "authoritative_support_probe_distance_m": authoritative_probe_distance,
        "support_probe_uses_player_capsule": true,
        "support_probe_test_only": true,
        "support_probe_recovery_as_collision": true,
        "station_two_progress_m": station_two_progress,
        "static_gap_clear_progress_m": static_gap_clear_progress,
        "crossed_static_gap_station": crossed_static_gap_station,
        "grounded_after_static_gap_within_source_segment": grounded_after_static_gap_within_source_segment,
        "grounding_proof_frame": grounding_proof_frame,
        "source_segment_frames_after_gap": source_segment_frames_after_gap,
        "airborne_after_gap_within_source_segment": airborne_after_gap_within_source_segment,
        "first_airborne_after_gap_frame": first_airborne_after_gap_frame,
        "continuous_grounding_after_gap_required": true,
        "continuous_grounding_after_gap": continuous_grounding_after_gap,
        "source_segment_grounding_required": true,
        "lateral_tolerance_derived_from_capsule_radius": true,
        "surface_collision_mask": SURFACE_COLLISION_MASK,
        "collision_owner_meta": ROAD_SUPPORT_OWNER_META,
        "collision_owner_id": ROAD_SUPPORT_OWNER_ID,
        "collision_road_ids_meta": ROAD_SUPPORT_OSM_IDS_META,
        "road_support_mode": "characterbody_capsule_test_motion",
        "road_support_frames": road_support_frames,
        "missing_road_support_frames": missing_road_support_frames,
        "wrong_owner_support_frames": wrong_owner_support_frames,
        "wrong_road_support_frames": wrong_road_support_frames,
        "first_invalid_road_support_frame": first_invalid_road_support_frame,
        "continuous_requested_road_support_required": true,
        "continuous_requested_road_support": continuous_requested_road_support,
        "slide_collision_diagnostic_is_release_gate": false,
        "slide_support_diagnostic_frames": slide_support_diagnostic_frames,
        "slide_support_diagnostic_misses": slide_support_diagnostic_misses,
        "diagnostic_center_ray_is_release_gate": false,
        "diagnostic_center_ray_misses": diagnostic_center_ray_misses,
        "max_progress_m": max_progress,
        "expected_unobstructed_progress_m": expected_unobstructed_progress,
        "progress_ratio_measurement_only": progress_ratio,
        "max_vertical_delta_m": max_vertical_delta,
        "max_lateral_deviation_m": max_lateral_deviation,
        "final_progress_m": final_progress,
        "final_lateral_deviation_m": final_lateral_deviation,
        "floor_frames": floor_frames,
        "airborne_frames": airborne_frames,
        "final_distance_to_target_m": final_distance_to_target,
        "samples": samples,
        "actual_character_body_move_and_slide": true,
        "static_edge_ray_diagnostic_is_release_gate": false,
        "collision_geometry_changed": false,
        "source_geometry_changed": false,
        "camera_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write_receipt(receipt):
        _fail("unable to persist motion receipt")
        return
    if not crossed_static_gap_station:
        _fail("real player capsule did not traverse beyond the measured static edge-ray gap")
        return
    if not grounded_after_static_gap_within_source_segment or grounding_proof_frame.is_empty():
        _fail("real player capsule did not retain floor contact beyond the measured gap while still inside the source segment")
        return
    if source_segment_frames_after_gap <= 0 or not continuous_grounding_after_gap:
        _fail("floor contact was lost after the measured gap while the capsule remained inside the source segment")
        return
    if floor_frames != STEP_COUNT or airborne_frames != 0:
        _fail("real player capsule was not grounded for the full three-second traversal")
        return
    if not continuous_requested_road_support:
        _fail("authoritative player capsule support was not backed by canonical road-8512036 collision on every physics frame")
        return

    print("BOURSE_8512036_PLAYER_MOTION_CONTINUITY_GREEN: progress_m=%.6f floor_frames=%d airborne_frames=%d capsule_support_frames=%d slide_diagnostic_misses=%d center_ray_misses=%d post_gap_frames=%d max_lateral_deviation_m=%.6f final_target_distance_m=%.6f" % [max_progress, floor_frames, airborne_frames, road_support_frames, slide_support_diagnostic_misses, diagnostic_center_ray_misses, source_segment_frames_after_gap, max_lateral_deviation, final_distance_to_target])
    quit(0)
