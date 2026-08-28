extends SceneTree

const TARGET_PATH := "res://assets/npc_gate_01.glb"
const ONE_RING_PATH := "res://evidence/one-ring-result.json"
const CONTRACT_PATH := "res://contract.json"
const OUT_PATH := "res://gate8_variant01_shoulder_two_ring_field_result.json"

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

func _surface_parts(surface_ref: String) -> Dictionary:
    var tail := surface_ref.split("/")[-1]
    var parts := tail.rsplit("#", true, 1)
    if parts.size() != 2 or not parts[1].is_valid_int():
        failures.append("bad_surface_ref=" + surface_ref)
        return {}
    return {"mesh_name": parts[0], "surface_index": int(parts[1])}

func _one_ring(arrays: Array, vertex_index: int) -> Array[int]:
    var indices = arrays[Mesh.ARRAY_INDEX]
    var vertices = arrays[Mesh.ARRAY_VERTEX]
    var found := {}
    if indices.size() > 0:
        if indices.size() % 3 != 0:
            failures.append("index_count_not_triangle_multiple")
            return []
        for i in range(0, indices.size(), 3):
            var tri := [int(indices[i]), int(indices[i + 1]), int(indices[i + 2])]
            if tri.has(vertex_index):
                for v in tri:
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
    var out: Array[int] = []
    for key in found.keys(): out.append(int(key))
    out.sort()
    return out

func _exact_two_ring(arrays: Array, center: int) -> Array[int]:
    var ring1 := _one_ring(arrays, center)
    var seen := {center: true}
    for v in ring1: seen[v] = true
    var ring2 := {}
    for v in ring1:
        for n in _one_ring(arrays, v):
            if not seen.has(n): ring2[n] = true
    var out: Array[int] = []
    for key in ring2.keys(): out.append(int(key))
    out.sort()
    return out

func _weights(arrays: Array, vertex_index: int) -> Dictionary:
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

func _weight_sum(w: Dictionary) -> float:
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

func _dominant(w: Dictionary, skeleton: Skeleton3D) -> Dictionary:
    var best := -1
    var best_w := -1.0
    for k in w.keys():
        var x := float(w[k])
        if x > best_w:
            best_w = x
            best = int(k)
    return {"bone_index": best, "bone": skeleton.get_bone_name(best) if skeleton != null and best >= 0 and best < skeleton.get_bone_count() else "", "weight": best_w}

func _two_ring_report(arrays: Array, broad: int, coherent: int, skeleton: Skeleton3D, gates: Dictionary) -> Dictionary:
    var broad_w := _weights(arrays, broad)
    var coherent_w := _weights(arrays, coherent)
    var ring1 := _one_ring(arrays, broad)
    var ring2 := _exact_two_ring(arrays, broad)
    var coherent_like := 0
    var broad_like := 0
    var other := 0
    var min_to_coherent := INF
    var min_to_broad := INF
    var rows: Array = []
    for v in ring2:
        var w := _weights(arrays, v)
        var dc := _l1(w, coherent_w)
        var db := _l1(w, broad_w)
        min_to_coherent = min(min_to_coherent, dc)
        min_to_broad = min(min_to_broad, db)
        var cls := "other"
        if dc <= float(gates["coherent_like_l1"]):
            cls = "coherent_like"
            coherent_like += 1
        elif db <= float(gates["broad_like_l1"]):
            cls = "broad_like"
            broad_like += 1
        else:
            other += 1
        rows.append({"vertex": v, "l1_to_coherent": dc, "l1_to_broad": db, "classification": cls, "dominant": _dominant(w, skeleton)})
    rows.sort_custom(func(a, b): return float(a["l1_to_broad"]) < float(b["l1_to_broad"]))
    return {
        "broad_vertex": broad,
        "coherent_vertex": coherent,
        "one_ring_count": ring1.size(),
        "exact_two_ring_count": ring2.size(),
        "coherent_like_count": coherent_like,
        "broad_like_count": broad_like,
        "other_count": other,
        "min_l1_to_coherent": min_to_coherent,
        "min_l1_to_broad": min_to_broad,
        "broad_weight_sum": _weight_sum(broad_w),
        "coherent_weight_sum": _weight_sum(coherent_w),
        "broad_dominant": _dominant(broad_w, skeleton),
        "coherent_dominant": _dominant(coherent_w, skeleton),
        "two_ring": rows
    }

func _total_vertices() -> int:
    var total := 0
    for node in mesh_nodes:
        if node.mesh == null: continue
        for s in range(node.mesh.get_surface_count()):
            total += node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
    return total

func _initialize() -> void:
    var contract := _read_json(CONTRACT_PATH)
    var prior := _read_json(ONE_RING_PATH)
    var packed := load(TARGET_PATH) as PackedScene
    if packed == null:
        failures.append("target_scene_missing")
        _write_result({"diagnostic_state":"SHOULDER_TWO_RING_BLOCKED","failures":failures})
        return
    var root := packed.instantiate()
    get_root().add_child(root)
    _collect_meshes(root)
    var target: Dictionary = contract.get("target_artifact", {})
    var source: Dictionary = contract.get("one_ring_artifact", {})
    var gates: Dictionary = contract.get("field_gates", {})
    if prior.get("diagnostic_state") != source.get("expected_state"): failures.append("one_ring_state_mismatch")
    if int(prior.get("audited_edge_count", -1)) != 6: failures.append("one_ring_edge_count_mismatch")
    var total := _total_vertices()
    if total != int(target.get("expected_vertex_total", -1)): failures.append("target_vertex_total=%d" % total)
    var reports: Array = []
    for edge in prior.get("edges", []):
        if str(edge.get("family", "")) != "shoulder": continue
        var a: Dictionary = edge.get("endpoint_a", {})
        var b: Dictionary = edge.get("endpoint_b", {})
        var coherent: Dictionary
        var broad: Dictionary
        if float(a.get("max_other_neighbor_weight_l1", INF)) <= float(gates["coherent_endpoint_max_other_l1"]) and float(b.get("max_other_neighbor_weight_l1", -INF)) >= float(gates["broad_endpoint_min_other_l1"]):
            coherent = a; broad = b
        elif float(b.get("max_other_neighbor_weight_l1", INF)) <= float(gates["coherent_endpoint_max_other_l1"]) and float(a.get("max_other_neighbor_weight_l1", -INF)) >= float(gates["broad_endpoint_min_other_l1"]):
            coherent = b; broad = a
        else:
            failures.append("shoulder_signature_drift=%d:%d" % [int(edge.get("vertex_a", -1)), int(edge.get("vertex_b", -1))])
            continue
        var parts := _surface_parts(str(edge.get("surface", "")))
        if parts.is_empty(): continue
        var mesh := _find_mesh(str(parts["mesh_name"]))
        if mesh == null or mesh.mesh == null: continue
        var s := int(parts["surface_index"])
        var arrays := mesh.mesh.surface_get_arrays(s)
        var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
        var r := _two_ring_report(arrays, int(broad["vertex"]), int(coherent["vertex"]), skeleton, gates)
        r["surface"] = edge.get("surface")
        r["pair_weight_l1"] = edge.get("pair_weight_l1")
        reports.append(r)
        if bool(gates["require_nonempty_exact_two_ring"]) and int(r["exact_two_ring_count"]) == 0: failures.append("empty_two_ring=%d" % int(broad["vertex"]))
        if abs(float(r["broad_weight_sum"]) - 1.0) > float(gates["weight_sum_tolerance"]): failures.append("broad_weight_sum=%f" % float(r["broad_weight_sum"]))
        if abs(float(r["coherent_weight_sum"]) - 1.0) > float(gates["weight_sum_tolerance"]): failures.append("coherent_weight_sum=%f" % float(r["coherent_weight_sum"]))
    if reports.size() != int(gates["require_exact_shoulder_edges"]): failures.append("shoulder_report_count=%d" % reports.size())
    var isolated := 0
    var extended := 0
    for r in reports:
        if int(r["broad_like_count"]) == 0: isolated += 1
        else: extended += 1
    var state := "SHOULDER_TWO_RING_BLOCKED"
    var next_axis := "FIX_TWO_RING_AUDIT"
    if failures.is_empty():
        if isolated == reports.size():
            state = "SHOULDER_BROAD_ENDPOINTS_ISOLATED_IN_TWO_RING"
            next_axis = str(contract["next_safe_axis_if_isolated_broad_islands"])
        elif extended == reports.size():
            state = "SHOULDER_BROAD_CLUSTER_EXTENDS_IN_TWO_RING"
            next_axis = str(contract["next_safe_axis_if_broad_cluster_extends"])
        else:
            state = "SHOULDER_TWO_RING_MIXED_TOPOLOGY"
            next_axis = str(contract["next_safe_axis_if_mixed"])
    _write_result({
        "diagnostic_state": state,
        "candidate_variant": int(contract.get("candidate_variant", -1)),
        "godot_version": Engine.get_version_info().get("string", ""),
        "target_vertex_total": total,
        "shoulder_report_count": reports.size(),
        "isolated_broad_endpoint_count": isolated,
        "extended_broad_endpoint_count": extended,
        "shoulders": reports,
        "failures": failures,
        "rails": contract.get("rails", {}),
        "production_activation_allowed": false,
        "visual_approval_allowed": false,
        "next_safe_axis": next_axis
    })
