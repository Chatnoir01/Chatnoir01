extends SceneTree

const PLAYABILITY_RUNTIME_SCRIPT := preload("res://game/scripts/mobile_playability_collision_runtime.gd")
const SEED_CELL_ID := "bxl-e149000-n169000-s500"
const EAST_CELL_ID := "bxl-e149500-n169000-s500"
const SEAM_E := 149500.0
const SOUTH_N := 169000.0
const SPACING_M := 2.0
const MAX_HEIGHT_DELTA_M := 0.002

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRUSSELS_EAST_DTM_RUNTIME_FAIL: %s" % message)
    quit(1)

func _expect(condition: bool, message: String) -> bool:
    if not condition:
        _fail(message)
        return false
    return true

func _wait_for_loaded(runtime: BrusselsWorldStreamingRuntime, cell_id: String, frames: int = 140) -> Node:
    for _frame: int in range(frames):
        await physics_frame
        await process_frame
        if runtime.backend.has_active_instance(cell_id):
            var instance := runtime.backend.get_instance(cell_id)
            if is_instance_valid(instance) and bool(instance.get("runtime_loaded")):
                return instance
    return null

func _raycast_height(world: Node3D, position: Vector3, expected_body_name: String) -> Dictionary:
    var query := PhysicsRayQueryParameters3D.create(
        Vector3(position.x, position.y + 120.0, position.z),
        Vector3(position.x, position.y - 120.0, position.z)
    )
    query.collision_mask = 1
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return {}
    var collider: Object = hit.get("collider")
    if not collider is Node or (collider as Node).name != expected_body_name:
        return {"wrong_collider": true, "actual": (collider as Node).name if collider is Node else "non-node"}
    return hit

func _run() -> void:
    var world := Node3D.new()
    world.name = "Main"
    root.add_child(world)

    var player := CharacterBody3D.new()
    player.name = "Player"
    player.position = Vector3(-652.0, 1.05, 621.0)
    world.add_child(player)

    var playability := PLAYABILITY_RUNTIME_SCRIPT.new()
    playability.name = "MobilePlayabilityCollisionRuntime"
    world.add_child(playability)

    var runtime: BrusselsWorldStreamingRuntime = null
    for _frame: int in range(20):
        await process_frame
        runtime = world.get_node_or_null("WorldStreamingRuntime") as BrusselsWorldStreamingRuntime
        if runtime != null and runtime.runtime_ready:
            break
    if not _expect(runtime != null and runtime.runtime_ready, "production world streamer did not become ready"):
        return

    var east_descriptor := runtime.manager.get_cell_descriptor(EAST_CELL_ID)
    var east_center: Vector3 = east_descriptor.get("world_center", Vector3.ZERO)
    if not _expect(east_center != Vector3.ZERO, "east DTM cell has no production world center"):
        return

    # Predictive visual load: terrain may appear, collision must remain off.
    player.global_position = east_center + Vector3(600.0, 1.05, 0.0)
    player.velocity = Vector3(-100.0, 0.0, 0.0)
    var east := await _wait_for_loaded(runtime, EAST_CELL_ID)
    if not _expect(is_instance_valid(east), "east DTM cell did not stream in"):
        return
    if not _expect(int(east.get("terrain_sample_count")) == 63001 and int(east.get("terrain_triangle_count")) == 125000, "east 2 m DTM topology drifted"):
        return
    if not _expect(int(east.get("street_surface_count")) == 252 and int(east.get("street_segment_count")) == 212, "east official street counts drifted"):
        return
    if not _expect(int(east.get("source_building_count")) == 919 and int(east.get("blocked_unapproved_building_count")) == 919 and int(east.get("rendered_building_count")) == 0, "east building fail-closed gate drifted"):
        return
    if not _expect(absf(float(east.get("vertical_reference_absolute_m")) - 62.393423) <= 0.000001, "east cell did not use shared seed datum"):
        return
    if not _expect(absf(float(east.get("first_relative_height_m"))) > 1.0, "east cell appears to have been incorrectly re-zeroed to its own first sample"):
        return
    if not _expect(int(east.get("terrain_sample_failures")) == 0, "east street drape sampled outside authoritative DTM"):
        return
    if not _expect(float(east.get("street_surface_min_vertex_clearance_m")) >= 0.0345, "east street vertices are not terrain-supported"):
        return
    if not _expect(int(east.call("get_max_stream_phase_ms")) <= 50, "east streamed DTM exceeded 50 ms phase guard"):
        return
    if not _expect(not runtime.manager.is_collision_active(EAST_CELL_ID), "east predictive prefetch enabled collision too early"):
        return
    if not _expect(not bool(east.call("is_streamed_collision_enabled")), "east cell created collision outside near-player tier"):
        return

    # The seed/east boundary is exactly 250 m from both cell centers, inside the
    # 260 m collision tier. Both real HeightMapShape3D bodies must therefore be
    # active together for a direct seam + PhysicsServer test.
    var seam_mid: Vector3 = east.call("lambert_to_game", SEAM_E, SOUTH_N + 250.0)
    var seam_mid_height := float(east.call("sample_height", seam_mid.x, seam_mid.z))
    player.global_position = Vector3(seam_mid.x, seam_mid_height + 1.05, seam_mid.z)
    player.velocity = Vector3.ZERO

    var seed: Node = null
    for _frame: int in range(160):
        await physics_frame
        await process_frame
        if runtime.backend.has_active_instance(SEED_CELL_ID):
            seed = runtime.backend.get_instance(SEED_CELL_ID)
        if is_instance_valid(seed) and bool(seed.get("runtime_loaded")) and runtime.manager.is_collision_active(SEED_CELL_ID) and runtime.manager.is_collision_active(EAST_CELL_ID) and bool(seed.call("is_streamed_collision_enabled")) and bool(east.call("is_streamed_collision_enabled")):
            break
    if not _expect(is_instance_valid(seed) and bool(seed.get("runtime_loaded")), "seed DTM was not loaded beside east cell"):
        return
    if not _expect(runtime.manager.is_collision_active(SEED_CELL_ID) and runtime.manager.is_collision_active(EAST_CELL_ID), "scheduler did not activate both seam collision tiers"):
        return
    if not _expect(seed.find_child("OfficialIxellesDTMCollision", true, false) != null and east.find_child("OfficialBrusselsDTMCollision", true, false) != null, "one of the real seam collision bodies is missing"):
        return

    var max_seam_delta_m := 0.0
    var max_world_xz_delta_m := 0.0
    for row: int in range(251):
        var n := SOUTH_N + float(row) * SPACING_M
        var seed_position: Vector3 = seed.call("lambert_to_game", SEAM_E, n)
        var east_position: Vector3 = east.call("lambert_to_game", SEAM_E, n)
        max_world_xz_delta_m = maxf(max_world_xz_delta_m, Vector2(seed_position.x - east_position.x, seed_position.z - east_position.z).length())
        var seed_y := float(seed.call("sample_height", seed_position.x, seed_position.z))
        var east_y := float(east.call("sample_height", east_position.x, east_position.z))
        max_seam_delta_m = maxf(max_seam_delta_m, absf(seed_y - east_y))
    if not _expect(max_world_xz_delta_m <= 0.0001, "seed/east Lambert world transform diverged %.6f m" % max_world_xz_delta_m):
        return
    if not _expect(max_seam_delta_m <= 0.0001, "seed/east rendered DTM seam diverged %.6f m" % max_seam_delta_m):
        return

    var physics_rows: Array[int] = [20, 70, 125, 180, 230]
    var max_physics_delta_m := 0.0
    for row: int in physics_rows:
        var n := SOUTH_N + float(row) * SPACING_M
        var seed_point: Vector3 = seed.call("lambert_to_game", SEAM_E - 1.0, n)
        seed_point.y = float(seed.call("sample_height", seed_point.x, seed_point.z))
        var seed_hit := _raycast_height(world, seed_point, "OfficialIxellesDTMCollision")
        if not _expect(not seed_hit.is_empty() and not bool(seed_hit.get("wrong_collider", false)), "PhysicsServer missed seed terrain near seam at row=%d: %s" % [row, seed_hit]):
            return
        max_physics_delta_m = maxf(max_physics_delta_m, absf((seed_hit.get("position") as Vector3).y - seed_point.y))

        var east_point: Vector3 = east.call("lambert_to_game", SEAM_E + 1.0, n)
        east_point.y = float(east.call("sample_height", east_point.x, east_point.z))
        var east_hit := _raycast_height(world, east_point, "OfficialBrusselsDTMCollision")
        if not _expect(not east_hit.is_empty() and not bool(east_hit.get("wrong_collider", false)), "PhysicsServer missed east terrain near seam at row=%d: %s" % [row, east_hit]):
            return
        max_physics_delta_m = maxf(max_physics_delta_m, absf((east_hit.get("position") as Vector3).y - east_point.y))

    if not _expect(max_physics_delta_m <= MAX_HEIGHT_DELTA_M, "seed/east PhysicsServer terrain divergence %.6f m exceeds 2 mm" % max_physics_delta_m):
        return

    player.global_position = east_center + Vector3(1000.0, 1.05, 0.0)
    for _frame: int in range(16):
        await physics_frame
        await process_frame
    if not _expect(not runtime.backend.has_active_instance(EAST_CELL_ID), "east DTM cell did not unload outside hysteresis radius"):
        return

    print("BRUSSELS_EAST_DTM_RUNTIME_OK: triangles=125000 streets=252 blocked_buildings=919 seam_pairs=251 seam_delta=%.6f world_xz_delta=%.6f physics_delta=%.6f shared_reference=62.393423" % [max_seam_delta_m, max_world_xz_delta_m, max_physics_delta_m])
    world.queue_free()
    quit(0)
