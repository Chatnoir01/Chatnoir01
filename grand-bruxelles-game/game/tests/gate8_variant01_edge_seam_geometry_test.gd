extends SceneTree

const TARGET_PATH := "res://assets/npc_gate_01.glb"
const COVERAGE_PATH := "res://evidence/worst-edge-coverage-result.json"
const CONTRACT_PATH := "res://contract.json"
const OUT_PATH := "res://gate8_variant01_edge_seam_geometry_result.json"

var failures: Array[String] = []
var mesh_nodes: Array[MeshInstance3D] = []

func _read_json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        failures.append("missing_json=" + path)
        return {}
    var text := FileAccess.get_file_as_string(path)
    var parsed = JSON.parse_string(text)
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

func _weight_l1(a: Dictionary, b: Dictionary) -> float:
    var keys := {}
    for key in a.keys():
        keys[key] = true
    for key in b.keys():
        keys[key] = true
    var total := 0.0
    for key in keys.keys():
        total += abs(float(a.get(key, 0.0)) - float(b.get(key, 0.0)))
    return total

func _weight_report(weights: Dictionary, skeleton: Skeleton3D) -> Array:
    var rows: Array = []
    for bone in weights.keys():
        var bone_index := int(bone)
        var bone_name := ""
        if skeleton != null and bone_index >= 0 and bone_index < skeleton.get_bone_count():
            bone_name = skeleton.get_bone_name(bone_index)
        rows.append({"bone_index": bone_index, "bone": bone_name, "weight": float(weights[bone])})
    rows.sort_custom(func(a, b): return float(a["weight"]) > float(b["weight"]))
    return rows

func _triangle_adjacency_count(arrays: Array, a: int, b: int) -> int:
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var indices = arrays[Mesh.ARRAY_INDEX]
    var count := 0
    if indices.size() > 0:
        if indices.size() % 3 != 0:
            failures.append("index_count_not_triangle_multiple")
            return 0
        for i in range(0, indices.size(), 3):
            var tri := [int(indices[i]), int(indices[i + 1]), int(indices[i + 2])]
            if tri.has(a) and tri.has(b):
                count += 1
    else:
        if vertices.size() % 3 != 0:
            failures.append("unindexed_vertex_count_not_triangle_multiple")
            return 0
        for i in range(0, vertices.size(), 3):
            var tri := [i, i + 1, i + 2]
            if tri.has(a) and tri.has(b):
                count += 1
    return count

func _coincident_duplicates(arrays: Array, vertex_index: int, tolerance: float, weight_tol: float, skeleton: Skeleton3D) -> Dictionary:
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var p: Vector3 = vertices[vertex_index]
    var base_weights := _vertex_weight_map(arrays, vertex_index)
    var rows: Array = []
    var divergent := 0
    var max_l1 := 0.0
    for other in range(vertices.size()):
        if other == vertex_index:
            continue
        var distance := p.distance_to(vertices[other])
        if distance <= tolerance:
            var other_weights := _vertex_weight_map(arrays, other)
            var l1 := _weight_l1(base_weights, other_weights)
            max_l1 = max(max_l1, l1)
            if l1 > weight_tol:
                divergent += 1
            rows.append({
                "vertex": other,
                "distance_m": distance,
                "weight_l1": l1,
                "weight_divergent": l1 > weight_tol,
                "influences": _weight_report(other_weights, skeleton),
            })
    return {
        "vertex": vertex_index,
        "position": [p.x, p.y, p.z],
        "influences": _weight_report(base_weights, skeleton),
        "coincident_duplicate_count": rows.size(),
        "weight_divergent_duplicate_count": divergent,
        "max_duplicate_weight_l1": max_l1,
        "duplicates": rows,
    }

func _total_vertices() -> int:
    var total := 0
    for node in mesh_nodes:
        if node.mesh == null:
            continue
        for surface in range(node.mesh.get_surface_count()):
            var arrays := node.mesh.surface_get_arrays(surface)
            total += arrays[Mesh.ARRAY_VERTEX].size()
    return total

func _initialize() -> void:
    var contract := _read_json(CONTRACT_PATH)
    var coverage := _read_json(COVERAGE_PATH)
    var packed := load(TARGET_PATH) as PackedScene
    if packed == null:
        failures.append("target_scene_missing")
        _write_result({"diagnostic_state": "EDGE_SEAM_GEOMETRY_BLOCKED", "failures": failures})
        return

    var root := packed.instantiate()
    get_root().add_child(root)
    _collect_meshes(root)

    var target: Dictionary = contract.get("target_artifact", {})
    var cov: Dictionary = contract.get("coverage_artifact", {})
    var gates: Dictionary = contract.get("geometry_gates", {})
    if coverage.get("diagnostic_state") != cov.get("expected_state"):
        failures.append("coverage_state_mismatch")
    if int(coverage.get("unique_worst_edges", -1)) != int(cov.get("expected_unique_edges", -2)):
        failures.append("coverage_edge_count_mismatch")
    if int(coverage.get("unique_vertices", -1)) != int(cov.get("expected_unique_vertices", -2)):
        failures.append("coverage_vertex_count_mismatch")
    if int(coverage.get("covered_blocked_case_count", -1)) != int(cov.get("expected_covered_cases", -2)):
        failures.append("coverage_case_count_mismatch")

    var total_vertices := _total_vertices()
    if total_vertices != int(target.get("expected_vertex_total", -1)):
        failures.append("target_vertex_total=%d" % total_vertices)

    var position_tol := float(gates.get("coincident_position_tolerance_m", 0.000001))
    var weight_tol := float(gates.get("weight_vector_l1_difference_tolerance", 0.0001))
    var evidence: Array = []
    var adjacent_edges := 0
    var split_duplicate_endpoints := 0
    var weight_divergent_split_endpoints := 0
    var pair_coincident_count := 0

    var edges: Array = coverage.get("edges", [])
    if edges.size() != int(cov.get("expected_unique_edges", 6)):
        failures.append("edge_evidence_count=%d" % edges.size())

    for edge in edges:
        var parts := _surface_ref_parts(str(edge.get("surface", "")))
        if parts.is_empty():
            continue
        var mesh_node := _find_mesh(str(parts["mesh_name"]))
        if mesh_node == null or mesh_node.mesh == null:
            continue
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
        var triangle_count := _triangle_adjacency_count(arrays, a, b)
        var edge_length: float = vertices[a].distance_to(vertices[b])
        var pair_coincident := edge_length <= position_tol
        if triangle_count > 0:
            adjacent_edges += 1
        if pair_coincident:
            pair_coincident_count += 1
        if bool(gates.get("require_all_pairs_triangle_adjacent", true)) and triangle_count == 0:
            failures.append("not_triangle_adjacent=%s:%d:%d" % [str(edge.get("surface", "")), a, b])
        if bool(gates.get("require_nonzero_rest_edge_length", true)) and pair_coincident:
            failures.append("worst_pair_is_coincident=%s:%d:%d" % [str(edge.get("surface", "")), a, b])

        var endpoint_a := _coincident_duplicates(arrays, a, position_tol, weight_tol, skeleton)
        var endpoint_b := _coincident_duplicates(arrays, b, position_tol, weight_tol, skeleton)
        for endpoint in [endpoint_a, endpoint_b]:
            if int(endpoint["coincident_duplicate_count"]) > 0:
                split_duplicate_endpoints += 1
            if int(endpoint["weight_divergent_duplicate_count"]) > 0:
                weight_divergent_split_endpoints += 1

        evidence.append({
            "surface": edge.get("surface"),
            "family": edge.get("family"),
            "vertex_a": a,
            "vertex_b": b,
            "case_count": edge.get("case_count"),
            "triangle_adjacency_count": triangle_count,
            "triangle_adjacent": triangle_count > 0,
            "rest_edge_length_m": edge_length,
            "pair_coincident": pair_coincident,
            "endpoint_distribution_l1_from_prior": edge.get("endpoint_distribution_l1"),
            "endpoint_a": endpoint_a,
            "endpoint_b": endpoint_b,
        })

    var state := "EDGE_SEAM_GEOMETRY_BLOCKED"
    var next_axis := "FIX_GEOMETRY_AUDIT_BEFORE_REWEIGHT"
    if failures.is_empty():
        if weight_divergent_split_endpoints > 0:
            state = "TRUE_EDGES_WITH_WEIGHT_DIVERGENT_SEAM_SPLITS_CONFIRMED"
            next_axis = str(contract.get("next_safe_axis_if_split_weights_found"))
        else:
            state = "TRUE_EDGES_NO_WEIGHT_DIVERGENT_SEAM_SPLITS"
            next_axis = str(contract.get("next_safe_axis_if_no_split_weights_found"))

    var result := {
        "diagnostic_state": state,
        "candidate_variant": int(contract.get("candidate_variant", -1)),
        "godot_version": Engine.get_version_info().get("string", ""),
        "target_vertex_total": total_vertices,
        "mesh_instance_count": mesh_nodes.size(),
        "audited_edge_count": evidence.size(),
        "triangle_adjacent_edge_count": adjacent_edges,
        "pair_coincident_count": pair_coincident_count,
        "split_duplicate_endpoint_count": split_duplicate_endpoints,
        "weight_divergent_split_endpoint_count": weight_divergent_split_endpoints,
        "coincident_position_tolerance_m": position_tol,
        "weight_vector_l1_difference_tolerance": weight_tol,
        "edges": evidence,
        "failures": failures,
        "rails": contract.get("rails", {}),
        "next_safe_axis": next_axis,
        "production_activation_allowed": false,
        "visual_approval_allowed": false,
    }
    _write_result(result)
