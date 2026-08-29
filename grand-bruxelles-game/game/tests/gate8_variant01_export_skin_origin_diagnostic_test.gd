extends SceneTree

const TARGET_PATH := "res://assets/npc_gate_01.glb"
const CONTRACT_PATH := "res://contract.json"
const OUT_PATH := "res://export-skin-origin-diagnostic-result.json"

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

func _l1(a: Dictionary, b: Dictionary) -> float:
    var keys := {}
    for k in a.keys(): keys[k] = true
    for k in b.keys(): keys[k] = true
    var total := 0.0
    for k in keys.keys():
        total += abs(float(a.get(k, 0.0)) - float(b.get(k, 0.0)))
    return total

func _finite_float(v: float) -> bool:
    return not is_nan(v) and not is_inf(v)

func _finite_transform(t: Transform3D) -> bool:
    var values := [
        t.basis.x.x, t.basis.x.y, t.basis.x.z,
        t.basis.y.x, t.basis.y.y, t.basis.y.z,
        t.basis.z.x, t.basis.z.y, t.basis.z.z,
        t.origin.x, t.origin.y, t.origin.z
    ]
    for value in values:
        if not _finite_float(float(value)):
            return false
    return true

func _total_vertices() -> int:
    var total := 0
    for node in mesh_nodes:
        if node.mesh == null: continue
        for s in range(node.mesh.get_surface_count()):
            total += node.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX].size()
    return total

func _resolve_bind_bone(skin: Skin, skeleton: Skeleton3D, bind_index: int) -> Dictionary:
    var bind_name := str(skin.get_bind_name(bind_index))
    var raw_bind_bone := skin.get_bind_bone(bind_index)
    var resolved_bone := raw_bind_bone
    var resolution := "index"
    if resolved_bone < 0 and not bind_name.is_empty():
        resolved_bone = skeleton.find_bone(bind_name)
        resolution = "name"
    elif resolved_bone < 0:
        resolution = "unresolved"
    var resolved_name := ""
    var rest_ok := false
    var identity_ok := false
    if resolved_bone >= 0 and resolved_bone < skeleton.get_bone_count():
        resolved_name = skeleton.get_bone_name(resolved_bone)
        rest_ok = _finite_transform(skeleton.get_bone_rest(resolved_bone))
        identity_ok = bind_name.is_empty() or resolved_name == bind_name
    return {
        "bind_name": bind_name,
        "raw_bind_bone": raw_bind_bone,
        "resolved_bone": resolved_bone,
        "resolved_name": resolved_name,
        "resolution": resolution,
        "rest_finite": rest_ok,
        "identity_ok": identity_ok
    }

func _weight_rows(w: Dictionary, skin: Skin, skeleton: Skeleton3D) -> Array:
    var rows: Array = []
    var keys: Array = w.keys()
    keys.sort()
    for key in keys:
        var bind_index := int(key)
        var bind_pose_ok := false
        var resolved := {
            "bind_name": "",
            "raw_bind_bone": -1,
            "resolved_bone": -1,
            "resolved_name": "",
            "resolution": "unresolved",
            "rest_finite": false,
            "identity_ok": false
        }
        if skin != null and skeleton != null and bind_index >= 0 and bind_index < skin.get_bind_count():
            bind_pose_ok = _finite_transform(skin.get_bind_pose(bind_index))
            resolved = _resolve_bind_bone(skin, skeleton, bind_index)
        rows.append({
            "bind_index": bind_index,
            "weight": float(w[key]),
            "bind_name": resolved["bind_name"],
            "bind_bone": resolved["raw_bind_bone"],
            "resolved_bone": resolved["resolved_bone"],
            "skeleton_bone_name": resolved["resolved_name"],
            "bind_resolution": resolved["resolution"],
            "bind_pose_finite": bind_pose_ok,
            "skeleton_rest_finite": resolved["rest_finite"],
            "bind_identity_matches": resolved["identity_ok"]
        })
    return rows

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
        _write({"diagnostic_state": "EXPORT_SKIN_ORIGIN_DIAGNOSTIC_BLOCKED", "failures": failures})
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
        _write({"diagnostic_state": "EXPORT_SKIN_ORIGIN_DIAGNOSTIC_BLOCKED", "failures": failures})
        return
    var surface_index := int(parts.get("surface_index", -1))
    if surface_index < 0 or surface_index >= mesh.mesh.get_surface_count():
        failures.append("surface_index_oob")
        _write({"diagnostic_state": "EXPORT_SKIN_ORIGIN_DIAGNOSTIC_BLOCKED", "failures": failures})
        return
    var arrays := mesh.mesh.surface_get_arrays(surface_index)
    var skin: Skin = mesh.skin
    if skin == null:
        failures.append("mesh_skin_missing")
    var skeleton: Skeleton3D = null
    if not mesh.skeleton.is_empty():
        skeleton = mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
    if skeleton == null:
        failures.append("skeleton_resolution_failed")
    var bind_count := skin.get_bind_count() if skin != null else 0
    var bone_count := skeleton.get_bone_count() if skeleton != null else 0
    if bind_count <= 0:
        failures.append("skin_bind_count=%d" % bind_count)
    if bone_count <= 0:
        failures.append("skeleton_bone_count=%d" % bone_count)
    var probe_rows := {}
    var weight_sum_tolerance := float(contract.get("weight_sum_tolerance", 0.0001))
    var named_bind_resolution_count := 0
    var unresolved_bind_count := 0
    for raw_vi in contract.get("probe_vertices", []):
        var vi := int(raw_vi)
        var w := _weights(arrays, vi)
        var sum := _sum(w)
        if abs(sum - 1.0) > weight_sum_tolerance:
            failures.append("weight_sum_v%d=%.9f" % [vi, sum])
        for raw_bind in w.keys():
            var bind_index := int(raw_bind)
            if bind_index < 0 or bind_index >= bind_count:
                failures.append("bind_index_oob_v%d=%d" % [vi, bind_index])
        var influences := _weight_rows(w, skin, skeleton)
        for influence in influences:
            if str(influence.get("bind_resolution", "")) == "name":
                named_bind_resolution_count += 1
            if int(influence.get("resolved_bone", -1)) < 0:
                unresolved_bind_count += 1
        probe_rows[str(vi)] = {
            "weight_sum": sum,
            "influences": influences
        }
    var target_edge: Array = contract.get("target_edge", [])
    var residual_edge: Array = contract.get("adjacent_residual_edge", [])
    if target_edge.size() != 2 or residual_edge.size() != 2:
        failures.append("edge_contract_invalid")
        _write({"diagnostic_state": "EXPORT_SKIN_ORIGIN_DIAGNOSTIC_BLOCKED", "failures": failures})
        return
    var target_l1 := _l1(_weights(arrays, int(target_edge[0])), _weights(arrays, int(target_edge[1])))
    var residual_l1 := _l1(_weights(arrays, int(residual_edge[0])), _weights(arrays, int(residual_edge[1])))
    var cliff_min := float(contract.get("weight_cliff_l1_min", 1.7))
    var rig_invalid := false
    for row in probe_rows.values():
        for influence in row.get("influences", []):
            if not bool(influence.get("bind_pose_finite", false)) \
            or not bool(influence.get("skeleton_rest_finite", false)) \
            or not bool(influence.get("bind_identity_matches", false)) \
            or int(influence.get("resolved_bone", -1)) < 0:
                rig_invalid = true
    var state := "EXPORT_SKIN_WEIGHT_DISCONTINUITY_NOT_REPRODUCED"
    var next_axis := str(contract.get("next_if_export_is_clean", "STOP"))
    if rig_invalid:
        state = "EXPORT_RIG_BIND_OR_REST_INVALID"
        next_axis = str(contract.get("next_if_bind_or_rest_invalid", "STOP"))
    elif target_l1 >= cliff_min:
        state = "EXPORT_SKIN_WEIGHT_DISCONTINUITY_CONFIRMED"
        next_axis = str(contract.get("next_if_export_weight_cliff_confirmed", "STOP"))
    _write({
        "format": "grand-bruxelles-gate8-variant01-export-skin-origin-diagnostic-result-v2",
        "diagnostic_state": state,
        "candidate_variant": int(contract.get("candidate_variant", -1)),
        "godot_version": Engine.get_version_info().get("string", ""),
        "target_vertex_total": total,
        "surface": contract.get("surface"),
        "skin_bind_count": bind_count,
        "skeleton_bone_count": bone_count,
        "named_bind_resolution_count": named_bind_resolution_count,
        "unresolved_bind_count": unresolved_bind_count,
        "target_edge": target_edge,
        "target_edge_weight_l1": target_l1,
        "adjacent_residual_edge": residual_edge,
        "adjacent_residual_edge_weight_l1": residual_l1,
        "probe_vertices": probe_rows,
        "failures": failures,
        "rails": contract.get("rails", {}),
        "production_activation_allowed": false,
        "visual_approval_allowed": false,
        "next_safe_axis": next_axis
    })