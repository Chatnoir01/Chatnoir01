extends SceneTree

const TARGET_BONE := "mixamorig_RightFoot"

func _initialize() -> void:
    var out_path := "user://civ1-rightfoot-weighted-subset.json"
    var args := OS.get_cmdline_user_args()
    if args.size() >= 1:
        out_path = args[0]
    var packed := load("res://civ1_body.glb") as PackedScene
    if packed == null:
        push_error("CIV1_RIGHTFOOT_SKIN_INFLUENCE_FAIL: load")
        quit(2); return
    var root := packed.instantiate()
    get_root().add_child(root)
    await process_frame
    var skeleton := _find_skeleton(root)
    if skeleton == null:
        push_error("CIV1_RIGHTFOOT_SKIN_INFLUENCE_FAIL: skeleton")
        quit(3); return
    var target_bone := skeleton.find_bone(TARGET_BONE)
    if target_bone < 0:
        push_error("CIV1_RIGHTFOOT_SKIN_INFLUENCE_FAIL: rightfoot-bone")
        quit(4); return

    var influenced: Array = []
    var dominant: Array = []
    var mesh_keys := {}
    var surface_keys := {}
    _collect_meshes(root, skeleton, target_bone, influenced, dominant, mesh_keys, surface_keys)

    var weights: Array[float] = []
    var competitor_counts := {}
    var min_y := INF
    var max_y := -INF
    for item in influenced:
        var w := float(item["rightfoot_weight"])
        weights.append(w)
        var competitor := str(item["dominant_bone"])
        competitor_counts[competitor] = int(competitor_counts.get(competitor, 0)) + 1
        var y := float(item["vertex_position"][1])
        min_y = min(min_y, y)
        max_y = max(max_y, y)
    weights.sort()

    var report := {
        "schema": "grand-bruxelles-civ1-rightfoot-skin-influence-characterization-v2",
        "diagnostic_only": true,
        "selection_semantic": "all_vertices_with_stored_nonzero_mixamorig_RightFoot_skin_influence",
        "threshold_tuned": false,
        "presence_rule": "stored_rightfoot_weight_greater_than_zero_only",
        "target_bone": TARGET_BONE,
        "target_bone_index": target_bone,
        "skeleton_bone_count": skeleton.get_bone_count(),
        "skinned_mesh_count": mesh_keys.size(),
        "surface_count": surface_keys.size(),
        "rightfoot_influenced_vertex_count": influenced.size(),
        "dominant_rightfoot_vertex_count": dominant.size(),
        "dominant_rightfoot_semantic_valid": not dominant.is_empty(),
        "influenced_local_y_min": min_y if not influenced.is_empty() else null,
        "influenced_local_y_max": max_y if not influenced.is_empty() else null,
        "rightfoot_weight_min": weights[0] if not weights.is_empty() else null,
        "rightfoot_weight_max": weights[weights.size() - 1] if not weights.is_empty() else null,
        "rightfoot_weight_median": _median(weights),
        "dominant_bone_counts_within_rightfoot_influenced_set": competitor_counts,
        "vertices": influenced,
        "contact_phase_ready": false,
        "quantitative_foot_slide_candidate": false,
        "animation_correction_authorized": false,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
        "player_view_claimed": false,
        "next_selection_authorized": not influenced.is_empty()
    }
    var f := FileAccess.open(out_path, FileAccess.WRITE)
    if f == null:
        push_error("CIV1_RIGHTFOOT_SKIN_INFLUENCE_FAIL: output")
        quit(6); return
    f.store_string(JSON.stringify(report, "  "))
    f.close()

    if influenced.is_empty():
        push_error("CIV1_RIGHTFOOT_SKIN_INFLUENCE_FAIL: no-nonzero-rightfoot-influence")
        quit(7); return
    print("CIV1_RIGHTFOOT_SKIN_INFLUENCE_OK influenced=", influenced.size(), " dominant=", dominant.size(), " meshes=", mesh_keys.size(), " surfaces=", surface_keys.size())
    quit(0)

func _median(values: Array[float]):
    if values.is_empty():
        return null
    var n := values.size()
    if n % 2 == 1:
        return values[n / 2]
    return (values[n / 2 - 1] + values[n / 2]) * 0.5

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _collect_meshes(node: Node, skeleton: Skeleton3D, target_bone: int, influenced: Array, dominant: Array, mesh_keys: Dictionary, surface_keys: Dictionary) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        if mi.mesh != null and mi.skin != null:
            _collect_mesh(mi, skeleton, target_bone, influenced, dominant, mesh_keys, surface_keys)
    for child in node.get_children():
        _collect_meshes(child, skeleton, target_bone, influenced, dominant, mesh_keys, surface_keys)

func _collect_mesh(mi: MeshInstance3D, skeleton: Skeleton3D, target_bone: int, influenced: Array, dominant: Array, mesh_keys: Dictionary, surface_keys: Dictionary) -> void:
    var skin := mi.skin
    for surface in range(mi.mesh.get_surface_count()):
        var arrays := mi.mesh.surface_get_arrays(surface)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
        var raw_weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
        if vertices.is_empty() or bones.is_empty() or raw_weights.is_empty():
            continue
        if bones.size() % vertices.size() != 0 or raw_weights.size() != bones.size():
            continue
        mesh_keys[str(mi.get_path())] = true
        surface_keys[str(mi.get_path(), ":", surface)] = true
        var influence_slots := int(bones.size() / vertices.size())
        for vi in range(vertices.size()):
            var strongest_weight := -1.0
            var strongest_bind := -1
            var rightfoot_weight := 0.0
            var rightfoot_bind := -1
            for slot in range(influence_slots):
                var idx := vi * influence_slots + slot
                var w := float(raw_weights[idx])
                var bind := int(bones[idx])
                if w > strongest_weight:
                    strongest_weight = w
                    strongest_bind = bind
                if bind >= 0 and bind < skin.get_bind_count() and skin.get_bind_bone(bind) == target_bone and w > 0.0:
                    rightfoot_weight += w
                    if rightfoot_bind < 0:
                        rightfoot_bind = bind
            if rightfoot_weight <= 0.0:
                continue
            var dominant_bone_index := -1
            var dominant_bone_name := "<invalid-bind>"
            if strongest_bind >= 0 and strongest_bind < skin.get_bind_count():
                dominant_bone_index = skin.get_bind_bone(strongest_bind)
                if dominant_bone_index >= 0 and dominant_bone_index < skeleton.get_bone_count():
                    dominant_bone_name = skeleton.get_bone_name(dominant_bone_index)
            var p := vertices[vi]
            var item := {
                "mesh_path": str(mi.get_path()),
                "surface": surface,
                "vertex": vi,
                "rightfoot_bind": rightfoot_bind,
                "rightfoot_weight": rightfoot_weight,
                "dominant_bind": strongest_bind,
                "dominant_bone_index": dominant_bone_index,
                "dominant_bone": dominant_bone_name,
                "dominant_weight": strongest_weight,
                "vertex_position": [p.x, p.y, p.z]
            }
            influenced.append(item)
            if dominant_bone_index == target_bone:
                dominant.append(item)
