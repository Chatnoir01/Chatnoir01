extends SceneTree

const TARGET_PATH := "res://assets/npc_gate_01.glb"
const CONTRACT_PATH := "res://contract.json"
const RESIDUAL_PATH := "res://evidence/residual.json"
const OUT_PATH := "res://right-cluster-boundary-one-ring-result.json"

var failures: Array[String] = []
var mesh_nodes: Array[MeshInstance3D] = []

func _json(path: String) -> Dictionary:
    if not FileAccess.file_exists(path):
        failures.append("missing_json=" + path)
        return {}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
    if not (parsed is Dictionary):
        failures.append("invalid_json=" + path)
        return {}
    return parsed

func _collect(node: Node) -> void:
    if node is MeshInstance3D:
        mesh_nodes.append(node as MeshInstance3D)
    for child in node.get_children():
        _collect(child)

func _find_mesh(name: String) -> MeshInstance3D:
    var matches: Array[MeshInstance3D] = []
    for node in mesh_nodes:
        if node.name == name:
            matches.append(node)
    if matches.size() != 1:
        failures.append("mesh_name_resolution_%s=%d" % [name, matches.size()])
        return null
    return matches[0]

func _surface_parts(surface_ref: String) -> Dictionary:
    var tail := surface_ref.split("/")[-1]
    var parts := tail.rsplit("#", true, 1)
    if parts.size() != 2 or not parts[1].is_valid_int():
        failures.append("bad_surface_ref=" + surface_ref)
        return {}
    return {"mesh_name": parts[0], "surface_index": int(parts[1])}

func _weights(arrays: Array, vi: int) -> Dictionary:
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var bones = arrays[Mesh.ARRAY_BONES]
    var weights = arrays[Mesh.ARRAY_WEIGHTS]
    var out := {}
    if vi < 0 or vi >= vertices.size():
        failures.append("vertex_oob=%d" % vi)
        return out
    if bones.size() == 0 or weights.size() == 0 or bones.size() != weights.size() or bones.size() % vertices.size() != 0:
        failures.append("invalid_skin_arrays")
        return out
    var stride: int = bones.size() / vertices.size()
    for slot in range(stride):
        var idx := vi * stride + slot
        var w := float(weights[idx])
        if w > 0.0:
            var bone := int(bones[idx])
            out[bone] = float(out.get(bone, 0.0)) + w
    return out

func _sum(w: Dictionary) -> float:
    var total := 0.0
    for x in w.values(): total += float(x)
    return total

func _l1(a: Dictionary, b: Dictionary) -> float:
    var keys := {}
    for k in a.keys(): keys[k] = true
    for k in b.keys(): keys[k] = true
    var total := 0.0
    for k in keys.keys(): total += abs(float(a.get(k, 0.0)) - float(b.get(k, 0.0)))
    return total

func _average(maps: Array) -> Dictionary:
    var out := {}
    for m in maps:
        for k in m.keys(): out[k] = float(out.get(k, 0.0)) + float(m[k]) / float(maps.size())
    var total := _sum(out)
    if total <= 0.000001:
        failures.append("zero_consensus")
        return {}
    for k in out.keys(): out[k] = float(out[k]) / total
    return out

func _one_ring(arrays: Array, center: int) -> Array[int]:
    var indices = arrays[Mesh.ARRAY_INDEX]
    var found := {}
    if indices.size() == 0 or indices.size() % 3 != 0:
        failures.append("indexed_triangle_surface_required")
        return []
    for i in range(0, indices.size(), 3):
        var tri := [int(indices[i]), int(indices[i+1]), int(indices[i+2])]
        if tri.has(center):
            for v in tri:
                if v != center: found[v] = true
    var out: Array[int] = []
    for k in found.keys(): out.append(int(k))
    out.sort()
    return out

func _boundary_edges(arrays: Array, cluster: Dictionary) -> Array:
    var indices = arrays[Mesh.ARRAY_INDEX]
    var seen := {}
    var out: Array = []
    for i in range(0, indices.size(), 3):
        var tri := [int(indices[i]), int(indices[i+1]), int(indices[i+2])]
        for pair in [[tri[0],tri[1]],[tri[1],tri[2]],[tri[2],tri[0]]]:
            var a := int(pair[0]); var b := int(pair[1])
            var ac := cluster.has(a); var bc := cluster.has(b)
            if ac == bc: continue
            var inside := a if ac else b
            var outside := b if ac else a
            var key := "%d:%d" % [inside, outside]
            if seen.has(key): continue
            seen[key] = true
            out.append({"inside":inside,"outside":outside,"triangle":int(i/3)})
    out.sort_custom(func(a,b): return int(a["inside"]) < int(b["inside"]) or (int(a["inside"]) == int(b["inside"]) and int(a["outside"]) < int(b["outside"])))
    return out

func _total_vertices() -> int:
    var total := 0
    for node in mesh_nodes:
        if node.mesh == null: continue
        for s in range(node.mesh.get_surface_count()): total += node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
    return total

func _write(result: Dictionary) -> void:
    var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
    if f == null:
        push_error("cannot_write_result")
        quit(2)
        return
    f.store_string(JSON.stringify(result, "  ", false)); f.close()
    print(JSON.stringify(result))
    quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
    var contract := _json(CONTRACT_PATH)
    var residual := _json(RESIDUAL_PATH)
    var packed := load(TARGET_PATH) as PackedScene
    if packed == null:
        failures.append("target_scene_missing")
        _write({"diagnostic_state":"RIGHT_CLUSTER_BOUNDARY_BLOCKED","failures":failures})
        return
    var root := packed.instantiate(); get_root().add_child(root); _collect(root)
    var target: Dictionary = contract.get("target_artifact", {})
    var rc: Dictionary = contract.get("right_cluster", {})
    var gates: Dictionary = contract.get("gates", {})
    var expected_residual: Dictionary = contract.get("residual_artifact", {})
    if residual.get("diagnostic_state") != expected_residual.get("expected_state"): failures.append("residual_state_drift")
    var rr: Dictionary = residual.get("right", {})
    if rr.get("candidate_worst_edge") != expected_residual.get("expected_worst_edge"): failures.append("residual_worst_edge_drift")
    if int(rr.get("modified_vertex_on_new_worst_edge", -1)) != int(expected_residual.get("expected_modified_vertex", -2)): failures.append("residual_modified_vertex_drift")
    var total := _total_vertices()
    if total != int(target.get("expected_vertex_total", -1)): failures.append("target_vertex_total=%d" % total)
    var parts := _surface_parts(str(rc.get("surface", "")))
    var mesh := _find_mesh(str(parts.get("mesh_name", "")))
    if mesh == null or mesh.mesh == null:
        _write({"diagnostic_state":"RIGHT_CLUSTER_BOUNDARY_BLOCKED","failures":failures})
        return
    var s := int(parts.get("surface_index", -1))
    if s < 0 or s >= mesh.mesh.get_surface_count(): failures.append("surface_index_oob")
    if not failures.is_empty():
        _write({"diagnostic_state":"RIGHT_CLUSTER_BOUNDARY_BLOCKED","failures":failures})
        return
    var arrays := mesh.mesh.surface_get_arrays(s)
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var cluster := {}
    for v in rc.get("modified_vertices", []): cluster[int(v)] = true
    if cluster.size() != int(gates.get("require_modified_vertex_count", -1)): failures.append("cluster_count=%d" % cluster.size())
    for v in cluster.keys():
        if int(v) < 0 or int(v) >= vertices.size(): failures.append("cluster_vertex_oob=%d" % int(v))
    var anchor := int(rc.get("coherent_anchor", -1))
    var anchor_w := _weights(arrays, anchor)
    var consensus_maps: Array = [anchor_w]
    var accepted_neighbors: Array[int] = []
    var anchor_ring := _one_ring(arrays, anchor)
    for n in anchor_ring:
        if cluster.has(n): continue
        var nw := _weights(arrays, n)
        if _l1(anchor_w, nw) <= 0.10:
            consensus_maps.append(nw); accepted_neighbors.append(n)
    if consensus_maps.size() < 2: failures.append("consensus_too_small")
    var consensus := _average(consensus_maps)
    var tol := float(gates.get("require_weight_sum_tolerance", 0.001))
    if abs(_sum(consensus) - 1.0) > tol: failures.append("consensus_weight_sum=%f" % _sum(consensus))
    var boundary := _boundary_edges(arrays, cluster)
    if bool(gates.get("require_nonempty_boundary_edges", true)) and boundary.is_empty(): failures.append("empty_boundary")
    var rows: Array = []
    var max_candidate_l1 := -1.0
    var max_candidate_edge: Array = []
    var high_count := 0
    var worst_found := false
    var expected_edge: Array = expected_residual.get("expected_worst_edge", [])
    for e in boundary:
        var inside := int(e["inside"]); var outside := int(e["outside"])
        var outside_w := _weights(arrays, outside)
        var inside_original_w := _weights(arrays, inside)
        var candidate_l1 := _l1(consensus, outside_w)
        var original_l1 := _l1(inside_original_w, outside_w)
        var is_expected := expected_edge.size() == 2 and ((inside == int(expected_edge[0]) and outside == int(expected_edge[1])) or (inside == int(expected_edge[1]) and outside == int(expected_edge[0])))
        if is_expected: worst_found = true
        if candidate_l1 > max_candidate_l1:
            max_candidate_l1 = candidate_l1; max_candidate_edge = [inside, outside]
        if candidate_l1 >= float(gates.get("high_l1_threshold", 0.75)): high_count += 1
        rows.append({"inside":inside,"outside":outside,"triangle":e["triangle"],"original_weight_l1":original_l1,"candidate_weight_l1":candidate_l1,"expected_residual_worst_edge":is_expected})
    rows.sort_custom(func(a,b): return float(a["candidate_weight_l1"]) > float(b["candidate_weight_l1"]))
    if bool(gates.get("require_new_worst_edge_on_boundary", true)) and not worst_found: failures.append("residual_worst_edge_not_boundary")
    var state := "RIGHT_CLUSTER_BOUNDARY_TOPOLOGY_DRIFT"
    var next_axis := str(contract.get("next_safe_axis_if_topology_drift", "STOP"))
    if failures.is_empty():
        if high_count > 0:
            state = "RIGHT_CLUSTER_BOUNDARY_WEIGHT_CLIFF_CONFIRMED"
            next_axis = str(contract.get("next_safe_axis_if_boundary_cliff_confirmed", "STOP"))
        else:
            state = "RIGHT_CLUSTER_BOUNDARY_FIELD_BROAD_WITHOUT_HIGH_CLIFF"
            next_axis = str(contract.get("next_safe_axis_if_boundary_field_broad", "STOP"))
    _write({
        "format":"grand-bruxelles-gate8-variant01-right-cluster-boundary-one-ring-result-v1",
        "diagnostic_state":state,
        "candidate_variant":int(contract.get("candidate_variant", -1)),
        "godot_version":Engine.get_version_info().get("string", ""),
        "target_vertex_total":total,
        "surface":rc.get("surface"),
        "cluster_vertices":cluster.keys(),
        "coherent_anchor":anchor,
        "accepted_consensus_neighbors":accepted_neighbors,
        "boundary_edge_count":boundary.size(),
        "high_candidate_l1_boundary_edge_count":high_count,
        "max_candidate_l1":max_candidate_l1,
        "max_candidate_l1_edge":max_candidate_edge,
        "expected_residual_worst_edge_found_on_boundary":worst_found,
        "boundary_edges":rows,
        "failures":failures,
        "rails":contract.get("rails", {}),
        "production_activation_allowed":false,
        "visual_approval_allowed":false,
        "next_safe_axis":next_axis
    })
