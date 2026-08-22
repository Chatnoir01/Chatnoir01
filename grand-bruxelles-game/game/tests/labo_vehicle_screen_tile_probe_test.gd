extends SceneTree

const WIDTH := 1280
const HEIGHT := 720
const WARMUP_FRAMES := 120
const SAMPLE_FRAMES := 120
const TILE_BBOX := Rect2(Vector2(1200.0, 320.0), Vector2(80.0, 80.0))

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("LABO_VEHICLE_SCREEN_TILE_PROBE_FAIL: %s" % message)
    quit(1)

func _collect_rgsdev_bodies(node: Node, out: Array[Node3D]) -> void:
    if node is Node3D and node.get_node_or_null("RgsdevVisual") != null:
        out.append(node as Node3D)
    for child: Node in node.get_children():
        _collect_rgsdev_bodies(child, out)

func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        out.append(node as MeshInstance3D)
    for child: Node in node.get_children():
        _collect_meshes(child, out)

func _screen_bbox_for_body(camera: Camera3D, body: Node3D) -> Rect2:
    var meshes: Array[MeshInstance3D] = []
    _collect_meshes(body, meshes)
    var min_screen := Vector2(INF, INF)
    var max_screen := Vector2(-INF, -INF)
    var projected := 0
    for mesh: MeshInstance3D in meshes:
        if not mesh.visible or mesh.mesh == null:
            continue
        var local_aabb := mesh.get_aabb()
        for xi: int in range(2):
            for yi: int in range(2):
                for zi: int in range(2):
                    var local_point := local_aabb.position + Vector3(
                        local_aabb.size.x * float(xi),
                        local_aabb.size.y * float(yi),
                        local_aabb.size.z * float(zi)
                    )
                    var world_point := mesh.global_transform * local_point
                    if camera.is_position_behind(world_point):
                        continue
                    var screen_point := camera.unproject_position(world_point)
                    min_screen.x = minf(min_screen.x, screen_point.x)
                    min_screen.y = minf(min_screen.y, screen_point.y)
                    max_screen.x = maxf(max_screen.x, screen_point.x)
                    max_screen.y = maxf(max_screen.y, screen_point.y)
                    projected += 1
    if projected == 0:
        return Rect2()
    return Rect2(min_screen, max_screen - min_screen)

func _model_id(body: Node3D) -> String:
    var visual := body.get_node_or_null("RgsdevVisual")
    if visual == null:
        return ""
    if visual.has_method("get_visual_contract"):
        var contract: Dictionary = visual.call("get_visual_contract")
        return str(contract.get("model_id", ""))
    return str(visual.get_meta("labo_vehicle_model", ""))

func _run() -> void:
    root.size = Vector2i(WIDTH, HEIGHT)
    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)

    for _i: int in range(WARMUP_FRAMES + SAMPLE_FRAMES):
        await process_frame

    var camera := root.get_camera_3d()
    if camera == null:
        _fail("active main-scene camera missing after frozen warmup")
        return

    var bodies: Array[Node3D] = []
    _collect_rgsdev_bodies(scene, bodies)
    if bodies.is_empty():
        _fail("no Rgsdev vehicle bodies found in main scene")
        return

    var hits: Array[Dictionary] = []
    var all_entries: Array[Dictionary] = []
    for body: Node3D in bodies:
        var bbox := _screen_bbox_for_body(camera, body)
        if bbox.size == Vector2.ZERO:
            continue
        var entry := {
            "name": body.name,
            "path": str(body.get_path()),
            "model_id": _model_id(body),
            "global_position": [body.global_position.x, body.global_position.y, body.global_position.z],
            "screen_bbox": [bbox.position.x, bbox.position.y, bbox.end.x, bbox.end.y],
            "simulated_occupancy": bool(body.get_meta("simulated_occupancy", false)),
            "simulated_delivery": bool(body.get_meta("simulated_delivery", false)),
            "traffic_vehicle": body.is_in_group("traffic_vehicle"),
            "vehicle_group": body.is_in_group("vehicle"),
        }
        all_entries.append(entry)
        if bbox.intersects(TILE_BBOX, true):
            hits.append(entry)

    var proof := {
        "schema": "grand-bruxelles-labo-vehicle-screen-tile-probe-v1",
        "viewport": [WIDTH, HEIGHT],
        "frozen_frames": WARMUP_FRAMES + SAMPLE_FRAMES,
        "tile_bbox": [TILE_BBOX.position.x, TILE_BBOX.position.y, TILE_BBOX.end.x, TILE_BBOX.end.y],
        "rgsdev_vehicle_count": bodies.size(),
        "projected_vehicle_count": all_entries.size(),
        "tile_hit_count": hits.size(),
        "tile_hits": hits,
    }
    print("LABO_VEHICLE_SCREEN_TILE_PROBE_JSON: %s" % JSON.stringify(proof))
    if hits.is_empty():
        _fail("no Rgsdev vehicle intersects frozen Performance tile 79")
        return
    print("LABO_VEHICLE_SCREEN_TILE_PROBE_OK: hits=%d" % hits.size())
    scene.queue_free()
    await process_frame
    quit(0)
