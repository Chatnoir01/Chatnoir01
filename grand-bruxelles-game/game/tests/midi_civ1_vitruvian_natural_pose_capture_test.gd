extends "res://game/tests/midi_civ1_vitruvian_capture_test.gd"

# Run 17 proved that a large local-Z pose delta can leave the imported body in
# a visible T-pose. Run 18 then proved why: Skeleton3D.get_bone_global_pose()
# is global to the skeleton, not to the scene. The character import carries a
# basis conversion, so a skeleton-space Y measurement did not describe what
# the player sees. Run 22 fixed the upper-arm silhouette but still read as a
# mannequin at 2 m because both elbows were perfectly straight. This review
# pose therefore adds one bounded, measured forearm bend in world space.
const TARGET_ARM_HORIZONTAL_COMPONENT := 0.20
const MIN_WORLD_DOWNWARD_COMPONENT := 0.92
const MAX_WORLD_HORIZONTAL_COMPONENT := 0.40
const MIN_ELBOW_BEND_DEG := 8.0
const MAX_ELBOW_BEND_DEG := 18.0

func _relax_pose_if_rigged(root: Node) -> Dictionary:
    var skeleton := _find_skeleton(root)
    if skeleton == null:
        var no_rig := {"applied": false, "reason": "body export is static/baked; no Skeleton3D"}
        print("GB_CIV1_POSE_WORLD ", JSON.stringify(no_rig))
        return no_rig

    var left := skeleton.find_bone("LeftArm")
    var right := skeleton.find_bone("RightArm")
    var left_fore := skeleton.find_bone("LeftForeArm")
    var right_fore := skeleton.find_bone("RightForeArm")
    var left_hand := skeleton.find_bone("LeftHand")
    var right_hand := skeleton.find_bone("RightHand")
    if left < 0 or right < 0 or left_fore < 0 or right_fore < 0 or left_hand < 0 or right_hand < 0:
        var names: Array[String] = []
        for i in range(skeleton.get_bone_count()):
            names.append(skeleton.get_bone_name(i))
        var missing := {"applied": false, "reason": "expected arm/forearm/hand chain missing", "bone_names": names}
        print("GB_CIV1_POSE_WORLD ", JSON.stringify(missing))
        return missing

    var left_before := _bone_segment_world_direction(skeleton, left, left_fore)
    var right_before := _bone_segment_world_direction(skeleton, right, right_fore)
    var left_target := _natural_world_arm_target(left_before)
    var right_target := _natural_world_arm_target(right_before)

    _align_bone_segment_in_world(skeleton, left, left_before, left_target)
    _align_bone_segment_in_world(skeleton, right, right_before, right_target)

    var left_after := _bone_segment_world_direction(skeleton, left, left_fore)
    var right_after := _bone_segment_world_direction(skeleton, right, right_fore)

    var left_fore_before := _bone_segment_world_direction(skeleton, left_fore, left_hand)
    var right_fore_before := _bone_segment_world_direction(skeleton, right_fore, right_hand)
    var left_fore_target := Vector3(0.08, -1.0, 0.18).normalized()
    var right_fore_target := Vector3(-0.06, -1.0, 0.16).normalized()
    _align_bone_segment_in_world(skeleton, left_fore, left_fore_before, left_fore_target)
    _align_bone_segment_in_world(skeleton, right_fore, right_fore_before, right_fore_target)
    var left_fore_after := _bone_segment_world_direction(skeleton, left_fore, left_hand)
    var right_fore_after := _bone_segment_world_direction(skeleton, right_fore, right_hand)

    var left_horizontal := Vector2(left_after.x, left_after.z).length()
    var right_horizontal := Vector2(right_after.x, right_after.z).length()
    var left_elbow_bend_deg := _angle_degrees(left_after, left_fore_after)
    var right_elbow_bend_deg := _angle_degrees(right_after, right_fore_after)
    # Keep the parent witness' historical "upper-arm drop" contract, but derive
    # it from what the player actually sees: degrees below the world horizontal.
    var left_drop_below_horizontal_deg := rad_to_deg(asin(clampf(-left_after.y, -1.0, 1.0)))
    var right_drop_below_horizontal_deg := rad_to_deg(asin(clampf(-right_after.y, -1.0, 1.0)))
    var visual_drop_below_horizontal_deg := minf(left_drop_below_horizontal_deg, right_drop_below_horizontal_deg)
    var measured_gate := (
        -left_after.y >= MIN_WORLD_DOWNWARD_COMPONENT
        and -right_after.y >= MIN_WORLD_DOWNWARD_COMPONENT
        and left_horizontal <= MAX_WORLD_HORIZONTAL_COMPONENT
        and right_horizontal <= MAX_WORLD_HORIZONTAL_COMPONENT
        and left_elbow_bend_deg >= MIN_ELBOW_BEND_DEG
        and left_elbow_bend_deg <= MAX_ELBOW_BEND_DEG
        and right_elbow_bend_deg >= MIN_ELBOW_BEND_DEG
        and right_elbow_bend_deg <= MAX_ELBOW_BEND_DEG
    )

    var applied := {
        "applied": measured_gate,
        "pose_space": "world",
        "alignment": "shortest_arc_upper_arms_plus_bounded_forearm_bend",
        "left_bone": skeleton.get_bone_name(left),
        "right_bone": skeleton.get_bone_name(right),
        "left_forearm_bone": skeleton.get_bone_name(left_fore),
        "right_forearm_bone": skeleton.get_bone_name(right_fore),
        "left_hand_bone": skeleton.get_bone_name(left_hand),
        "right_hand_bone": skeleton.get_bone_name(right_hand),
        "target_horizontal_component": TARGET_ARM_HORIZONTAL_COMPONENT,
        "minimum_world_downward_component": MIN_WORLD_DOWNWARD_COMPONENT,
        "maximum_world_horizontal_component": MAX_WORLD_HORIZONTAL_COMPONENT,
        "minimum_elbow_bend_deg": MIN_ELBOW_BEND_DEG,
        "maximum_elbow_bend_deg": MAX_ELBOW_BEND_DEG,
        "left_direction_before_world": _vec3_array(left_before),
        "right_direction_before_world": _vec3_array(right_before),
        "left_target_world": _vec3_array(left_target),
        "right_target_world": _vec3_array(right_target),
        "left_direction_after_world": _vec3_array(left_after),
        "right_direction_after_world": _vec3_array(right_after),
        "left_horizontal_after": left_horizontal,
        "right_horizontal_after": right_horizontal,
        "left_forearm_before_world": _vec3_array(left_fore_before),
        "right_forearm_before_world": _vec3_array(right_fore_before),
        "left_forearm_target_world": _vec3_array(left_fore_target),
        "right_forearm_target_world": _vec3_array(right_fore_target),
        "left_forearm_after_world": _vec3_array(left_fore_after),
        "right_forearm_after_world": _vec3_array(right_fore_after),
        "left_elbow_bend_deg": left_elbow_bend_deg,
        "right_elbow_bend_deg": right_elbow_bend_deg,
        "left_drop_below_horizontal_deg": left_drop_below_horizontal_deg,
        "right_drop_below_horizontal_deg": right_drop_below_horizontal_deg,
        "extra_upper_arm_degrees": visual_drop_below_horizontal_deg,
        "source_authoring_reference": "ibrews/VitruvianGodot blender_prep/_pose_export.py armature-global arm lowering",
        "replaces_rejected_local_z_run": 17,
        "replaces_rejected_skeleton_global_run": 18,
        "refines_world_upper_arm_run": 22
    }
    if not measured_gate:
        applied["reason"] = "world-space arm chain did not reach upper-arm and bounded elbow gates"
    print("GB_CIV1_POSE_WORLD ", JSON.stringify(applied))
    return applied

func _natural_world_arm_target(current: Vector3) -> Vector3:
    var horizontal := Vector3(current.x, 0.0, current.z)
    if horizontal.length_squared() < 0.000001:
        horizontal = Vector3.RIGHT
    horizontal = horizontal.normalized()
    var downward := sqrt(maxf(0.0, 1.0 - TARGET_ARM_HORIZONTAL_COMPONENT * TARGET_ARM_HORIZONTAL_COMPONENT))
    return (horizontal * TARGET_ARM_HORIZONTAL_COMPONENT + Vector3.DOWN * downward).normalized()

func _align_bone_segment_in_world(skeleton: Skeleton3D, bone: int, current: Vector3, target: Vector3) -> void:
    var from_dir := current.normalized()
    var to_dir := target.normalized()
    var dot_value := clampf(from_dir.dot(to_dir), -1.0, 1.0)
    if dot_value > 0.99999:
        return
    var axis := from_dir.cross(to_dir)
    if axis.length_squared() < 0.000001:
        axis = from_dir.cross(Vector3.UP)
        if axis.length_squared() < 0.000001:
            axis = Vector3.RIGHT
    axis = axis.normalized()
    var angle := acos(dot_value)

    var skeleton_pose := skeleton.get_bone_global_pose(bone)
    var world_pose := skeleton.global_transform * skeleton_pose
    var world_delta := Basis(axis, angle)
    world_pose.basis = world_delta * world_pose.basis
    var corrected_pose := skeleton.global_transform.affine_inverse() * world_pose
    skeleton.set_bone_global_pose(bone, corrected_pose)

func _bone_segment_world_direction(skeleton: Skeleton3D, bone: int, child: int) -> Vector3:
    var a := skeleton.to_global(skeleton.get_bone_global_pose(bone).origin)
    var b := skeleton.to_global(skeleton.get_bone_global_pose(child).origin)
    var segment := b - a
    return segment.normalized() if segment.length_squared() > 0.000001 else Vector3.ZERO

func _angle_degrees(a: Vector3, b: Vector3) -> float:
    return rad_to_deg(acos(clampf(a.normalized().dot(b.normalized()), -1.0, 1.0)))

func _vec3_array(value: Vector3) -> Array:
    return [value.x, value.y, value.z]
