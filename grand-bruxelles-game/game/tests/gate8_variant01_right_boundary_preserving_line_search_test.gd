extends SceneTree

const TARGET_PATH := "res://assets/npc_gate_01.glb"
const CONTRACT_PATH := "res://contract.json"
const OUT_PATH := "res://right-boundary-preserving-line-search-result.json"

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

func _surface_parts(surface_ref: String) -> Dictionary:
    var tail := surface_ref.split("/")[-1]
    var parts := tail.rsplit("#", true, 1)
    if parts.size() != 2 or not parts[1].is_valid_int():
        failures.append("bad_surface_ref=" + surface_ref)
        return {}
    return {"mesh_name": parts[0], "surface_index": int(parts[1])}

func _find_mesh(name: String) -> MeshInstance3D:
    var matches: Array[MeshInstance3D] = []
    for node in mesh_nodes:
        if node.name == name:
            matches.append(node)
    if matches.size() != 1:
        failures.append("mesh_name_resolution_%s=%d" % [name, matches.size()])
        return null
    return matches[0]

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
    for value in w.values():
        total += float(value)
    return total

func _normalize(w: Dictionary) -> Dictionary:
    var total := _sum(w)
    if total <= 0.000001:
        failures.append("zero_weight_vector")
        return {}
    var out := {}
    for key in w.keys():
        var value := float(w[key]) / total
        if value > 0.000000001:
            out[key] = value
    return out

func _l1(a: Dictionary, b: Dictionary) -> float:
    var keys := {}
    for k in a.keys(): keys[k] = true
    for k in b.keys(): keys[k] = true
    var total := 0.0
    for k in keys.keys():
        total += abs(float(a.get(k, 0.0)) - float(b.get(k, 0.0)))
    return total

func _blend(a: Dictionary, b: Dictionary, alpha: float) -> Dictionary:
    var keys := {}
    for k in a.keys(): keys[k] = true
    for k in b.keys(): keys[k] = true
    var out := {}
    for k in keys.keys():
        var value := (1.0 - alpha) * float(a.get(k, 0.0)) + alpha * float(b.get(k, 0.0))
        if value > 0.000000001:
            out[k] = value
    return _normalize(out)

func _average(maps: Array) -> Dictionary:
    var out := {}
    if maps.is_empty():
        failures.append("empty_consensus")
        return out
    for m in maps:
        for k in m.keys():
            out[k] = float(out.get(k, 0.0)) + float(m[k]) / float(maps.size())
    return _normalize(out)

func _one_ring(arrays: Array, center: int) -> Array[int]:
    var indices = arrays[Mesh.ARRAY_INDEX]
    var found := {}
    if indices.size() == 0 or indices.size() % 3 != 0:
        failures.append("indexed_triangle_surface_required")
        return []
    for i in range(0, indices.size(), 3):
        var tri := [int(indices[i]), int(indices[i + 1]), int(indices[i + 2])]
        if tri.has(center):
            for v in tri:
                if v != center:
                    found[v] = true
    var out: Array[int] = []
    for k in found.keys(): out.append(int(k))
    out.sort()
    return out

func _boundary_edges(arrays: Array, cluster: Dictionary) -> Array:
    var indices = arrays[Mesh.ARRAY_INDEX]
    var seen := {}
    var out: Array = []
    for i in range(0, indices.size(), 3):
        var tri := [int(indices[i]), int(indices[i + 1]), int(indices[i + 2])]
        for pair in [[tri[0], tri[1]], [tri[1], tri[2]], [tri[2], tri[0]]]:
            var a := int(pair[0])
            var b := int(pair[1])
            var ac := cluster.has(a)
            var bc := cluster.has(b)
            if ac == bc: continue
            var inside: int = a if ac else b
            var outside: int = b if ac else a
            var lo := min(inside, outside)
            var hi := max(inside, outside)
            var key := "%d:%d" % [lo, hi]
            if seen.has(key): continue
            seen[key] = true
            out.append({"inside": inside, "outside": outside})
    out.sort_custom(func(a, b): return int(a["inside"]) < int(b["inside"]) or (int(a["inside"]) == int(b["inside"]) and int(a["outside"]) < int(b["outside"])))
    return out

func _total_vertices() -> int:
    var total := 0
    for node in mesh_nodes:
        if node.mesh == null: continue
        for s in range(node.mesh.get_surface_count()):
            total += node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
    return total

func _write(result: Dictionary) -> void:
    var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
    if f == null:
        push_error("cannot_write_result")
        quit(2)
        return
    f.store_string(JSON.stringify(result, "  ", false))
    f.close()
    print(JSON.stringify(result))
    quit(0 if failures.is_empty() else 1)

func _initialize() -> void:
    var contract := _json(CONTRACT_PATH)
    var packed := load(TARGET_PATH) as PackedScene
    if packed == null:
        failures.append("target_scene_missing")
        _write({"diagnostic_state": "RIGHT_BOUNDARY_PRESERVING_LINE_SEARCH_BLOCKED", "failures": failures})
        return
    var root := packed.instantiate()
    get_root().add_child(root)
    _collect(root)
    var target: Dictionary = contract.get("target", {})
    var total := _total_vertices()
    if total != int(target.get("expected_vertex_total", -1)):
        failures.append("target_vertex_total=%d" % total)
    var parts := _surface_parts(str(contract.get("surface", "")))
    var mesh := _find_mesh(str(parts.get("mesh_name", "")))
    if mesh == null or mesh.mesh == null:
        _write({"diagnostic_state": "RIGHT_BOUNDARY_PRESERVING_LINE_SEARCH_BLOCKED", "failures": failures})
        return
    var surface_index := int(parts.get("surface_index", -1))
    if surface_index < 0 or surface_index >= mesh.mesh.get_surface_count():
        failures.append("surface_index_oob")
        _write({"diagnostic_state": "RIGHT_BOUNDARY_PRESERVING_LINE_SEARCH_BLOCKED", "failures": failures})
        return
    var arrays := mesh.mesh.surface_get_arrays(surface_index)
    var cluster := {}
    for v in contract.get("cluster_vertices", []): cluster[int(v)] = true
    if cluster.size() != 4: failures.append("cluster_count=%d" % cluster.size())
    var anchor := int(contract.get("coherent_anchor", -1))
    var anchor_w := _weights(arrays, anchor)
    var consensus_maps: Array = [anchor_w]
    var accepted_neighbors: Array[int] = []
    for n in _one_ring(arrays, anchor):
        if cluster.has(n): continue
        var nw := _weights(arrays, n)
        if _l1(anchor_w, nw) <= float(contract.get("consensus_neighbor_l1_max", 0.10)):
            consensus_maps.append(nw)
            accepted_neighbors.append(n)
    if consensus_maps.size() < 2: failures.append("consensus_too_small")
    var consensus := _average(consensus_maps)
    var boundary := _boundary_edges(arrays, cluster)
    if boundary.size() != int(contract.get("boundary_evidence", {}).get("expected_boundary_edge_count", -1)):
        failures.append("boundary_edge_count=%d" % boundary.size())
    var target_edge: Array = contract.get("target_edge", [])
    var original_target_l1 := -1.0
    for e in boundary:
        var inside := int(e["inside"])
        var outside := int(e["outside"])
        if target_edge.size() == 2 and ((inside == int(target_edge[0]) and outside == int(target_edge[1])) or (inside == int(target_edge[1]) and outside == int(target_edge[0]))):
            original_target_l1 = _l1(_weights(arrays, inside), _weights(arrays, outside))
    if original_target_l1 < 0.0: failures.append("target_edge_not_on_boundary")
    var ls: Dictionary = contract.get("line_search", {})
    var step := float(ls.get("alpha_step", 0.01))
    var tolerance := float(ls.get("boundary_l1_worsening_tolerance", 0.000001))
    var min_improvement := float(ls.get("minimum_target_edge_improvement", 0.001))
    if step <= 0.0 or step > 1.0: failures.append("invalid_alpha_step")
    var best_alpha := 0.0
    var best_target_l1 := original_target_l1
    var best_rows: Array = []
    var tested: Array = []
    if failures.is_empty():
        var count := int(round(1.0 / step))
        for index in range(count, 0, -1):
            var alpha := min(1.0, float(index) * step)
            var rows: Array = []
            var boundary_safe := true
            var target_l1: float = original_target_l1
            var max_worsening: float = -INF
            for e in boundary:
                var inside := int(e["inside"])
                var outside := int(e["outside"])
                var original_inside := _weights(arrays, inside)
                var outside_w := _weights(arrays, outside)
                var candidate_inside := _blend(original_inside, consensus, alpha)
                var original_l1 := _l1(original_inside, outside_w)
                var candidate_l1 := _l1(candidate_inside, outside_w)
                var worsening := candidate_l1 - original_l1
                max_worsening = max(max_worsening, worsening)
                if worsening > tolerance: boundary_safe = false
                var is_target := target_edge.size() == 2 and ((inside == int(target_edge[0]) and outside == int(target_edge[1])) or (inside == int(target_edge[1]) and outside == int(target_edge[0])))
                if is_target: target_l1 = candidate_l1
                rows.append({"inside": inside, "outside": outside, "original_l1": original_l1, "candidate_l1": candidate_l1, "worsening": worsening, "target_edge": is_target})
            var improvement := original_target_l1 - target_l1
            var useful := boundary_safe and improvement >= min_improvement
            tested.append({"alpha": alpha, "boundary_safe": boundary_safe, "target_edge_improvement": improvement, "max_boundary_worsening": max_worsening, "useful": useful})
            if useful:
                best_alpha = alpha
                best_target_l1 = target_l1
                best_rows = rows
                break
    var minimum_useful_alpha := float(ls.get("minimum_useful_alpha", 0.05))
    var state := "RIGHT_BOUNDARY_PRESERVING_REWEIGHT_INFEASIBLE"
    var next_axis := str(contract.get("next_if_infeasible", "STOP"))
    if best_alpha >= minimum_useful_alpha:
        state = "RIGHT_BOUNDARY_PRESERVING_REWEIGHT_FEASIBLE"
        next_axis = str(contract.get("next_if_feasible", "STOP"))
    _write({
        "format": "grand-bruxelles-gate8-variant01-right-boundary-preserving-line-search-result-v1",
        "diagnostic_state": state,
        "candidate_variant": int(contract.get("candidate_variant", -1)),
        "godot_version": Engine.get_version_info().get("string", ""),
        "target_vertex_total": total,
        "surface": contract.get("surface"),
        "cluster_vertices": cluster.keys(),
        "coherent_anchor": anchor,
        "accepted_consensus_neighbors": accepted_neighbors,
        "boundary_edge_count": boundary.size(),
        "original_target_edge_l1": original_target_l1,
        "best_alpha": best_alpha,
        "best_target_edge_l1": best_target_l1,
        "best_target_edge_improvement": original_target_l1 - best_target_l1,
        "minimum_useful_alpha": minimum_useful_alpha,
        "tested_alphas": tested,
        "best_boundary_rows": best_rows,
        "failures": failures,
        "rails": contract.get("rails", {}),
        "production_activation_allowed": false,
        "visual_approval_allowed": false,
        "next_safe_axis": next_axis
    })
