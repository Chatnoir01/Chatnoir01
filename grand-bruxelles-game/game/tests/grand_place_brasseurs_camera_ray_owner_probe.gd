extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT := "res://artifacts/qa/brasseurs_camera_ray_owner_probe.json"
const CAMERA := Vector3(324.9581, 3.3, -512.8388)
const WALL_A_XZ := Vector2(317.93637041315284, -487.48588343904734)
const WALL_B_XZ := Vector2(325.884743245733, -483.8294664611034)
const SAMPLE_HEIGHTS := [3.0, 7.0, 11.0, 15.0, 18.0]
const SAMPLE_U := [0.15, 0.35, 0.50, 0.65, 0.85]

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRASSEURS_CAMERA_RAY_OWNER_PROBE_FAIL: " + message)
    quit(1)

func _target(u: float, y: float) -> Vector3:
    var xz := WALL_A_XZ.lerp(WALL_B_XZ, u)
    return Vector3(xz.x, y, xz.y)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main
    for frame_index: int in range(240):
        await physics_frame
        var lod := root.get_node_or_null("GrandPlaceOfficialLod2Next")
        if lod != null and bool(lod.get("geometry_loaded")) and frame_index >= 30:
            break
    for _frame: int in range(4):
        await physics_frame

    var state := root.world_3d.direct_space_state
    if state == null:
        _fail("no 3D physics state")
        return

    var rays: Array[Dictionary] = []
    var collider_counts: Dictionary = {}
    var hit_count := 0
    for y: float in SAMPLE_HEIGHTS:
        for u: float in SAMPLE_U:
            var target := _target(u, y)
            # Extend 1.5 m beyond the official wall point so the first hit is
            # observable even when the target itself lies numerically on a face.
            var direction := (target - CAMERA).normalized()
            var query := PhysicsRayQueryParameters3D.create(CAMERA, target + direction * 1.5, 1)
            query.collide_with_bodies = true
            query.collide_with_areas = false
            var hit := state.intersect_ray(query)
            var row := {
                "u": u,
                "height_m": y,
                "target": [target.x, target.y, target.z],
                "hit": not hit.is_empty(),
            }
            if not hit.is_empty():
                hit_count += 1
                var collider := hit.get("collider") as Object
                var path := ""
                var name := ""
                var parent_path := ""
                if collider is Node:
                    var node := collider as Node
                    path = str(node.get_path())
                    name = str(node.name)
                    if node.get_parent() != null:
                        parent_path = str(node.get_parent().get_path())
                var position: Vector3 = hit.get("position", Vector3.ZERO)
                var normal: Vector3 = hit.get("normal", Vector3.ZERO)
                row["collider_path"] = path
                row["collider_name"] = name
                row["collider_parent_path"] = parent_path
                row["position"] = [position.x, position.y, position.z]
                row["normal"] = [normal.x, normal.y, normal.z]
                row["distance_from_camera_m"] = CAMERA.distance_to(position)
                var key := path if path != "" else name
                collider_counts[key] = int(collider_counts.get(key, 0)) + 1
            rays.append(row)

    var evidence := {
        "schema": "grand-bruxelles-brasseurs-camera-ray-owner-probe-v1",
        "status": "evidence_only",
        "camera": [CAMERA.x, CAMERA.y, CAMERA.z],
        "camera_contract": "merged #711 clean Grand-Place player-eye witness",
        "urbis_building_id": "1639974",
        "urbis_front_wall_id": "10945501",
        "wall_world_xz": [[WALL_A_XZ.x, WALL_A_XZ.y], [WALL_B_XZ.x, WALL_B_XZ.y]],
        "sample_heights_m": SAMPLE_HEIGHTS,
        "sample_u": SAMPLE_U,
        "ray_count": rays.size(),
        "hit_count": hit_count,
        "collider_counts": collider_counts,
        "rays": rays,
        "safe_to_hide_any_collider": false,
        "safety_reason": "ray ownership proves first collision along the player-eye line only; selective replacement still requires exact source-face ownership",
    }
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var f := FileAccess.open(OUTPUT, FileAccess.WRITE)
    if f == null:
        _fail("cannot write ray evidence")
        return
    f.store_string(JSON.stringify(evidence, "  "))
    f.close()
    print("BRASSEURS_CAMERA_RAY_OWNER_PROBE_JSON " + JSON.stringify(evidence))
    print("BRASSEURS_CAMERA_RAY_OWNER_PROBE_OK rays=%d hits=%d colliders=%s" % [rays.size(), hit_count, JSON.stringify(collider_counts)])
    quit(0)
