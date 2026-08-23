extends "res://game/tests/gate8_variant01_native_retarget_ab_test.gd"

var _skin_bind_remap_report := {
    "meshes": 0,
    "skins": 0,
    "binds": 0,
    "renamed_binds": 0,
    "bind_count_unchanged": true,
    "bind_poses_unchanged": true,
    "bind_bone_indices_unchanged": true,
    "missing_named_binds_after_remap": 0,
    "runtime_only": true
}

func _rename_target_to_source_namespace() -> bool:
    # Keep the source skeleton untouched so imported AnimationPlayer track paths remain
    # valid. Rename the target bones first, then immediately replace every imported
    # Skin with a duplicated runtime Skin whose named binds follow the same namespace.
    # No frame is yielded between these operations.
    if not super._rename_target_to_source_namespace():
        return false
    return _remap_target_skin_bind_names_runtime_only()

func _remap_target_skin_bind_names_runtime_only() -> bool:
    var target_to_source := {}
    for role_value: Variant in ROLE_PAIRS.keys():
        var role := String(role_value)
        target_to_source[_target_name(role)] = _source_name(role)

    for mesh: MeshInstance3D in _target_meshes:
        if not is_instance_valid(mesh):
            continue
        _skin_bind_remap_report["meshes"] = int(_skin_bind_remap_report["meshes"]) + 1
        var original := mesh.get_skin()
        if original == null:
            continue
        _skin_bind_remap_report["skins"] = int(_skin_bind_remap_report["skins"]) + 1
        var duplicate := original.duplicate(true) as Skin
        if duplicate == null:
            _failures.append("skin_duplicate_failed mesh=%s" % mesh.name)
            continue

        var bind_count := original.get_bind_count()
        if duplicate.get_bind_count() != bind_count:
            _skin_bind_remap_report["bind_count_unchanged"] = false
            _failures.append("skin_bind_count_changed mesh=%s before=%d after=%d" % [mesh.name, bind_count, duplicate.get_bind_count()])
            continue

        for bind_index: int in range(bind_count):
            _skin_bind_remap_report["binds"] = int(_skin_bind_remap_report["binds"]) + 1
            var old_name := String(original.get_bind_name(bind_index))
            var original_bone := original.get_bind_bone(bind_index)
            var original_pose := original.get_bind_pose(bind_index)
            if target_to_source.has(old_name):
                duplicate.set_bind_name(bind_index, StringName(String(target_to_source[old_name])))
                _skin_bind_remap_report["renamed_binds"] = int(_skin_bind_remap_report["renamed_binds"]) + 1

            if duplicate.get_bind_bone(bind_index) != original_bone:
                _skin_bind_remap_report["bind_bone_indices_unchanged"] = false
                _failures.append("skin_bind_bone_changed mesh=%s bind=%d" % [mesh.name, bind_index])
            if not duplicate.get_bind_pose(bind_index).is_equal_approx(original_pose):
                _skin_bind_remap_report["bind_poses_unchanged"] = false
                _failures.append("skin_bind_pose_changed mesh=%s bind=%d" % [mesh.name, bind_index])

        mesh.set_skin(duplicate)

    # After target bone rename + Skin remap, every named bind must resolve on the
    # renamed target skeleton. This catches incomplete role maps and hidden helpers.
    var missing := 0
    for mesh: MeshInstance3D in _target_meshes:
        if not is_instance_valid(mesh):
            continue
        var skin := mesh.get_skin()
        if skin == null:
            continue
        for bind_index: int in range(skin.get_bind_count()):
            var bind_name := String(skin.get_bind_name(bind_index))
            if bind_name.is_empty():
                continue
            if _target_skeleton.find_bone(bind_name) < 0:
                missing += 1
                _failures.append("skin_named_bind_missing mesh=%s bind=%d name=%s" % [mesh.name, bind_index, bind_name])
    _skin_bind_remap_report["missing_named_binds_after_remap"] = missing

    if int(_skin_bind_remap_report["skins"]) <= 0:
        _failures.append("skin_remap_no_skins")
    if int(_skin_bind_remap_report["renamed_binds"]) < ROLE_PAIRS.size():
        _failures.append("skin_remap_too_few_named_binds renamed=%d reviewed_roles=%d" % [int(_skin_bind_remap_report["renamed_binds"]), ROLE_PAIRS.size()])
    if missing != 0:
        _failures.append("skin_remap_missing_named_binds=%d" % missing)

    _write_skin_remap_report()
    print("GATE8_NATIVE_SKIN_REMAP meshes=%d skins=%d binds=%d renamed=%d missing=%d bind_count_unchanged=%s bind_poses_unchanged=%s bind_bones_unchanged=%s runtime_only=true" % [
        int(_skin_bind_remap_report["meshes"]),
        int(_skin_bind_remap_report["skins"]),
        int(_skin_bind_remap_report["binds"]),
        int(_skin_bind_remap_report["renamed_binds"]),
        missing,
        str(_skin_bind_remap_report["bind_count_unchanged"]),
        str(_skin_bind_remap_report["bind_poses_unchanged"]),
        str(_skin_bind_remap_report["bind_bone_indices_unchanged"])
    ])
    return _failures.is_empty()

func _write_skin_remap_report() -> void:
    var file := FileAccess.open("res://gate8_variant01_native_skin_remap_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("skin_remap_result_file_open_failed")
        return
    file.store_string(JSON.stringify(_skin_bind_remap_report, "  "))
    file.close()
