extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const RESOLVER_SCRIPT := preload("res://game/scripts/automatic_road_direct_spawn.gd")
const ROAD_ID := 8512036
const STATION_COUNT := 7
const LATERAL_FACTORS := [-1.0, 0.0, 1.0]
const SURFACE_COLLISION_MASK := 524288
const ROAD_SUPPORT_OWNER_META := "grand_bruxelles_owner"
const ROAD_SUPPORT_OWNER_ID := "generic_osm_surface_collision_runtime"
const ROAD_SUPPORT_OSM_IDS_META := "road_support_osm_ids"
const RECEIPT_PATH := "res://artifacts/qa/bourse_8512036_ground_gap_diagnostic.json"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BOURSE_8512036_GROUND_GAP_DIAGNOSTIC_FAIL: %s" % message)
    quit(1)

func _write_receipt(receipt: Dictionary) -> bool:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var file := FileAccess.open(RECEIPT_PATH, FileAccess.WRITE)
    if file == null:
        return false
    file.store_string(JSON.stringify(receipt, "  ") + "\n")
    file.close()
    return true

func _owned_ids(node: Node) -> Array[int]:
    var raw: Variant = node.get_meta(ROAD_SUPPORT_OSM_IDS_META, null)
    if not raw is Array:
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
    var radius := float((shape_node.shape as CapsuleShape3D).radius)
    if not is_finite(radius) or radius <= 0.0:
        _fail("invalid player footprint radius")
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
    if delta.length() < 10.0:
        _fail("diagnostic corridor too short")
        return
    var forward := delta.normalized()
    var lateral := Vector2(-forward.y, forward.x)

    var world := scene.get_viewport().world_3d
    if world == null:
        _fail("3D world unavailable")
        return
    var space := world.direct_space_state
    var samples: Array[Dictionary] = []
    var missing: Array[Dictionary] = []
    var wrong_owner: Array[Dictionary] = []
    var wrong_road: Array[Dictionary] = []

    for station_index: int in range(STATION_COUNT):
        var t := float(station_index) / float(STATION_COUNT - 1)
        var center_xz := spawn_xz.lerp(target_xz, t)
        for lateral_index: int in range(LATERAL_FACTORS.size()):
            var lateral_factor := float(LATERAL_FACTORS[lateral_index])
            var lateral_offset_m := lateral_factor * radius
            var xz := center_xz + lateral * lateral_offset_m
            var query := PhysicsRayQueryParameters3D.create(
                Vector3(xz.x, 6.0, xz.y),
                Vector3(xz.x, -4.0, xz.y),
                SURFACE_COLLISION_MASK
            )
            query.collide_with_areas = false
            query.collide_with_bodies = true
            var hit := space.intersect_ray(query)
            var sample := {
                "station_index": station_index,
                "station_number": station_index + 1,
                "lateral_index": lateral_index,
                "t": t,
                "lateral_factor": lateral_factor,
                "lateral_offset_m": lateral_offset_m,
                "xz": [xz.x, xz.y],
                "hit": not hit.is_empty(),
                "canonical_owner": false,
                "requested_osm_id_owned": false,
            }
            if hit.is_empty():
                missing.append(sample.duplicate(true))
                samples.append(sample)
                continue
            var collider: Object = hit.get("collider") as Object
            if collider == null or not collider is Node:
                wrong_owner.append(sample.duplicate(true))
                samples.append(sample)
                continue
            var collider_node := collider as Node
            var owner_id := str(collider_node.get_meta(ROAD_SUPPORT_OWNER_META, ""))
            var ids := _owned_ids(collider_node)
            sample["collider_name"] = str(collider_node.name)
            sample["collider_owner_id"] = owner_id
            sample["collider_road_support_osm_ids"] = ids
            sample["canonical_owner"] = owner_id == ROAD_SUPPORT_OWNER_ID
            sample["requested_osm_id_owned"] = ids.has(ROAD_ID)
            var position: Variant = hit.get("position", null)
            if position is Vector3:
                sample["ground_y"] = (position as Vector3).y
            if owner_id != ROAD_SUPPORT_OWNER_ID:
                wrong_owner.append(sample.duplicate(true))
            elif not ids.has(ROAD_ID):
                wrong_road.append(sample.duplicate(true))
            samples.append(sample)

    var expected := STATION_COUNT * LATERAL_FACTORS.size()
    if samples.size() != expected:
        _fail("probe accounting mismatch")
        return

    var receipt := {
        "schema": "grand-bruxelles-bourse-8512036-ground-gap-diagnostic-v1",
        "road_osm_id": ROAD_ID,
        "lookup_mode": str(player.get_meta("automatic_road_direct_lookup_mode", "")),
        "source_path": str(player.get_meta("automatic_road_direct_source_path", "")),
        "source_sha256": str(player.get_meta("automatic_road_direct_source_sha256", "")),
        "spawn_xz": [spawn_xz.x, spawn_xz.y],
        "target_xz": [target_xz.x, target_xz.y],
        "station_count": STATION_COUNT,
        "lateral_factors": LATERAL_FACTORS,
        "player_footprint_radius_m": radius,
        "probe_count": expected,
        "missing_probe_count": missing.size(),
        "wrong_owner_probe_count": wrong_owner.size(),
        "wrong_road_probe_count": wrong_road.size(),
        "samples": samples,
        "missing_probes": missing,
        "wrong_owner_probes": wrong_owner,
        "wrong_road_probes": wrong_road,
        "diagnostic_only": true,
        "release_gate_unchanged": true,
        "collision_geometry_changed": false,
        "source_geometry_changed": false,
        "resolver_thresholds_lowered": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    if not _write_receipt(receipt):
        _fail("unable to persist diagnostic receipt")
        return

    print("BOURSE_8512036_GROUND_GAP_DIAGNOSTIC_OK: probes=%d missing=%d wrong_owner=%d wrong_road=%d footprint_radius_m=%.6f release_gate_unchanged=true" % [expected, missing.size(), wrong_owner.size(), wrong_road.size(), radius])
    quit(0)
