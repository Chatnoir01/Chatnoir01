extends SceneTree

const FOOT := "mixamorig_RightFoot"
const TOE := "mixamorig_RightToeBase"
const NORMALIZATION_TOLERANCE := 0.0001

func _initialize() -> void:
    var out_path := "user://civ1-rightfoot-bind-pose.json"
    var args := OS.get_cmdline_user_args()
    if args.size() >= 1:
        out_path = args[0]
    var packed := load("res://civ1_body.glb") as PackedScene
    if packed == null:
        push_error("CIV1_BIND_POSE_FAIL:load"); quit(2); return
    var root := packed.instantiate()
    get_root().add_child(root)
    await process_frame
    var skeleton := _find_skeleton(root)
    if skeleton == null:
        push_error("CIV1_BIND_POSE_FAIL:skeleton"); quit(3); return
    var foot := skeleton.find_bone(FOOT)
    var toe := skeleton.find_bone(TOE)
    if foot < 0 or toe < 0 or not _is_descendant_of(skeleton, toe, foot):
        push_error("CIV1_BIND_POSE_FAIL:chain"); quit(4); return

    var selected: Array = []
    var counters := {"positive_slots":0,"indexed":0,"named":0,"unresolved":0,"nonfinite_bind_pose":0}
    var meshes := {}
    var surfaces := {}
    _collect(root, skeleton, foot, toe, selected, counters, meshes, surfaces)
    selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var ka := "%s|%08d|%08d" % [a["mesh_path"], a["surface"], a["vertex"]]
        var kb := "%s|%08d|%08d" % [b["mesh_path"], b["surface"], b["vertex"]]
        return ka < kb)

    var normalization_violation_count := 0
    var vertices_with_complete_bind_space := 0
    var positive_influence_slots_with_bind_space := 0
    for v in selected:
        var s := float(v["influence_weight_sum"])
        if abs(s - 1.0) > NORMALIZATION_TOLERANCE:
            normalization_violation_count += 1
        var complete := true
        for i in v["influences"]:
            if not bool(i.get("bind_pose_finite", false)):
                complete = false
            else:
                positive_influence_slots_with_bind_space += 1
        if complete:
            vertices_with_complete_bind_space += 1

    var bind_space_complete := selected.size() == 3306 and vertices_with_complete_bind_space == 3306 and counters["unresolved"] == 0 and counters["nonfinite_bind_pose"] == 0
    var report := {
        "schema":"grand-bruxelles-civ1-rightfoot-bind-pose-basis-v1",
        "diagnostic_only":true,
        "selection_semantic":"same_fixed_righttoebase_positive_vertex_population_from_validated_chain_geometry",
        "presence_rule":"stored_weight_greater_than_zero_only",
        "target_bone":FOOT,
        "toe_bone":TOE,
        "skeleton_bone_count":skeleton.get_bone_count(),
        "skinned_mesh_count":meshes.size(),
        "surface_count":surfaces.size(),
        "selection_vertex_count":selected.size(),
        "positive_weight_slot_count":counters["positive_slots"],
        "unresolved_positive_bind_slot_count":counters["unresolved"],
        "nonfinite_bind_pose_count":counters["nonfinite_bind_pose"],
        "normalization_tolerance":NORMALIZATION_TOLERANCE,
        "normalization_violation_count":normalization_violation_count,
        "vertices_with_complete_bind_space":vertices_with_complete_bind_space,
        "positive_influence_slots_with_bind_space":positive_influence_slots_with_bind_space,
        "bind_space_complete":bind_space_complete,
        "vertices":selected,
        "rigid_parent_proxy_authorized":false,
        "global_pose_as_bind_matrix_authorized":false,
        "skinned_replay_authorized":false,
        "animation_correction_authorized":false,
        "runtime_authorized":false,
        "visual_approval_claimed":false,
        "player_view_claimed":false
    }
    var f := FileAccess.open(out_path, FileAccess.WRITE)
    if f == null:
        push_error("CIV1_BIND_POSE_FAIL:output"); quit(5); return
    f.store_string(JSON.stringify(report, "  ")); f.close()
    if counters["unresolved"] != 0 or counters["nonfinite_bind_pose"] != 0:
        push_error("CIV1_BIND_POSE_FAIL:bind-integrity"); quit(6); return
    if selected.size() != 3306:
        push_error("CIV1_BIND_POSE_FAIL:selection-count:%d" % selected.size()); quit(7); return
    if normalization_violation_count != 0:
        push_error("CIV1_BIND_POSE_FAIL:normalization:%d" % normalization_violation_count); quit(8); return
    if not bind_space_complete:
        push_error("CIV1_BIND_POSE_FAIL:incomplete-bind-space"); quit(9); return
    print("CIV1_BIND_POSE_OK vertices=", selected.size(), " slots=", counters["positive_slots"])
    quit(0)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _is_descendant_of(skeleton: Skeleton3D, candidate: int, ancestor: int) -> bool:
    var current := candidate
    while current >= 0:
        if current == ancestor:
            return candidate != ancestor
        current = skeleton.get_bone_parent(current)
    return false

func _resolve_bind(skin: Skin, bind: int, skeleton: Skeleton3D, counters: Dictionary) -> int:
    if bind < 0 or bind >= skin.get_bind_count():
        counters["unresolved"] += 1; return -1
    var indexed := skin.get_bind_bone(bind)
    if indexed >= 0 and indexed < skeleton.get_bone_count():
        counters["indexed"] += 1; return indexed
    var bind_name := str(skin.get_bind_name(bind))
    if not bind_name.is_empty():
        var named := skeleton.find_bone(bind_name)
        if named >= 0:
            counters["named"] += 1; return named
    counters["unresolved"] += 1
    return -1

func _transform_array(t: Transform3D) -> Array:
    return [t.basis.x.x,t.basis.x.y,t.basis.x.z,t.basis.y.x,t.basis.y.y,t.basis.y.z,t.basis.z.x,t.basis.z.y,t.basis.z.z,t.origin.x,t.origin.y,t.origin.z]

func _transform_finite(t: Transform3D) -> bool:
    for value in _transform_array(t):
        if not is_finite(float(value)):
            return false
    return true

func _collect(node: Node, skeleton: Skeleton3D, foot: int, toe: int, selected: Array, counters: Dictionary, meshes: Dictionary, surfaces: Dictionary) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        if mi.mesh != null and mi.skin != null:
            _collect_mesh(mi, skeleton, foot, toe, selected, counters, meshes, surfaces)
    for child in node.get_children():
        _collect(child, skeleton, foot, toe, selected, counters, meshes, surfaces)

func _collect_mesh(mi: MeshInstance3D, skeleton: Skeleton3D, foot: int, toe: int, selected: Array, counters: Dictionary, meshes: Dictionary, surfaces: Dictionary) -> void:
    var skin := mi.skin
    var mesh_to_skeleton_rest := skeleton.global_transform.affine_inverse() * mi.global_transform
    for surface in range(mi.mesh.get_surface_count()):
        var arrays := mi.mesh.surface_get_arrays(surface)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var binds: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
        var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
        if vertices.is_empty() or binds.is_empty() or weights.is_empty(): continue
        if binds.size() % vertices.size() != 0 or weights.size() != binds.size(): continue
        meshes[str(mi.get_path())] = true
        surfaces[str(mi.get_path(), ":", surface)] = true
        var slots := int(binds.size() / vertices.size())
        for vi in range(vertices.size()):
            var influences: Array = []
            var sum := 0.0
            var has_toe := false
            var rightfoot_weight := 0.0
            var righttoebase_weight := 0.0
            for slot in range(slots):
                var idx := vi * slots + slot
                var w := float(weights[idx])
                if w <= 0.0: continue
                counters["positive_slots"] += 1
                var bind := int(binds[idx])
                var bone := _resolve_bind(skin, bind, skeleton, counters)
                if bone < 0: continue
                var bind_pose := skin.get_bind_pose(bind)
                var finite := _transform_finite(bind_pose)
                if not finite:
                    counters["nonfinite_bind_pose"] += 1
                sum += w
                if bone == foot: rightfoot_weight += w
                if bone == toe:
                    righttoebase_weight += w
                    has_toe = true
                influences.append({"slot":slot,"bind_index":bind,"bone_index":bone,"bone_name":str(skeleton.get_bone_name(bone)),"weight":w,"inverse_bind_transform":_transform_array(bind_pose),"bind_pose_finite":finite})
            if not has_toe: continue
            var p := vertices[vi]
            selected.append({"mesh_path":str(mi.get_path()),"surface":surface,"vertex":vi,"vertex_position":[p.x,p.y,p.z],"mesh_to_skeleton_rest":_transform_array(mesh_to_skeleton_rest),"rightfoot_weight":rightfoot_weight,"righttoebase_weight":righttoebase_weight,"influence_weight_sum":sum,"influences":influences})
