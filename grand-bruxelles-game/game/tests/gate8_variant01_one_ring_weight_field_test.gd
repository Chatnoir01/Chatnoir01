extends SceneTree

const TARGET_PATH := "res://assets/npc_gate_01.glb"
const GEOMETRY_PATH := "res://evidence/edge-seam-geometry-result.json"
const CONTRACT_PATH := "res://contract.json"
const OUT_PATH := "res://gate8_variant01_one_ring_weight_field_result.json"

var failures: Array[String] = []
var mesh_nodes: Array[MeshInstance3D] = []

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        failures.append("missing_json=" + path)
        return {}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        failures.append("invalid_json=" + path)
        return {}
    return parsed

func _write_result(result: Dictionary) -> void:
    var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
    if f == null:
        push_error("cannot_write_result")
        quit(2)
        return
    f.store_string(JSON.stringify(result, "  ", false))
    f.close()
    print(JSON.stringify(result))
    quit(0 if failures.is_empty() else 1)

func _collect_meshes(node: Node) -> void:
    if node is MeshInstance3D:
        mesh_nodes.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect_meshes(child)

func _find_mesh(name: String) -> MeshInstance3D:
    var matches: Array[MeshInstance3D] = []
    for node in mesh_nodes:
        if node.name == name:
            matches.append(node)
    if matches.size() != 1:
        failures.append("mesh_name_resolution_%s=%d" % [name, matches.size()])
        return null
    return matches[0]

func _surface_ref_parts(surface_ref: String) -> Dictionary:
    var tail := surface_ref.split("/")[-1]
    var parts := tail.rsplit("#", true, 1)
    if parts.size() != 2 or not parts[1].is_valid_int():
        failures.append("bad_surface_ref=" + surface_ref)
        return {}
    return {"mesh_name": parts[0], "surface_index": int(parts[1])}

func _vertex_weight_map(arrays: Array, vertex_index: int) -> Dictionary:
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var bones = arrays[Mesh.ARRAY_BONES]
    var weights = arrays[Mesh.ARRAY_WEIGHTS]
    var result := {}
    if vertices.size() == 0 or bones.size() == 0 or weights.size() == 0:
        failures.append("missing_skin_arrays")
        return result
    if bones.size() != weights.size() or bones.size() % vertices.size() != 0:
        failures.append("invalid_skin_array_stride")
        return result
    var stride: int = bones.size() / vertices.size()
    for slot in range(stride):
        var i := vertex_index * stride + slot
        var w := float(weights[i])
        if w > 0.0:
            var bone := int(bones[i])
            result[bone] = float(result.get(bone, 0.0)) + w
    return result

func _weight_sum(weights: Dictionary) -> float:
    var total := 0.0
    for value in weights.values():
        total += float(value)
    return total

func _weight_l1(a: Dictionary, b: Dictionary) -> float:
    var keys := {}
    for key in a.keys(): keys[key] = true
    for key in b.keys(): keys[key] = true
    var total := 0.0
    for key in keys.keys():
        total += abs(float(a.get(key, 0.0)) - float(b.get(key, 0.0)))
    return total

func _dominant(weights: Dictionary, skeleton: Skeleton3D) -> Dictionary:
    var best_bone := -1
    var best_weight := -1.0
    for key in weights.keys():
        var w := float(weights[key])
        if w > best_weight:
            best_weight = w
            best_bone = int(key)
    var name := ""
    if skeleton != null and best_bone >= 0 and best_bone < skeleton.get_bone_count():
        name = skeleton.get_bone_name(best_bone)
    return {"bone_index": best_bone, "bone": name, "weight": best_weight}

func _weight_report(weights: Dictionary, skeleton: Skeleton3D) -> Array:
    var rows: Array = []
    for key in weights.keys():
        var bone := int(key)
        var name := ""
        if skeleton != null and bone >= 0 and bone < skeleton.get_bone_count():
            name = skeleton.get_bone_name(bone)
        rows.append({"bone_index": bone, "bone": name, "weight": float(weights[key])})
    rows.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
    return rows

func _one_ring(arrays: Array, vertex_index: int) -> Array[int]:
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var indices = arrays[Mesh.ARRAY_INDEX]
    var found := {}
    if indices.size() > 0:
        if indices.size() % 3 != 0:
            failures.append("index_count_not_triangle_multiple")
            return []
        for i in range(0, indices.size(), 3):
            var a := int(indices[i])
            var b := int(indices[i + 1])
            var c := int(indices[i + 2])
            if a == vertex_index or b == vertex_index or c == vertex_index:
                for v in [a, b, c]:
                    if v != vertex_index:
                        found[v] = true
    else:
        if vertices.size() % 3 != 0:
            failures.append("unindexed_vertex_count_not_triangle_multiple")
            return []
        for i in range(0, vertices.size(), 3):
            var tri := [i, i + 1, i + 2]
            if tri.has(vertex_index):
                for v in tri:
                    if v != vertex_index:
                        found[v] = true
    var result: Array[int] = []
    for key in found.keys(): result.append(int(key))
    result.sort()
    return result

func _neighbor_field(arrays: Array, vertex_index: int, pair_vertex: int, skeleton: Skeleton3D, weight_tol: float) -> Dictionary:
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var base_weights := _vertex_weight_map(arrays, vertex_index)
    var ring := _one_ring(arrays, vertex_index)
    var rows: Array = []
    var max_other_l1 := 0.0
    var pair_l1 := -1.0
    var dominant_flip_count := 0
    var base_dom := _dominant(base_weights, skeleton)
    for neighbor in ring:
        var nw := _vertex_weight_map(arrays, neighbor)
        var l1 := _weight_l1(base_weights, nw)
        var nd := _dominant(nw, skeleton)
        var is_pair := neighbor == pair_vertex
        if is_pair:
            pair_l1 = l1
        else:
            max_other_l1 = max(max_other_l1, l1)
        if int(nd["bone_index"]) != int(base_dom["bone_index"]):
            dominant_flip_count += 1
        rows.append({
            "vertex": neighbor,
            "is_worst_pair_endpoint": is_pair,
            "edge_length_m": vertices[vertex_index].distance_to(vertices[neighbor]),
            "weight_l1": l1,
            "dominant": nd,
            "dominant_flip": int(nd["bone_index"]) != int(base_dom["bone_index"]),
            "influences": _weight_report(nw, skeleton),
        })
    rows.sort_custom(func(a, b): return float(a["weight_l1"]) > float(b["weight_l1"]))
    return {
        "vertex": vertex_index,
        "position": [vertices[vertex_index].x, vertices[vertex_index].y, vertices[vertex_index].z],
        "weight_sum": _weight_sum(base_weights),
        "dominant": base_dom,
        "influences": _weight_report(base_weights, skeleton),
        "neighbor_count": ring.size(),
        "pair_present": pair_l1 >= 0.0,
        "pair_weight_l1": pair_l1,
        "max_other_neighbor_weight_l1": max_other_l1,
        "pair_is_local_maximum": pair_l1 >= 0.0 and pair_l1 + weight_tol >= max_other_l1,
        "dominant_flip_neighbor_count": dominant_flip_count,
        "neighbors": rows,
    }

func _total_vertices() -> int:
    var total := 0
    for node in mesh_nodes:
        if node.mesh == null: continue
        for surface in range(node.mesh.get_surface_count()):
            total += node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX].size()
    return total

func _initialize() -> void:
    var contract := _read_json(CONTRACT_PATH)
    var geometry := _read_json(GEOMETRY_PATH)
    var packed := load(TARGET_PATH) as PackedScene
    if packed == null:
        failures.append("target_scene_missing")
        _write_result({"diagnostic_state": "ONE_RING_WEIGHT_FIELD_BLOCKED", "failures": failures})
        return
    var root := packed.instantiate()
    get_root().add_child(root)
    _collect_meshes(root)

    var target: Dictionary = contract.get("target_artifact", {})
    var source: Dictionary = contract.get("geometry_artifact", {})
    var gates: Dictionary = contract.get("field_gates", {})
    if geometry.get("diagnostic_state") != source.get("expected_state"):
        failures.append("geometry_state_mismatch")
    if int(geometry.get("audited_edge_count", -1)) != int(source.get("expected_edges", -2)):
        failures.append("geometry_edge_count_mismatch")
    if int(geometry.get("triangle_adjacent_edge_count", -1)) != int(source.get("expected_triangle_adjacent_edges", -2)):
        failures.append("geometry_triangle_count_mismatch")
    if int(geometry.get("weight_divergent_split_endpoint_count", -1)) != int(source.get("expected_weight_divergent_split_endpoints", -2)):
        failures.append("geometry_split_weight_mismatch")

    var total_vertices := _total_vertices()
    if total_vertices != int(target.get("expected_vertex_total", -1)):
        failures.append("target_vertex_total=%d" % total_vertices)

    var sum_tol := float(gates.get("require_normalized_weight_sum_tolerance", 0.0002))
    var weight_eps := float(gates.get("weight_l1_epsilon", 0.000001))
    var edge_reports: Array = []
    var all_pair_local_maxima := true
    var resolved := 0

    var edges: Array = geometry.get("edges", [])
    if edges.size() != int(source.get("expected_edges", 6)):
        failures.append("geometry_edges_payload=%d" % edges.size())

    for edge in edges:
        var parts := _surface_ref_parts(str(edge.get("surface", "")))
        if parts.is_empty(): continue
        var mesh_node := _find_mesh(str(parts["mesh_name"]))
        if mesh_node == null or mesh_node.mesh == null: continue
        var surface_index := int(parts["surface_index"])
        if surface_index < 0 or surface_index >= mesh_node.mesh.get_surface_count():
            failures.append("surface_index_out_of_range=" + str(edge.get("surface", "")))
            continue
        var arrays := mesh_node.mesh.surface_get_arrays(surface_index)
        var vertices = arrays[Mesh.ARRAY_VERTEX]
        var a := int(edge.get("vertex_a", -1))
        var b := int(edge.get("vertex_b", -1))
        if a < 0 or b < 0 or a >= vertices.size() or b >= vertices.size():
            failures.append("vertex_index_out_of_range=%s:%d:%d" % [str(edge.get("surface", "")), a, b])
            continue
        var skeleton := mesh_node.get_node_or_null(mesh_node.skeleton) as Skeleton3D
        var field_a := _neighbor_field(arrays, a, b, skeleton, weight_eps)
        var field_b := _neighbor_field(arrays, b, a, skeleton, weight_eps)
        if bool(gates.get("require_both_endpoints_have_neighbors", true)) and (int(field_a["neighbor_count"]) == 0 or int(field_b["neighbor_count"]) == 0):
            failures.append("empty_one_ring=%s:%d:%d" % [str(edge.get("surface", "")), a, b])
        if bool(gates.get("require_pair_present_in_mutual_one_ring", true)) and (not bool(field_a["pair_present"]) or not bool(field_b["pair_present"])):
            failures.append("pair_missing_from_mutual_one_ring=%s:%d:%d" % [str(edge.get("surface", "")), a, b])
        if abs(float(field_a["weight_sum"]) - 1.0) > sum_tol:
            failures.append("weight_sum_a=%s:%d:%f" % [str(edge.get("surface", "")), a, float(field_a["weight_sum"])])
        if abs(float(field_b["weight_sum"]) - 1.0) > sum_tol:
            failures.append("weight_sum_b=%s:%d:%f" % [str(edge.get("surface", "")), b, float(field_b["weight_sum"])])
        var measured_pair_l1 := _weight_l1(_vertex_weight_map(arrays, a), _vertex_weight_map(arrays, b))
        var prior_pair_l1 := float(edge.get("endpoint_distribution_l1_from_prior", -1.0))
        if prior_pair_l1 < 0.0 or abs(measured_pair_l1 - prior_pair_l1) > 0.0002:
            failures.append("pair_l1_drift=%s:%d:%d:%f:%f" % [str(edge.get("surface", "")), a, b, measured_pair_l1, prior_pair_l1])
        var pair_local := bool(field_a["pair_is_local_maximum"]) and bool(field_b["pair_is_local_maximum"])
        all_pair_local_maxima = all_pair_local_maxima and pair_local
        resolved += 1
        edge_reports.append({
            "surface": edge.get("surface"),
            "family": edge.get("family"),
            "vertex_a": a,
            "vertex_b": b,
            "case_count": edge.get("case_count"),
            "rest_edge_length_m": edge.get("rest_edge_length_m"),
            "pair_weight_l1": measured_pair_l1,
            "pair_is_bilateral_local_maximum": pair_local,
            "endpoint_a": field_a,
            "endpoint_b": field_b,
        })

    if bool(gates.get("require_all_six_edges_resolved", true)) and resolved != int(source.get("expected_edges", 6)):
        failures.append("resolved_edge_count=%d" % resolved)

    var state := "ONE_RING_WEIGHT_FIELD_BLOCKED"
    var next_axis := "FIX_ONE_RING_AUDIT_BEFORE_REWEIGHT"
    if failures.is_empty():
        if all_pair_local_maxima:
            state = "ONE_RING_LOCAL_WEIGHT_CLIFFS_CONFIRMED"
            next_axis = str(contract.get("next_safe_axis_if_all_pair_local_maxima"))
        else:
            state = "ONE_RING_BROADER_WEIGHT_FIELD_CONFIRMED"
            next_axis = str(contract.get("next_safe_axis_if_broader_field"))

    _write_result({
        "diagnostic_state": state,
        "candidate_variant": int(contract.get("candidate_variant", -1)),
        "godot_version": Engine.get_version_info().get("string", ""),
        "target_vertex_total": total_vertices,
        "mesh_instance_count": mesh_nodes.size(),
        "audited_edge_count": edge_reports.size(),
        "all_pair_bilateral_local_maxima": all_pair_local_maxima,
        "edges": edge_reports,
        "failures": failures,
        "rails": contract.get("rails", {}),
        "next_safe_axis": next_axis,
        "production_activation_allowed": false,
        "visual_approval_allowed": false
    })
