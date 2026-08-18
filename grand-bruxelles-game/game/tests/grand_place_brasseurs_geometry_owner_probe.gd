extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const OUTPUT := "res://artifacts/qa/brasseurs_scene_geometry_probe.json"
const WALL_A := Vector3(317.93637041315284, 0.0, -487.48588343904734)
const WALL_B := Vector3(325.884743245733, 0.0, -483.8294664611034)
const PROBE := AABB(Vector3(314.0, -1.0, -492.0), Vector3(16.0, 32.0, 14.0))

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("BRASSEURS_GEOMETRY_OWNER_PROBE_FAIL: " + message)
    quit(1)

func _walk(node: Node, out: Array[Node]) -> void:
    out.append(node)
    for child: Node in node.get_children():
        _walk(child, out)

func _aabb_array(box: AABB) -> Array:
    return [box.position.x, box.position.y, box.position.z, box.size.x, box.size.y, box.size.z]

func _mesh_world_aabb(node: MeshInstance3D) -> AABB:
    if node.mesh == null:
        return AABB()
    return node.global_transform * node.mesh.get_aabb()

func _csg_world_aabb(node: CSGShape3D) -> AABB:
    if not node.is_root_shape():
        return AABB()
    var mesh := node.bake_static_mesh()
    if mesh == null or mesh.get_surface_count() == 0:
        return AABB()
    return node.global_transform * mesh.get_aabb()

func _xz_distance_to_probe_mid(box: AABB) -> float:
    var p := Vector2((WALL_A.x + WALL_B.x) * 0.5, (WALL_A.z + WALL_B.z) * 0.5)
    var q := Vector2(
        clampf(p.x, box.position.x, box.end.x),
        clampf(p.y, box.position.z, box.end.z)
    )
    return p.distance_to(q)

func _run() -> void:
    var main := MAIN_SCENE.instantiate()
    root.add_child(main)
    current_scene = main

    for frame_index: int in range(240):
        await process_frame
        var generated := main.get_node_or_null("BrusselsOSM/GeneratedBuildings")
        if generated != null and generated.get_child_count() > 0 and frame_index >= 30:
            break
    for _frame: int in range(12):
        await process_frame

    var all_nodes: Array[Node] = []
    _walk(root, all_nodes)
    var hits: Array[Dictionary] = []
    var nearby: Array[Dictionary] = []
    var scanned_geometry := 0

    for raw: Node in all_nodes:
        var box := AABB()
        var geometry_kind := ""
        if raw is MeshInstance3D:
            box = _mesh_world_aabb(raw as MeshInstance3D)
            geometry_kind = "MeshInstance3D"
        elif raw is CSGShape3D:
            box = _csg_world_aabb(raw as CSGShape3D)
            geometry_kind = raw.get_class()
        else:
            continue
        if box.size == Vector3.ZERO:
            continue
        scanned_geometry += 1
        var distance := _xz_distance_to_probe_mid(box)
        var row := {
            "path": str(raw.get_path()),
            "name": str(raw.name),
            "class": geometry_kind,
            "visible_in_tree": (raw as Node3D).is_visible_in_tree(),
            "world_aabb": _aabb_array(box),
            "probe_midpoint_xz_distance_m": distance,
        }
        if box.intersects(PROBE):
            hits.append(row)
        elif distance <= 30.0:
            nearby.append(row)

    hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["probe_midpoint_xz_distance_m"]) < float(b["probe_midpoint_xz_distance_m"])
    )
    nearby.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        return float(a["probe_midpoint_xz_distance_m"]) < float(b["probe_midpoint_xz_distance_m"])
    )
    if nearby.size() > 20:
        nearby.resize(20)

    var evidence := {
        "schema": "grand-bruxelles-brasseurs-scene-geometry-probe-v1",
        "status": "evidence_only",
        "urbis_building_id": "1639974",
        "urbis_front_wall_id": "10945501",
        "wall_world_xz": [[WALL_A.x, WALL_A.z], [WALL_B.x, WALL_B.z]],
        "probe_world_aabb": _aabb_array(PROBE),
        "scanned_geometry_count": scanned_geometry,
        "intersecting_geometry": hits,
        "nearby_geometry": nearby,
        "safe_to_hide_any_hit": false,
        "safety_reason": "intersection identifies rendered geometry occupancy only; replacement safety requires proving the hit's full geometry scope and a complete source-backed replacement envelope",
    }

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://artifacts/qa"))
    var f := FileAccess.open(OUTPUT, FileAccess.WRITE)
    if f == null:
        _fail("cannot write evidence")
        return
    f.store_string(JSON.stringify(evidence, "  "))
    f.close()

    print("BRASSEURS_GEOMETRY_OWNER_PROBE_JSON " + JSON.stringify(evidence))
    print("BRASSEURS_GEOMETRY_OWNER_PROBE_OK scanned=%d hits=%d nearby=%d safe_to_hide_any_hit=false" % [scanned_geometry, hits.size(), nearby.size()])
    if hits.is_empty():
        _fail("no rendered MeshInstance3D/CSG geometry intersects the exact Brasseurs wall probe")
        return
    quit(0)
