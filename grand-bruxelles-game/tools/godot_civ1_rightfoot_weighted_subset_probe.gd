extends SceneTree

const TARGET_BONE := "mixamorig_RightFoot"

func _initialize() -> void:
    var out_path := "user://civ1-rightfoot-weighted-subset.json"
    var args := OS.get_cmdline_user_args()
    if args.size() >= 1:
        out_path = args[0]
    var packed := load("res://civ1_body.glb") as PackedScene
    if packed == null:
        push_error("CIV1_RIGHTFOOT_SKIN_SUBSET_FAIL: load")
        quit(2); return
    var root := packed.instantiate()
    get_root().add_child(root)
    await process_frame
    var skeleton := _find_skeleton(root)
    if skeleton == null:
        push_error("CIV1_RIGHTFOOT_SKIN_SUBSET_FAIL: skeleton")
        quit(3); return
    var bone_idx := skeleton.find_bone(TARGET_BONE)
    if bone_idx < 0:
        push_error("CIV1_RIGHTFOOT_SKIN_SUBSET_FAIL: rightfoot-bone")
        quit(4); return
    var selected: Array = []
    _collect_meshes(root, bone_idx, selected)
    if selected.is_empty():
        push_error("CIV1_RIGHTFOOT_SKIN_SUBSET_FAIL: no-dominant-rightfoot-vertices")
        quit(5); return
    var mesh_keys := {}
    var surface_keys := {}
    var min_y := INF
    var max_y := -INF
    for item in selected:
        mesh_keys[item["mesh_path"]] = true
        surface_keys[str(item["mesh_path"], ":", item["surface"])] = true
        var y := float(item["vertex_position"][1])
        min_y = min(min_y, y)
        max_y = max(max_y, y)
    var report := {
        "schema": "grand-bruxelles-civ1-rightfoot-dominant-skin-subset-v1",
        "diagnostic_only": true,
        "selection_semantic": "fixed_vertices_whose_strongest_skin_influence_maps_to_mixamorig_RightFoot",
        "threshold_tuned": false,
        "target_bone": TARGET_BONE,
        "target_bone_index": bone_idx,
        "skeleton_bone_count": skeleton.get_bone_count(),
        "skinned_mesh_count": mesh_keys.size(),
        "surface_count": surface_keys.size(),
        "selected_vertex_count": selected.size(),
        "selected_local_y_min": min_y,
        "selected_local_y_max": max_y,
        "vertices": selected,
        "contact_phase_ready": false,
        "quantitative_foot_slide_candidate": false,
        "animation_correction_authorized": false,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
        "player_view_claimed": false
    }
    var f := FileAccess.open(out_path, FileAccess.WRITE)
    if f == null:
        push_error("CIV1_RIGHTFOOT_SKIN_SUBSET_FAIL: output")
        quit(6); return
    f.store_string(JSON.stringify(report, "  "))
    f.close()
    print("CIV1_RIGHTFOOT_SKIN_SUBSET_OK selected=", selected.size(), " meshes=", mesh_keys.size(), " surfaces=", surface_keys.size())
    quit(0)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _collect_meshes(node: Node, target_bone: int, selected: Array) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        if mi.mesh != null and mi.skin != null:
            _collect_mesh(mi, target_bone, selected)
    for child in node.get_children():
        _collect_meshes(child, target_bone, selected)

func _collect_mesh(mi: MeshInstance3D, target_bone: int, selected: Array) -> void:
    var skin := mi.skin
    for surface in range(mi.mesh.get_surface_count()):
        var arrays := mi.mesh.surface_get_arrays(surface)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
        var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
        if vertices.is_empty() or bones.is_empty() or weights.is_empty():
            continue
        if bones.size() % vertices.size() != 0 or weights.size() != bones.size():
            continue
        var influences := int(bones.size() / vertices.size())
        for vi in range(vertices.size()):
            var strongest_weight := -1.0
            var strongest_bind := -1
            for slot in range(influences):
                var idx := vi * influences + slot
                var w := float(weights[idx])
                if w > strongest_weight:
                    strongest_weight = w
                    strongest_bind = int(bones[idx])
            if strongest_bind < 0 or strongest_bind >= skin.get_bind_count():
                continue
            if skin.get_bind_bone(strongest_bind) != target_bone:
                continue
            var p := vertices[vi]
            selected.append({"mesh_path": str(mi.get_path()), "surface": surface, "vertex": vi, "dominant_bind": strongest_bind, "dominant_weight": strongest_weight, "vertex_position": [p.x, p.y, p.z]})
