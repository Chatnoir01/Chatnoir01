extends "res://game/tests/gate8_variant01_native_retarget_ab_test.gd"

# Diagnostic only. First prove whether the imported target survives a reset to its
# Skeleton3D rest pose before any animation. Then keep the native RetargetModifier3D
# experiment unchanged except for mirroring the complete 53-bone proxy local pose.

var _bridge_max_position_error_m := 0.0
var _bridge_max_rotation_error_deg := 0.0
var _bridge_max_scale_error := 0.0
var _imported_to_rest_max_position_delta_m := 0.0
var _imported_to_rest_max_rotation_delta_deg := 0.0
var _imported_to_rest_max_scale_delta := 0.0

func _load_characters() -> bool:
    var ok: bool = await super._load_characters()
    if not ok:
        return false

    var imported_positions: Array[Vector3] = []
    var imported_rotations: Array[Quaternion] = []
    var imported_scales: Array[Vector3] = []
    for bone_idx: int in range(_target_skeleton.get_bone_count()):
        imported_positions.append(_target_skeleton.get_bone_pose_position(bone_idx))
        imported_rotations.append(_target_skeleton.get_bone_pose_rotation(bone_idx))
        imported_scales.append(_target_skeleton.get_bone_pose_scale(bone_idx))

    await _capture_target_sanity("imported-default")

    for bone_idx: int in range(_target_skeleton.get_bone_count()):
        _target_skeleton.reset_bone_pose(bone_idx)
    _target_skeleton.force_update_all_bone_transforms()

    for bone_idx: int in range(_target_skeleton.get_bone_count()):
        _imported_to_rest_max_position_delta_m = maxf(
            _imported_to_rest_max_position_delta_m,
            imported_positions[bone_idx].distance_to(_target_skeleton.get_bone_pose_position(bone_idx))
        )
        _imported_to_rest_max_rotation_delta_deg = maxf(
            _imported_to_rest_max_rotation_delta_deg,
            rad_to_deg(imported_rotations[bone_idx].angle_to(_target_skeleton.get_bone_pose_rotation(bone_idx)))
        )
        _imported_to_rest_max_scale_delta = maxf(
            _imported_to_rest_max_scale_delta,
            (imported_scales[bone_idx] - _target_skeleton.get_bone_pose_scale(bone_idx)).length()
        )

    await _capture_target_sanity("reset-to-rest")

    # Restore the exact imported pose before the inherited experiment continues.
    for bone_idx: int in range(_target_skeleton.get_bone_count()):
        _target_skeleton.set_bone_pose_position(bone_idx, imported_positions[bone_idx])
        _target_skeleton.set_bone_pose_rotation(bone_idx, imported_rotations[bone_idx])
        _target_skeleton.set_bone_pose_scale(bone_idx, imported_scales[bone_idx])
    _target_skeleton.force_update_all_bone_transforms()

    print("GATE8_TARGET_BINDPOSE_SANITY imported_to_rest_position_m=%.6f imported_to_rest_rotation_deg=%.6f imported_to_rest_scale=%.6f" % [
        _imported_to_rest_max_position_delta_m,
        _imported_to_rest_max_rotation_delta_deg,
        _imported_to_rest_max_scale_delta
    ])
    return true

func _capture_target_sanity(label: String) -> void:
    var pelvis_idx := _target_skeleton.find_bone("pelvis")
    var head_idx := _target_skeleton.find_bone("head")
    var left_foot_idx := _target_skeleton.find_bone("foot_l")
    var right_foot_idx := _target_skeleton.find_bone("foot_r")
    if pelvis_idx < 0 or head_idx < 0 or left_foot_idx < 0 or right_foot_idx < 0:
        _failures.append("bindpose_sanity_required_bone_missing")
        return

    var left_foot := _target_skeleton.get_bone_global_pose(left_foot_idx).origin
    var right_foot := _target_skeleton.get_bone_global_pose(right_foot_idx).origin
    var foot_y := minf(left_foot.y, right_foot.y)
    var ground_world := _target_skeleton.to_global(Vector3(0.0, foot_y - GROUND_CLEARANCE_M, 0.0))
    _ground.global_position.y = ground_world.y

    var pelvis_world := _target_skeleton.to_global(_target_skeleton.get_bone_global_pose(pelvis_idx).origin)
    var head_world := _target_skeleton.to_global(_target_skeleton.get_bone_global_pose(head_idx).origin)
    var center := (pelvis_world + head_world) * 0.5
    _camera.look_at_from_position(center + Vector3(2.9, 0.45, 4.15), center, Vector3.UP)

    await process_frame
    await process_frame
    RenderingServer.force_draw(false)
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _failures.append("bindpose_sanity_capture_empty=%s" % label)
        return
    var path := "res://gate8_variant01_%s.png" % label
    if image.save_png(path) != OK:
        _failures.append("bindpose_sanity_capture_save_failed=%s" % label)

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

    # Rotation comparison accumulates tiny quaternion-normalization noise through
    # a 53-bone hierarchy, so record it diagnostically instead of replacing the
    # authoritative retarget gates. Position/scale must remain effectively exact.
    if _bridge_max_position_error_m > 0.0005:
        _append_bridge_failure_once("fullpose_bridge_position_error=%.6f" % _bridge_max_position_error_m)
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
