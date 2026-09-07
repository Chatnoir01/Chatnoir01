extends SceneTree

const FOOT := "mixamorig_RightFoot"
const TOE := "mixamorig_RightToeBase"

func _initialize() -> void:
    var out_path := "user://civ1-rightfoot-full-skin-basis.json"
    var args := OS.get_cmdline_user_args()
    if args.size() >= 1:
        out_path = args[0]
    var packed := load("res://civ1_body.glb") as PackedScene
    if packed == null:
        push_error("CIV1_FULL_SKIN_BASIS_FAIL:load")
        quit(2); return
    var root := packed.instantiate()
    get_root().add_child(root)
    await process_frame
    var skeleton := _find_skeleton(root)
    if skeleton == null:
        push_error("CIV1_FULL_SKIN_BASIS_FAIL:skeleton")
        quit(3); return
    var foot := skeleton.find_bone(FOOT)
    var toe := skeleton.find_bone(TOE)
    if foot < 0 or toe < 0 or not _is_descendant_of(skeleton, toe, foot):
        push_error("CIV1_FULL_SKIN_BASIS_FAIL:chain")
        quit(4); return

    var selected: Array = []
    var counters := {"positive_slots":0,"indexed":0,"named":0,"unresolved":0}
    var meshes := {}
    var surfaces := {}
    _collect(root, skeleton, foot, toe, selected, counters, meshes, surfaces)
    selected.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        var ka := "%s|%08d|%08d" % [a["mesh_path"], a["surface"], a["vertex"]]
        var kb := "%s|%08d|%08d" % [b["mesh_path"], b["surface"], b["vertex"]]
        return ka < kb)

    var report := {
        "schema":"grand-bruxelles-civ1-rightfoot-full-skin-basis-v1",
        "diagnostic_only":true,
        "selection_semantic":"same_fixed_righttoebase_positive_vertex_population_from_validated_chain_geometry",
        "presence_rule":"stored_weight_greater_than_zero_only",
        "threshold_tuned":false,
        "target_bone":FOOT,
        "toe_bone":TOE,
        "toe_is_descendant_of_rightfoot":true,
        "skeleton_bone_count":skeleton.get_bone_count(),
        "skinned_mesh_count":meshes.size(),
        "surface_count":surfaces.size(),
        "positive_weight_slot_count":counters["positive_slots"],
        "indexed_bind_resolution_slot_count":counters["indexed"],
        "named_bind_resolution_slot_count":counters["named"],
        "unresolved_positive_bind_slot_count":counters["unresolved"],
        "selection_vertex_count":selected.size(),
        "vertices":selected,
        "full_vertex_influence_basis_available":true,
        "pose_coverage_ready":false,
        "skinning_input_complete":false,
        "bone_local_witness_authorized":false,
        "contact_phase_ready":false,
        "quantitative_foot_slide_candidate":false,
        "animation_correction_authorized":false,
        "runtime_authorized":false,
        "visual_approval_claimed":false,
        "player_view_claimed":false
    }
    var f := FileAccess.open(out_path, FileAccess.WRITE)
    if f == null:
        push_error("CIV1_FULL_SKIN_BASIS_FAIL:output")
        quit(5); return
    f.store_string(JSON.stringify(report, "  ")); f.close()
    if counters["unresolved"] != 0:
        push_error("CIV1_FULL_SKIN_BASIS_FAIL:unresolved")
        quit(6); return
    if selected.size() != 3306:
        push_error("CIV1_FULL_SKIN_BASIS_FAIL:selection-count:%d" % selected.size())
        quit(7); return
    for v in selected:
        if v["influences"].is_empty():
            push_error("CIV1_FULL_SKIN_BASIS_FAIL:empty-influence-vector")
            quit(8); return
    print("CIV1_FULL_SKIN_BASIS_OK vertices=", selected.size(), " positive_slots=", counters["positive_slots"])
    quit(0)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D: return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null: return found
    return null

func _is_descendant_of(skeleton: Skeleton3D, candidate: int, ancestor: int) -> bool:
    var current := candidate
    while current >= 0:
        if current == ancestor: return candidate != ancestor
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

func _collect(node: Node, skeleton: Skeleton3D, foot: int, toe: int, selected: Array, counters: Dictionary, meshes: Dictionary, surfaces: Dictionary) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        if mi.mesh != null and mi.skin != null:
            _collect_mesh(mi, skeleton, foot, toe, selected, counters, meshes, surfaces)
    for child in node.get_children():
        _collect(child, skeleton, foot, toe, selected, counters, meshes, surfaces)

func _collect_mesh(mi: MeshInstance3D, skeleton: Skeleton3D, foot: int, toe: int, selected: Array, counters: Dictionary, meshes: Dictionary, surfaces: Dictionary) -> void:
    var skin := mi.skin
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
            var per_bone := {}
            for slot in range(slots):
                var idx := vi * slots + slot
                var w := float(weights[idx])
                if w <= 0.0: continue
                counters["positive_slots"] += 1
                var bone := _resolve_bind(skin, int(binds[idx]), skeleton, counters)
                if bone < 0: continue
                per_bone[bone] = float(per_bone.get(bone, 0.0)) + w
            if not per_bone.has(toe): continue
            var influences: Array = []
            var sum := 0.0
            for bone in per_bone.keys():
                var w := float(per_bone[bone]); sum += w
                influences.append({"bone_index":int(bone),"bone_name":str(skeleton.get_bone_name(int(bone))),"weight":w})
            influences.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["bone_index"]) < int(b["bone_index"]))
            var p := vertices[vi]
            selected.append({
                "mesh_path":str(mi.get_path()),"surface":surface,"vertex":vi,
                "vertex_position":[p.x,p.y,p.z],
                "rightfoot_weight":float(per_bone.get(foot,0.0)),
                "righttoebase_weight":float(per_bone.get(toe,0.0)),
                "influence_weight_sum":sum,
                "influences":influences
            })
