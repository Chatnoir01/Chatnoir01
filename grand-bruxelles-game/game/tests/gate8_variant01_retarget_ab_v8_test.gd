extends "res://game/tests/gate8_variant01_retarget_ab_test.gd"

# v8 fixes the model-space rotation transfer order. A source pose is represented
# as source_rest * delta, therefore the target pose must be target_rest * delta.
# The previous v7 order (source_pose * source_rest^-1 * target_rest) mixed the
# source and target rest frames and produced catastrophically folded limbs.

func _model_space_target_basis(source_global_pose_basis: Basis, source_global_rest_basis: Basis, target_global_rest_basis: Basis) -> Basis:
    var source_rest_relative_delta := (source_global_rest_basis.inverse() * source_global_pose_basis).orthonormalized()
    return (target_global_rest_basis * source_rest_relative_delta).orthonormalized()

func _regression_model_space_global_rest_identity() -> void:
    super._regression_model_space_global_rest_identity()

    # Non-commutative regression: this must distinguish v8 from the rejected v7
    # multiplication order, not merely pass the rest==pose identity case.
    var source_rest := Basis(Vector3(0.31, 0.82, 0.47).normalized(), 0.71)
    var target_rest := Basis(Vector3(0.73, 0.19, 0.66).normalized(), -0.58)
    var local_delta := Basis(Vector3(0.12, 0.96, 0.25).normalized(), 0.43)
    var source_pose := (source_rest * local_delta).orthonormalized()
    var expected := (target_rest * local_delta).orthonormalized()
    var actual := _model_space_target_basis(source_pose, source_rest, target_rest)
    var rejected_v7 := (source_pose * source_rest.inverse() * target_rest).orthonormalized()

    var actual_error_deg := rad_to_deg(actual.get_rotation_quaternion().angle_to(expected.get_rotation_quaternion()))
    var rejected_delta_deg := rad_to_deg(rejected_v7.get_rotation_quaternion().angle_to(expected.get_rotation_quaternion()))
    if actual_error_deg > 0.0001:
        _failures.append("regression_rest_frame_delta_transfer_failed rotation=%.6f" % actual_error_deg)
    if rejected_delta_deg < 1.0:
        _failures.append("regression_does_not_distinguish_rejected_v7 rotation=%.6f" % rejected_delta_deg)

func _write_result(result: Dictionary) -> void:
    result["retarget_solver_revision"] = "rest_frame_delta_target_lengths_v8"
    result["rotation_transfer_formula"] = "target_global_rest_basis * (source_global_rest_basis^-1 * source_global_pose_basis)"
    super._write_result(result)

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_VARIANT01_RETARGET_AB_OK candidate=01 clips=Jog_Fwd,Sprint solver=rest_frame_delta_target_lengths_v8 alias_selected=false production_authorized=false")
        quit(0)
        return
    for failure: String in _failures:
        push_error("GATE8_VARIANT01_RETARGET_AB_FAIL %s" % failure)
    quit(1)
