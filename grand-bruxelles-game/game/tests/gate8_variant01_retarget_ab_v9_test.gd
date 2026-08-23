extends "res://game/tests/gate8_variant01_retarget_ab_v8_test.gd"

# v9 mirrors Godot 4.7.1 RetargetModifier3D's non-global-pose basis transfer.
# Unlike v6-v8, this stays in each bone's LOCAL pose space and explicitly
# converts between source/target parent-rest frames. Target rest translations
# remain authoritative for every non-hips bone, so target proportions cannot
# be replaced by source translations. Scale is never transferred.

const V9_SOLVER := "godot_native_non_global_pose_rotation_hips_translation_v9"
const V9_FORMULA := "target_parent_global_rest^-1 * source_parent_global_rest * source_pose * source_rest^-1 * source_parent_global_rest^-1 * target_parent_global_rest * target_rest"

func _native_target_local_basis(source_pose_basis: Basis, source_rest_basis: Basis, source_parent_global_rest_basis: Basis, target_rest_basis: Basis, target_parent_global_rest_basis: Basis) -> Basis:
    var pre_basis := target_parent_global_rest_basis.inverse() * source_parent_global_rest_basis
    var post_basis := source_rest_basis.inverse() * source_parent_global_rest_basis.inverse() * target_parent_global_rest_basis * target_rest_basis
    return (pre_basis * source_pose_basis * post_basis).orthonormalized()

func _regression_model_space_global_rest_identity() -> void:
    super._regression_model_space_global_rest_identity()

    # Non-commutative native-formula regression. This guards the exact parent
    # rest-frame conversion used by Godot 4.7.1 RetargetModifier3D and proves
    # that the rejected v8 global-rest transfer is not silently reintroduced.
    var source_parent_rest := Basis(Vector3(0.31, 0.77, 0.55).normalized(), 0.49)
    var target_parent_rest := Basis(Vector3(0.61, 0.25, 0.75).normalized(), -0.37)
    var source_rest := Basis(Vector3(0.17, 0.93, 0.32).normalized(), 0.28)
    var target_rest := Basis(Vector3(0.81, 0.14, 0.57).normalized(), -0.41)
    var source_pose := Basis(Vector3(0.24, 0.64, 0.73).normalized(), 0.36)
    var expected := (target_parent_rest.inverse() * source_parent_rest * source_pose * source_rest.inverse() * source_parent_rest.inverse() * target_parent_rest * target_rest).orthonormalized()
    var actual := _native_target_local_basis(source_pose, source_rest, source_parent_rest, target_rest, target_parent_rest)
    var rejected_v8 := (target_rest * (source_rest.inverse() * source_pose)).orthonormalized()
    var actual_error_deg := rad_to_deg(actual.get_rotation_quaternion().angle_to(expected.get_rotation_quaternion()))
    var rejected_delta_deg := rad_to_deg(rejected_v8.get_rotation_quaternion().angle_to(expected.get_rotation_quaternion()))
    if actual_error_deg > 0.0001:
        _failures.append("regression_native_retarget_formula_failed rotation=%.6f" % actual_error_deg)
    if rejected_delta_deg < 1.0:
        _failures.append("regression_does_not_distinguish_rejected_v8 rotation=%.6f" % rejected_delta_deg)

func _apply_retarget_pose() -> Dictionary:
    var max_error := 0.0
    var max_length_error := 0.0
    var max_non_hips_source_translation := 0.0

    for role: String in ROLE_ORDER:
        var source_idx := _source_index(role)
        var target_idx := _target_index(role)
        if source_idx < 0 or target_idx < 0:
            continue

        var source_pose := _source_skeleton.get_bone_pose(source_idx)
        var source_rest := _source_skeleton.get_bone_rest(source_idx)
        var target_rest := _target_skeleton.get_bone_rest(target_idx)
        var source_parent_idx := _source_skeleton.get_bone_parent(source_idx)
        var target_parent_idx := _target_skeleton.get_bone_parent(target_idx)
        var source_parent_global_rest_basis := Basis.IDENTITY
        var target_parent_global_rest_basis := Basis.IDENTITY
        if source_parent_idx >= 0:
            source_parent_global_rest_basis = _source_skeleton.get_bone_global_rest(source_parent_idx).basis
        if target_parent_idx >= 0:
            target_parent_global_rest_basis = _target_skeleton.get_bone_global_rest(target_parent_idx).basis

        var desired_basis := _native_target_local_basis(source_pose.basis, source_rest.basis, source_parent_global_rest_basis, target_rest.basis, target_parent_global_rest_basis)
        _target_skeleton.set_bone_pose_rotation(target_idx, desired_basis.get_rotation_quaternion())

        if role == "hips":
            var pre_basis := target_parent_global_rest_basis.inverse() * source_parent_global_rest_basis
            var source_delta := (source_pose.origin - source_rest.origin) * TARGET_TO_SOURCE_LEG_RATIO
            _target_skeleton.set_bone_pose_position(target_idx, target_rest.origin + pre_basis * source_delta)
        else:
            _target_skeleton.set_bone_pose_position(target_idx, target_rest.origin)
            max_non_hips_source_translation = maxf(max_non_hips_source_translation, source_pose.origin.distance_to(source_rest.origin))

        var applied_q := _target_skeleton.get_bone_pose_rotation(target_idx).normalized()
        var desired_q := desired_basis.get_rotation_quaternion().normalized()
        max_error = maxf(max_error, rad_to_deg(desired_q.angle_to(applied_q)))

    _target_skeleton.force_update_all_bone_transforms()

    for role: String in ROLE_ORDER:
        if role == "hips":
            continue
        var target_idx := _target_index(role)
        if target_idx < 0:
            continue
        var parent_idx := _target_skeleton.get_bone_parent(target_idx)
        if parent_idx < 0:
            _failures.append("mapped_non_hips_parent_missing role=%s" % role)
            continue
        var target_rest := _target_skeleton.get_bone_rest(target_idx)
        var child_origin := _target_skeleton.get_bone_global_pose(target_idx).origin
        var parent_origin := _target_skeleton.get_bone_global_pose(parent_idx).origin
        max_length_error = maxf(max_length_error, absf(child_origin.distance_to(parent_origin) - target_rest.origin.length()))

    return {
        "application_error_deg": max_error,
        "target_bone_length_error_m": max_length_error,
        "max_non_hips_source_translation_m": max_non_hips_source_translation
    }

func _write_result(result: Dictionary) -> void:
    # Keep the inherited write for compatibility/history, then stamp v9 and
    # persist once more. The previous implementation stamped only in memory
    # after super() had already written the v8-labelled JSON to disk.
    super._write_result(result)
    result["retarget_solver_revision"] = V9_SOLVER
    result["rotation_transfer_formula"] = V9_FORMULA
    result["retarget_reference"] = "Godot 4.7.1 RetargetModifier3D non-global-pose basis transfer"
    result["target_local_rest_positions_preserved"] = true
    result["solver_identity_guard"] = true
    var file := FileAccess.open("res://gate8_variant01_retarget_ab_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("v9_result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_VARIANT01_RETARGET_AB_OK candidate=01 clips=Jog_Fwd,Sprint solver=%s alias_selected=false production_authorized=false" % V9_SOLVER)
        quit(0)
        return
    print("GATE8_VARIANT01_RETARGET_AB_REJECTED candidate=01 solver=%s failures=%d alias_selected=false production_authorized=false" % [V9_SOLVER, _failures.size()])
    for failure: String in _failures:
        push_error("GATE8_VARIANT01_RETARGET_AB_FAIL %s" % failure)
    quit(1)
