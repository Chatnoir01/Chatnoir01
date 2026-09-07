extends SceneTree

const TARGET_BONE := "mixamorig_RightFoot"

func _initialize() -> void:
    var out_path := "user://civ1-skin-influence-census.json"
    var args := OS.get_cmdline_user_args()
    if args.size() >= 1:
        out_path = args[0]

    var packed := load("res://civ1_body.glb") as PackedScene
    if packed == null:
        push_error("CIV1_SKIN_INFLUENCE_CENSUS_FAIL: load")
        quit(2)
        return
    var root := packed.instantiate()
    get_root().add_child(root)
    await process_frame

    var skeleton := _find_skeleton(root)
    if skeleton == null:
        push_error("CIV1_SKIN_INFLUENCE_CENSUS_FAIL: skeleton")
        quit(3)
        return
    var target_bone := skeleton.find_bone(TARGET_BONE)
    if target_bone < 0:
        push_error("CIV1_SKIN_INFLUENCE_CENSUS_FAIL: rightfoot-bone")
        quit(4)
        return

    var census := {}
    var target_vertices: Array = []
    var mesh_keys := {}
    var surface_keys := {}
    var counters := {
        "positive_weight_slots": 0,
        "indexed_bind_resolution_slots": 0,
        "named_bind_resolution_slots": 0,
        "unresolved_positive_bind_slots": 0
    }
    _collect_meshes(root, skeleton, target_bone, census, target_vertices, mesh_keys, surface_keys, counters)

    var bones: Array = []
    var right_side_bones: Array = []
    for bone_index in range(skeleton.get_bone_count()):
        var name := str(skeleton.get_bone_name(bone_index))
        var entry: Dictionary = census.get(name, {})
        var record := {
            "bone_index": bone_index,
            "bone_name": name,
            "parent_bone_index": skeleton.get_bone_parent(bone_index),
            "parent_bone_name": str(skeleton.get_bone_name(skeleton.get_bone_parent(bone_index))) if skeleton.get_bone_parent(bone_index) >= 0 else "<root>",
            "positive_vertex_count": int(entry.get("positive_vertex_count", 0)),
            "positive_slot_count": int(entry.get("positive_slot_count", 0)),
            "total_stored_weight": float(entry.get("total_stored_weight", 0.0)),
            "dominant_vertex_count": int(entry.get("dominant_vertex_count", 0)),
            "local_y_min": entry.get("local_y_min", null),
            "local_y_max": entry.get("local_y_max", null)
        }
        bones.append(record)
        if "Right" in name and record["positive_vertex_count"] > 0:
            right_side_bones.append(record)

    right_side_bones.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
        if a["positive_vertex_count"] == b["positive_vertex_count"]:
            return str(a["bone_name"]) < str(b["bone_name"])
        return int(a["positive_vertex_count"]) > int(b["positive_vertex_count"])
    )

    var target_record: Dictionary = bones[target_bone]
    var resolved_slots := int(counters["indexed_bind_resolution_slots"]) + int(counters["named_bind_resolution_slots"])
    var report := {
        "schema": "grand-bruxelles-civ1-skin-influence-census-v4",
        "diagnostic_only": true,
        "selection_semantic": "all_stored_positive_skin_influences_resolved_through_skin_bind_index_or_bind_name",
        "threshold_tuned": false,
        "presence_rule": "stored_weight_greater_than_zero_only",
        "bind_mapping_rule": "ARRAY_BONES_is_skin_bind_index_then_resolve_get_bind_bone_or_get_bind_name_to_skeleton",
        "target_bone": TARGET_BONE,
        "target_bone_index": target_bone,
        "skeleton_bone_count": skeleton.get_bone_count(),
        "skinned_mesh_count": mesh_keys.size(),
        "surface_count": surface_keys.size(),
        "positive_weight_slot_count": int(counters["positive_weight_slots"]),
        "indexed_bind_resolution_slot_count": int(counters["indexed_bind_resolution_slots"]),
        "named_bind_resolution_slot_count": int(counters["named_bind_resolution_slots"]),
        "resolved_positive_bind_slot_count": resolved_slots,
        "unresolved_positive_bind_slot_count": int(counters["unresolved_positive_bind_slots"]),
        "target_rightfoot_positive_vertex_count": int(target_record["positive_vertex_count"]),
        "target_rightfoot_dominant_vertex_count": int(target_record["dominant_vertex_count"]),
        "target_rightfoot_semantic_valid": int(target_record["positive_vertex_count"]) > 0,
        "right_side_positive_bones": right_side_bones,
        "bone_influence_census": bones,
        "target_vertices": target_vertices,
        "contact_phase_ready": false,
        "quantitative_foot_slide_candidate": false,
        "animation_correction_authorized": false,
        "runtime_authorized": false,
        "visual_approval_claimed": false,
        "player_view_claimed": false,
        "next_selection_authorized": false
    }

    var f := FileAccess.open(out_path, FileAccess.WRITE)
    if f == null:
        push_error("CIV1_SKIN_INFLUENCE_CENSUS_FAIL: output")
        quit(6)
        return
    f.store_string(JSON.stringify(report, "  "))
    f.close()

    if int(counters["positive_weight_slots"]) <= 0:
        push_error("CIV1_SKIN_INFLUENCE_CENSUS_FAIL: no-positive-skin-weights")
        quit(7)
        return
    if int(counters["unresolved_positive_bind_slots"]) != 0:
        push_error("CIV1_SKIN_INFLUENCE_CENSUS_FAIL: unresolved-positive-bind-slots")
        quit(8)
        return
    if resolved_slots != int(counters["positive_weight_slots"]):
        push_error("CIV1_SKIN_INFLUENCE_CENSUS_FAIL: bind-resolution-accounting")
        quit(9)
        return
    if right_side_bones.is_empty():
        push_error("CIV1_SKIN_INFLUENCE_CENSUS_FAIL: no-positive-right-side-bones-after-dual-resolution")
        quit(10)
        return

    print(
        "CIV1_SKIN_INFLUENCE_CENSUS_OK rightfoot=", target_record["positive_vertex_count"],
        " right_side_bones=", right_side_bones.size(),
        " indexed_slots=", counters["indexed_bind_resolution_slots"],
        " named_slots=", counters["named_bind_resolution_slots"],
        " positive_slots=", counters["positive_weight_slots"]
    )
    quit(0)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _resolve_bind_bone(skin: Skin, bind: int, skeleton: Skeleton3D, counters: Dictionary) -> int:
    if bind < 0 or bind >= skin.get_bind_count():
        counters["unresolved_positive_bind_slots"] = int(counters["unresolved_positive_bind_slots"]) + 1
        return -1

    var indexed_bone := skin.get_bind_bone(bind)
    if indexed_bone >= 0 and indexed_bone < skeleton.get_bone_count():
        counters["indexed_bind_resolution_slots"] = int(counters["indexed_bind_resolution_slots"]) + 1
        return indexed_bone

    var bind_name := str(skin.get_bind_name(bind))
    if not bind_name.is_empty():
        var named_bone := skeleton.find_bone(bind_name)
        if named_bone >= 0:
            counters["named_bind_resolution_slots"] = int(counters["named_bind_resolution_slots"]) + 1
            return named_bone

    counters["unresolved_positive_bind_slots"] = int(counters["unresolved_positive_bind_slots"]) + 1
    return -1

func _collect_meshes(node: Node, skeleton: Skeleton3D, target_bone: int, census: Dictionary, target_vertices: Array, mesh_keys: Dictionary, surface_keys: Dictionary, counters: Dictionary) -> void:
    if node is MeshInstance3D:
        var mi := node as MeshInstance3D
        if mi.mesh != null and mi.skin != null:
            _collect_mesh(mi, skeleton, target_bone, census, target_vertices, mesh_keys, surface_keys, counters)
    for child in node.get_children():
        _collect_meshes(child, skeleton, target_bone, census, target_vertices, mesh_keys, surface_keys, counters)

func _collect_mesh(mi: MeshInstance3D, skeleton: Skeleton3D, target_bone: int, census: Dictionary, target_vertices: Array, mesh_keys: Dictionary, surface_keys: Dictionary, counters: Dictionary) -> void:
    var skin := mi.skin
    for surface in range(mi.mesh.get_surface_count()):
        var arrays := mi.mesh.surface_get_arrays(surface)
        var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
        var binds: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
        var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
        if vertices.is_empty() or binds.is_empty() or weights.is_empty():
            continue
        if binds.size() % vertices.size() != 0 or weights.size() != binds.size():
            continue
        mesh_keys[str(mi.get_path())] = true
        surface_keys[str(mi.get_path(), ":", surface)] = true
        var slots := int(binds.size() / vertices.size())
        for vi in range(vertices.size()):
            var strongest_weight := -1.0
            var strongest_bone := -1
            var per_vertex := {}
            for slot in range(slots):
                var idx := vi * slots + slot
                var w := float(weights[idx])
                if w <= 0.0:
                    continue
                counters["positive_weight_slots"] = int(counters["positive_weight_slots"]) + 1
                var bind := int(binds[idx])
                var bone_index := _resolve_bind_bone(skin, bind, skeleton, counters)
                if bone_index < 0:
                    continue
                per_vertex[bone_index] = float(per_vertex.get(bone_index, 0.0)) + w
                if w > strongest_weight:
                    strongest_weight = w
                    strongest_bone = bone_index

            var p := vertices[vi]
            for bone_index in per_vertex.keys():
                var bone_name := str(skeleton.get_bone_name(int(bone_index)))
                var entry: Dictionary = census.get(bone_name, {
                    "positive_vertex_count": 0,
                    "positive_slot_count": 0,
                    "total_stored_weight": 0.0,
                    "dominant_vertex_count": 0,
                    "local_y_min": null,
                    "local_y_max": null
                })
                entry["positive_vertex_count"] = int(entry["positive_vertex_count"]) + 1
                entry["positive_slot_count"] = int(entry["positive_slot_count"]) + 1
                entry["total_stored_weight"] = float(entry["total_stored_weight"]) + float(per_vertex[bone_index])
                if strongest_bone == int(bone_index):
                    entry["dominant_vertex_count"] = int(entry["dominant_vertex_count"]) + 1
                if entry["local_y_min"] == null or p.y < float(entry["local_y_min"]):
                    entry["local_y_min"] = p.y
                if entry["local_y_max"] == null or p.y > float(entry["local_y_max"]):
                    entry["local_y_max"] = p.y
                census[bone_name] = entry

            if per_vertex.has(target_bone):
                target_vertices.append({
                    "mesh_path": str(mi.get_path()),
                    "surface": surface,
                    "vertex": vi,
                    "rightfoot_weight": float(per_vertex[target_bone]),
                    "dominant_bone_index": strongest_bone,
                    "dominant_bone": str(skeleton.get_bone_name(strongest_bone)) if strongest_bone >= 0 else "<none>",
                    "dominant_weight": strongest_weight,
                    "vertex_position": [p.x, p.y, p.z]
                })
