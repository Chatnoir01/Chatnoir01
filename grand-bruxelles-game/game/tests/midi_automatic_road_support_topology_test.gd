extends SceneTree

const MAIN_SCENE := preload("res://game/main.tscn")
const SOURCE_PATH := "res://data/osm/vertical_slice_01.game.json"
const OUTPUT_PATH := "res://artifacts/qa/midi_automatic_road_support_topology.json"
const MIDI_ROAD_NAME := "Avenue Fonsny - Fonsnylaan"
const MIDI_ANCHOR_ID := "midi"
const MAX_DISTANCE_M := 80.0
const SUPPORT_RAY_UP_M := 4.0
const SUPPORT_RAY_DOWN_M := 8.0
const PROBE_BASIS := "nearest_triangle_centroid_to_mesh_aabb_center"
const TRIANGLE_AREA_EPSILON_SQ := 0.000000000001
const EXPECTED_COLLIDER_SUFFIX := "/UrbISMidiExact/UrbISStreetSurfaces/ExactRoadCarriageways/ExactRoadCarriageways_col"
const EXPECTED_OWNER_SUFFIX := "/UrbISMidiExact/UrbISStreetSurfaces/ExactRoadCarriageways"

func _initialize() -> void:
    call_deferred("_run")

func _fail(message: String) -> void:
    push_error("MIDI_AUTOMATIC_ROAD_SUPPORT_TOPOLOGY_FAIL: %s" % message)
    quit(1)

func _document() -> Dictionary:
    if not FileAccess.file_exists(SOURCE_PATH):
        return {}
    var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
    return parsed as Dictionary if parsed is Dictionary else {}

func _anchor(document: Dictionary) -> Vector2:
    var corridor: Variant = document.get("corridor", {})
    if not corridor is Dictionary:
        return Vector2(INF, INF)
    var anchors: Variant = (corridor as Dictionary).get("anchors", [])
    if not anchors is Array:
        return Vector2(INF, INF)
    for raw: Variant in anchors:
        if raw is Dictionary and str((raw as Dictionary).get("id", "")) == MIDI_ANCHOR_ID:
            return Vector2(float((raw as Dictionary).get("x", INF)), float((raw as Dictionary).get("z", INF)))
    return Vector2(INF, INF)

func _road_points(raw: Variant) -> Array[Vector2]:
    var result: Array[Vector2] = []
    if not raw is Array:
        return result
    for pair: Variant in raw:
        if not pair is Array or pair.size() != 2:
            return []
        var point := Vector2(float(pair[0]), float(pair[1]))
        if not point.is_finite():
            return []
        result.append(point)
    return result

func _candidate_ids(document: Dictionary, anchor: Vector2) -> Array[int]:
    var result: Array[int] = []
    var roads: Variant = document.get("roads", [])
    if not roads is Array:
        return result
    for raw: Variant in roads:
        if not raw is Dictionary:
            continue
        var road := raw as Dictionary
        if str(road.get("name", "")) != MIDI_ROAD_NAME or not bool(road.get("drivable", false)):
            continue
        var osm_id := int(road.get("osm_id", 0))
        if osm_id <= 0:
            continue
        var nearest := INF
        for point: Vector2 in _road_points(road.get("points", [])):
            nearest = minf(nearest, point.distance_to(anchor))
        if is_finite(nearest) and nearest <= MAX_DISTANCE_M:
            result.append(osm_id)
    result.sort()
    return result

func _visual_owner(collider: Node) -> GeometryInstance3D:
    var current: Node = collider.get_parent()
    while current != null:
        if current is GeometryInstance3D:
            return current as GeometryInstance3D
        current = current.get_parent()
    return null

func _path_string(node: Node) -> String:
    return node.get_path().get_concatenated_names()

func _consider_triangle(best: Dictionary, target: Vector3, vertices: PackedVector3Array, surface_index: int, triangle_index: int, ia: int, ib: int, ic: int) -> Dictionary:
    if ia < 0 or ib < 0 or ic < 0 or ia >= vertices.size() or ib >= vertices.size() or ic >= vertices.size():
        return best
    var a := vertices[ia]
    var b := vertices[ib]
    var c := vertices[ic]
    if ((b - a).cross(c - a)).length_squared() <= TRIANGLE_AREA_EPSILON_SQ:
        return best
    var centroid := (a + b + c) / 3.0
    var distance_sq := centroid.distance_squared_to(target)
    if best.is_empty() or distance_sq < float(best.get("distance_sq", INF)):
        return {
            "distance_sq": distance_sq,
            "surface_index": surface_index,
            "triangle_index": triangle_index,
            "local_centroid": centroid,
        }
    return best

func _mesh_probe_point(node: MeshInstance3D) -> Dictionary:
    if node.mesh == null:
        return {"valid": false, "reason": "mesh_unavailable"}
    var mesh := node.mesh
    var local_aabb := mesh.get_aabb()
    if local_aabb.size.length_squared() <= 0.0:
        return {"valid": false, "reason": "empty_mesh_aabb"}
    var target := local_aabb.get_center()
    var best: Dictionary = {}
    for surface_index: int in range(mesh.get_surface_count()):
        if mesh.surface_get_primitive_type(surface_index) != Mesh.PRIMITIVE_TRIANGLES:
            continue
        var arrays: Array = mesh.surface_get_arrays(surface_index)
        if arrays.size() <= Mesh.ARRAY_INDEX:
            continue
        var vertices_variant: Variant = arrays[Mesh.ARRAY_VERTEX]
        if not vertices_variant is PackedVector3Array:
            continue
        var vertices := vertices_variant as PackedVector3Array
        if vertices.size() < 3:
            continue
        var indices_variant: Variant = arrays[Mesh.ARRAY_INDEX]
        if indices_variant is PackedInt32Array and not (indices_variant as PackedInt32Array).is_empty():
            var indices := indices_variant as PackedInt32Array
            var triangle_count := indices.size() / 3
            for triangle_index: int in range(triangle_count):
                var offset := triangle_index * 3
                best = _consider_triangle(best, target, vertices, surface_index, triangle_index, indices[offset], indices[offset + 1], indices[offset + 2])
        else:
            var triangle_count := vertices.size() / 3
            for triangle_index: int in range(triangle_count):
                var offset := triangle_index * 3
                best = _consider_triangle(best, target, vertices, surface_index, triangle_index, offset, offset + 1, offset + 2)
    if best.is_empty():
        return {"valid": false, "reason": "no_non_degenerate_triangle"}
    var local_centroid := best.get("local_centroid", Vector3.ZERO) as Vector3
    var world_position := node.global_transform * local_centroid
    if not world_position.is_finite():
        return {"valid": false, "reason": "non_finite_triangle_centroid"}
    return {
        "valid": true,
        "basis": PROBE_BASIS,
        "surface_index": int(best.get("surface_index", -1)),
        "triangle_index": int(best.get("triangle_index", -1)),
        "local_aabb_center": [target.x, target.y, target.z],
        "local_triangle_centroid": [local_centroid.x, local_centroid.y, local_centroid.z],
        "world_position": [world_position.x, world_position.y, world_position.z],
        "distance_to_aabb_center_m": sqrt(float(best.get("distance_sq", 0.0))),
    }

func _support_probe(node: MeshInstance3D) -> Dictionary:
    var probe := _mesh_probe_point(node)
    if not bool(probe.get("valid", false)):
        return {"hit": false, "reason": str(probe.get("reason", "probe_point_unavailable")), "probe": probe}
    var world_position_values: Array = probe.get("world_position", []) as Array
    if world_position_values.size() != 3:
        return {"hit": false, "reason": "invalid_probe_world_position", "probe": probe}
    var world_position := Vector3(float(world_position_values[0]), float(world_position_values[1]), float(world_position_values[2]))
    var origin := world_position + Vector3(0.0, SUPPORT_RAY_UP_M, 0.0)
    var finish := world_position - Vector3(0.0, SUPPORT_RAY_DOWN_M, 0.0)
    var query := PhysicsRayQueryParameters3D.create(origin, finish)
    query.collide_with_areas = false
    query.collide_with_bodies = true
    var world := node.get_world_3d()
    if world == null:
        return {"hit": false, "reason": "world_unavailable", "probe": probe}
    var hit: Dictionary = world.direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return {"hit": false, "reason": "no_support_hit", "probe": probe}
    var collider: Variant = hit.get("collider", null)
    if not collider is CollisionObject3D:
        return {"hit": false, "reason": "non_collision_object", "probe": probe}
    var collision := collider as CollisionObject3D
    var owner := _visual_owner(collision)
    var normal: Variant = hit.get("normal", Vector3.ZERO)
    var position: Variant = hit.get("position", Vector3.ZERO)
    return {
        "hit": true,
        "probe": probe,
        "collider_path": _path_string(collision),
        "collider_class": collision.get_class(),
        "collision_layer": collision.collision_layer,
        "owner_found": owner != null,
        "owner_path": _path_string(owner) if owner != null else "",
        "owner_class": owner.get_class() if owner != null else "",
        "owner_visible": owner.visible if owner != null else false,
        "owner_visible_in_tree": owner.is_visible_in_tree() if owner != null else false,
        "normal_y": (normal as Vector3).y if normal is Vector3 else 0.0,
        "position_y": (position as Vector3).y if position is Vector3 else 0.0,
    }

func _run() -> void:
    var document := _document()
    if document.is_empty():
        _fail("source unavailable")
        return
    var anchor := _anchor(document)
    if not anchor.is_finite():
        _fail("Midi anchor unavailable")
        return
    var ids := _candidate_ids(document, anchor)
    if ids.is_empty():
        _fail("no source-backed Fonsny candidates")
        return

    var viewport := SubViewport.new()
    viewport.size = Vector2i(1280, 720)
    viewport.own_world_3d = true
    root.add_child(viewport)
    var scene := MAIN_SCENE.instantiate()
    viewport.add_child(scene)
    for _frame: int in range(36):
        await process_frame
        await physics_frame

    var id_set: Dictionary = {}
    for osm_id: int in ids:
        id_set[osm_id] = true

    var rows: Array[Dictionary] = []
    var collider_paths: Dictionary = {}
    var owner_paths: Dictionary = {}
    var collision_layers: Dictionary = {}
    var exact_leaf_count := 0
    var support_hit_count := 0
    var errors: Array[String] = []
    var stack: Array[Node] = [scene]
    while not stack.is_empty():
        var current: Node = stack.pop_back()
        if current is GeometryInstance3D and str(current.name).begins_with("Road_") and current.has_meta("osm_id"):
            var osm_id := int(current.get_meta("osm_id"))
            if id_set.has(osm_id) and str(current.name).begins_with("Road_%d_" % osm_id):
                exact_leaf_count += 1
                if not current is MeshInstance3D:
                    errors.append("road-%d exact geometry is not MeshInstance3D: %s" % [osm_id, _path_string(current)])
                else:
                    var geometry := current as MeshInstance3D
                    if geometry.visible:
                        errors.append("road-%d leaf unexpectedly visible: %s" % [osm_id, _path_string(geometry)])
                    var support := _support_probe(geometry)
                    if not bool(support.get("hit", false)):
                        errors.append("road-%d leaf has no physical support at sampled triangle: %s (%s)" % [osm_id, _path_string(geometry), str(support.get("reason", "unknown"))])
                    else:
                        support_hit_count += 1
                        var collider_path := str(support.get("collider_path", ""))
                        var owner_path := str(support.get("owner_path", ""))
                        var layer := int(support.get("collision_layer", 0))
                        collider_paths[collider_path] = int(collider_paths.get(collider_path, 0)) + 1
                        owner_paths[owner_path] = int(owner_paths.get(owner_path, 0)) + 1
                        collision_layers[str(layer)] = int(collision_layers.get(str(layer), 0)) + 1
                        if not collider_path.ends_with(EXPECTED_COLLIDER_SUFFIX):
                            errors.append("road-%d support collider drifted: %s" % [osm_id, collider_path])
                        if not owner_path.ends_with(EXPECTED_OWNER_SUFFIX):
                            errors.append("road-%d support visual owner drifted: %s" % [osm_id, owner_path])
                        if not bool(support.get("owner_visible", false)) or not bool(support.get("owner_visible_in_tree", false)):
                            errors.append("road-%d support owner is not visible in tree" % osm_id)
                        if layer <= 0:
                            errors.append("road-%d support collider has no collision layer" % osm_id)
                        if float(support.get("normal_y", 0.0)) <= 0.0:
                            errors.append("road-%d support hit is not upward-facing" % osm_id)
                    rows.append({
                        "osm_id": osm_id,
                        "road_leaf_path": _path_string(geometry),
                        "road_leaf_visible": geometry.visible,
                        "support": support,
                    })
        for child: Node in current.get_children():
            stack.append(child)

    if exact_leaf_count <= 0:
        errors.append("no exact candidate road leaves found")
    if rows.size() != exact_leaf_count:
        errors.append("not every exact candidate road leaf is probeable mesh geometry")
    if support_hit_count != exact_leaf_count:
        errors.append("not every exact candidate leaf has physical support at a real sampled triangle")
    if collider_paths.size() != 1:
        errors.append("support topology is fragmented across %d collider paths" % collider_paths.size())
    if owner_paths.size() != 1:
        errors.append("support topology is fragmented across %d visual owner paths" % owner_paths.size())
    if collision_layers.size() != 1:
        errors.append("support topology uses inconsistent collision layers")

    var output := {
        "schema": "grand-bruxelles-midi-automatic-road-support-topology-v3",
        "source_path": SOURCE_PATH,
        "source_sha256": FileAccess.get_sha256(SOURCE_PATH).to_lower(),
        "probe_basis": PROBE_BASIS,
        "candidate_ids": ids,
        "candidate_count": ids.size(),
        "exact_road_leaf_count": exact_leaf_count,
        "support_hit_count": support_hit_count,
        "support_collider_paths": collider_paths,
        "support_visual_owner_paths": owner_paths,
        "support_collision_layers": collision_layers,
        "rows": rows,
        "topology_errors": errors,
        "topology_fail_closed": true,
        "osm_to_urbis_crosswalk_claimed": false,
        "destination_advertisable": false,
        "visual_acceptance": false,
        "jouable_authorized": false,
    }
    var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
    DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
    var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
    if file == null:
        _fail("cannot persist support topology evidence")
        return
    file.store_string(JSON.stringify(output, "  ", true) + "\n")
    file.close()
    if not errors.is_empty():
        _fail("support topology contract failed: %s" % JSON.stringify(errors))
        return
    print("MIDI_AUTOMATIC_ROAD_SUPPORT_TOPOLOGY_GREEN: candidates=%d leaves=%d hits=%d probe_basis=%s collider_paths=%d owner_paths=%d collision_layers=%d crosswalk_claimed=false destination_advertisable=false visual_acceptance=false jouable_authorized=false" % [ids.size(), exact_leaf_count, support_hit_count, PROBE_BASIS, collider_paths.size(), owner_paths.size(), collision_layers.size()])
    quit(0)
