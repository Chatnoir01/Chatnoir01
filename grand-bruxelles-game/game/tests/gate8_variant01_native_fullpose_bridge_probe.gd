extends "res://game/tests/gate8_variant01_native_retarget_ab_test.gd"

# Diagnostic only: keep the native RetargetModifier3D and every production rail
# unchanged, but mirror the complete proxy local pose into the real skinned target.
# If the rendered mesh becomes correct, the old 22-rotation bridge was the defect.
# If it stays deformed, the defect is upstream in native retarget/profile topology.

var _bridge_max_position_error_m := 0.0
var _bridge_max_rotation_error_deg := 0.0
var _bridge_max_scale_error := 0.0

func _copy_proxy_rotations_to_target() -> void:
    if _proxy_skeleton.get_bone_count() != _target_skeleton.get_bone_count():
        _failures.append("fullpose_bridge_bone_count_mismatch")
        return

    for proxy_idx: int in range(_proxy_skeleton.get_bone_count()):
        var bone_name := String(_proxy_skeleton.get_bone_name(proxy_idx))
        var target_idx := _target_skeleton.find_bone(bone_name)
        if target_idx < 0:
            _failures.append("fullpose_bridge_target_bone_missing=%s" % bone_name)
            continue
        _target_skeleton.set_bone_pose_position(target_idx, _proxy_skeleton.get_bone_pose_position(proxy_idx))
        _target_skeleton.set_bone_pose_rotation(target_idx, _proxy_skeleton.get_bone_pose_rotation(proxy_idx))
        _target_skeleton.set_bone_pose_scale(target_idx, _proxy_skeleton.get_bone_pose_scale(proxy_idx))

    _target_skeleton.force_update_all_bone_transforms()
    _measure_fullpose_bridge_fidelity()

func _measure_fullpose_bridge_fidelity() -> void:
    for proxy_idx: int in range(_proxy_skeleton.get_bone_count()):
        var bone_name := String(_proxy_skeleton.get_bone_name(proxy_idx))
        var target_idx := _target_skeleton.find_bone(bone_name)
        if target_idx < 0:
            continue

        var proxy_pose := _proxy_skeleton.get_bone_global_pose(proxy_idx)
        var target_pose := _target_skeleton.get_bone_global_pose(target_idx)
        _bridge_max_position_error_m = maxf(_bridge_max_position_error_m, proxy_pose.origin.distance_to(target_pose.origin))
        _bridge_max_rotation_error_deg = maxf(
            _bridge_max_rotation_error_deg,
            rad_to_deg(proxy_pose.basis.get_rotation_quaternion().angle_to(target_pose.basis.get_rotation_quaternion()))
        )
        _bridge_max_scale_error = maxf(
            _bridge_max_scale_error,
            (proxy_pose.basis.get_scale() - target_pose.basis.get_scale()).length()
        )

    if _bridge_max_position_error_m > 0.0005:
        _append_bridge_failure_once("fullpose_bridge_position_error=%.6f" % _bridge_max_position_error_m)
    if _bridge_max_rotation_error_deg > 0.05:
        _append_bridge_failure_once("fullpose_bridge_rotation_error_deg=%.6f" % _bridge_max_rotation_error_deg)
    if _bridge_max_scale_error > 0.0005:
        _append_bridge_failure_once("fullpose_bridge_scale_error=%.6f" % _bridge_max_scale_error)

func _append_bridge_failure_once(message: String) -> void:
    for failure: String in _failures:
        if failure.begins_with(message.get_slice("=", 0)):
            return
    _failures.append(message)

func _finish() -> void:
    print("GATE8_NATIVE_FULLPOSE_BRIDGE fidelity_position_m=%.6f fidelity_rotation_deg=%.6f fidelity_scale=%.6f" % [
        _bridge_max_position_error_m,
        _bridge_max_rotation_error_deg,
        _bridge_max_scale_error
    ])
    super._finish()
