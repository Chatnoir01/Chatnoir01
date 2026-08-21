extends "res://game/tests/midi_civ1_vitruvian_capture_test.gd"

# Run 17 proved that a large local-Z pose delta can leave the imported body in
# a visible T-pose. Run 18 then proved why: Skeleton3D.get_bone_global_pose()
# is global to the skeleton, not to the scene. The character import carries a
# basis conversion, so a skeleton-space Y measurement did not describe what
# the player sees. Run 22 fixed the upper-arm silhouette but still read as a
# mannequin at 2 m because both elbows were perfectly straight. Run 23 added a
# bounded elbow bend, but the exact 1280x720 witness still showed a strongly
# bilateral mannequin stance: both upper arms measured an identical 0.20 world
# horizontal component. Run 25 fixed that bilateral arm symmetry; the remaining
# close-view mannequin cue is the perfectly square, dead-ahead head. Keep the
# proven arm chain and add one bounded world-space head yaw for an authored idle.
const LEFT_ARM_HORIZONTAL_COMPONENT := 0.17
const RIGHT_ARM_HORIZONTAL_COMPONENT := 0.23
const MIN_ARM_HORIZONTAL_ASYMMETRY := 0.04
const MIN_WORLD_DOWNWARD_COMPONENT := 0.92
const MAX_WORLD_HORIZONTAL_COMPONENT := 0.40
const MIN_ELBOW_BEND_DEG := 8.0
const MAX_ELBOW_BEND_DEG := 18.0
const AMBIENT_HEAD_YAW_DEG := 7.0
const MIN_HEAD_YAW_DEG := 5.0
const MAX_HEAD_YAW_DEG := 10.0

# Run 33 proved that synthetic ankle cylinders are visually unacceptable even
# when they pass mechanical placement gates. Use the pinned MakeHuman shoes03
# boot geometry instead. Scale X to a plausible pair width, Z to a plausible
# foot length, and let Y follow the same longitudinal scale so the authored boot
# shaft profile is preserved instead of being flattened or stretched by hand.
# Run 37 proved that 0.29 m longitudinal sizing still leaves a visible ankle band
# despite technical GREEN. Require a bounded authored shaft height above the sole
# while preserving the source profile with identical Y/Z scale.
const PRIMARY_FOOTWEAR := REVIEW_ROOT + "/shoes03_cc0.obj"
const TARGET_BOOT_PAIR_WIDTH_M := 0.38
const TARGET_BOOT_LENGTH_M := 0.32
const MIN_BOOT_HEIGHT_M := 0.275
const MAX_BOOT_HEIGHT_M := 0.305
const MAX_BOOT_SOLE_DRIFT_M := 0.001
const MAX_BOOT_PROFILE_SCALE_DRIFT := 0.000001

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
    var head := skeleton.find_bone("Head")
    if left < 0 or right < 0 or left_fore < 0 or right_fore < 0 or left_hand < 0 or right_hand < 0 or head < 0:
        var names: Array[String] = []
        for i in range(skeleton.get_bone_count()):
            names.append(skeleton.get_bone_name(i))
        var missing := {"applied": false, "reason": "expected arm/forearm/hand/head chain missing", "bone_names": names}
        print("GB_CIV1_POSE_WORLD ", JSON.stringify(missing))
        return missing

    var left_before := _bone_segment_world_direction(skeleton, left, left_fore)
    var right_before := _bone_segment_world_direction(skeleton, right, right_fore)
    var left_target := _natural_world_arm_target(left_before, LEFT_ARM_HORIZONTAL_COMPONENT)
    var right_target := _natural_world_arm_target(right_before, RIGHT_ARM_HORIZONTAL_COMPONENT)

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

    # Rotate the head in world space so the visible result is independent of the
    # imported armature basis conversion that invalidated the old local-Z pose.
    var head_pose := skeleton.get_bone_global_pose(head)
    var head_world := skeleton.global_transform * head_pose
    head_world.basis = Basis(Vector3.UP, deg_to_rad(AMBIENT_HEAD_YAW_DEG)) * head_world.basis
    var corrected_head_pose := skeleton.global_transform.affine_inverse() * head_world
    skeleton.set_bone_global_pose(head, corrected_head_pose)

    var left_horizontal := Vector2(left_after.x, left_after.z).length()
    var right_horizontal := Vector2(right_after.x, right_after.z).length()
    var arm_horizontal_asymmetry := absf(left_horizontal - right_horizontal)
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
        and arm_horizontal_asymmetry >= MIN_ARM_HORIZONTAL_ASYMMETRY
        and left_elbow_bend_deg >= MIN_ELBOW_BEND_DEG
        and left_elbow_bend_deg <= MAX_ELBOW_BEND_DEG
        and right_elbow_bend_deg >= MIN_ELBOW_BEND_DEG
        and right_elbow_bend_deg <= MAX_ELBOW_BEND_DEG
        and AMBIENT_HEAD_YAW_DEG >= MIN_HEAD_YAW_DEG
        and AMBIENT_HEAD_YAW_DEG <= MAX_HEAD_YAW_DEG
    )

    var applied := {
        "applied": measured_gate,
        "pose_space": "world",
        "alignment": "shortest_arc_asymmetric_upper_arms_plus_bounded_forearm_bend_plus_head_yaw",
        "left_bone": skeleton.get_bone_name(left),
        "right_bone": skeleton.get_bone_name(right),
        "left_forearm_bone": skeleton.get_bone_name(left_fore),
        "right_forearm_bone": skeleton.get_bone_name(right_fore),
        "left_hand_bone": skeleton.get_bone_name(left_hand),
        "right_hand_bone": skeleton.get_bone_name(right_hand),
        "head_bone": skeleton.get_bone_name(head),
        "head_yaw_deg": AMBIENT_HEAD_YAW_DEG,
        "minimum_head_yaw_deg": MIN_HEAD_YAW_DEG,
        "maximum_head_yaw_deg": MAX_HEAD_YAW_DEG,
        "left_target_horizontal_component": LEFT_ARM_HORIZONTAL_COMPONENT,
        "right_target_horizontal_component": RIGHT_ARM_HORIZONTAL_COMPONENT,
        "minimum_arm_horizontal_asymmetry": MIN_ARM_HORIZONTAL_ASYMMETRY,
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
        "arm_horizontal_asymmetry": arm_horizontal_asymmetry,
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
        "refines_world_upper_arm_run": 22,
        "refines_bounded_elbow_run": 23,
        "refines_asymmetric_arm_run": 25
    }
    if not measured_gate:
        applied["reason"] = "world-space authored idle did not reach head, asymmetry, upper-arm, and bounded elbow gates"
    print("GB_CIV1_POSE_WORLD ", JSON.stringify(applied))
    return applied

func _add_cc0_footwear(candidate: Node3D, body_bounds: AABB) -> Dictionary:
    candidate.set_meta("footwear_source", "furqonat/makehuman-assets@8cf9645b975a98eea056b140df11a1d278da0d10:base/clothes/shoes03/shoes03.obj")
    var shoe_mesh := ResourceLoader.load(PRIMARY_FOOTWEAR) as Mesh
    if shoe_mesh == null:
        return {"added": false, "reason": "primary shoes03 boot OBJ did not import as Mesh"}
    var source := shoe_mesh.get_aabb()
    if source.size.x <= 0.001 or source.size.y <= 0.001 or source.size.z <= 0.001:
        return {"added": false, "reason": "invalid shoes03 boot AABB", "source_aabb": str(source)}

    var node := MeshInstance3D.new()
    node.name = "Shoes03_CC0_Review"
    node.mesh = shoe_mesh
    node.set_meta("source", "furqonat/makehuman-assets@8cf9645b975a98eea056b140df11a1d278da0d10:base/clothes/shoes03/shoes03.obj")
    node.set_meta("license", "CC0-1.0")
    node.set_meta("production_authorized", false)
    candidate.add_child(node)

    var scale_x := TARGET_BOOT_PAIR_WIDTH_M / source.size.x
    var scale_z := TARGET_BOOT_LENGTH_M / source.size.z
    var scale_y := scale_z
    node.scale = Vector3(scale_x, scale_y, scale_z)

    var source_center := source.position + source.size * 0.5
    node.position.x = -source_center.x * node.scale.x
    node.position.z = -source_center.z * node.scale.z + 0.015
    var sole_y_before := body_bounds.position.y - 0.004
    node.position.y = sole_y_before - source.position.y * node.scale.y
    var sole_y_after := node.position.y + source.position.y * node.scale.y

    var shoe_mat := StandardMaterial3D.new()
    shoe_mat.albedo_color = Color(0.055, 0.052, 0.050)
    shoe_mat.roughness = 0.58
    shoe_mat.metallic = 0.0
    shoe_mat.metallic_specular = 0.20
    for surface in range(shoe_mesh.get_surface_count()):
        node.set_surface_override_material(surface, shoe_mat)

    var scaled_size := Vector3(
        source.size.x * node.scale.x,
        source.size.y * node.scale.y,
        source.size.z * node.scale.z
    )
    var sole_drift := absf(sole_y_after - sole_y_before)
    var boot_top_y := sole_y_after + scaled_size.y
    var boot_top_above_sole := boot_top_y - sole_y_after
    var profile_scale_drift := absf(node.scale.y - node.scale.z)
    var fit_gate := (
        boot_top_above_sole >= MIN_BOOT_HEIGHT_M
        and boot_top_above_sole <= MAX_BOOT_HEIGHT_M
        and sole_drift <= MAX_BOOT_SOLE_DRIFT_M
        and profile_scale_drift <= MAX_BOOT_PROFILE_SCALE_DRIFT
    )
    var audit := {
        "added": fit_gate,
        "source_asset": "base/clothes/shoes03/shoes03.obj",
        "source_aabb": str(source),
        "target_pair_width_m": TARGET_BOOT_PAIR_WIDTH_M,
        "target_length_m": TARGET_BOOT_LENGTH_M,
        "scaled_pair_size_m": [scaled_size.x, scaled_size.y, scaled_size.z],
        "boot_height_gate_m": [MIN_BOOT_HEIGHT_M, MAX_BOOT_HEIGHT_M],
        "boot_top_y": boot_top_y,
        "boot_top_above_sole_m": boot_top_above_sole,
        "vertical_scale_policy": "match_longitudinal_scale_preserve_authored_boot_profile",
        "profile_scale_drift": profile_scale_drift,
        "max_profile_scale_drift": MAX_BOOT_PROFILE_SCALE_DRIFT,
        "scale": [node.scale.x, node.scale.y, node.scale.z],
        "position": [node.position.x, node.position.y, node.position.z],
        "sole_y_before": sole_y_before,
        "sole_y_after": sole_y_after,
        "sole_drift_m": sole_drift,
        "max_sole_drift_m": MAX_BOOT_SOLE_DRIFT_M,
        "fit_gate": fit_gate,
        "synthetic_ankle_bridge": false,
        "manual_vertical_stretch": false,
        "source_commit": "8cf9645b975a98eea056b140df11a1d278da0d10",
        "license": "CC0-1.0",
        "production_authorized": false
    }
    if not fit_gate:
        audit["reason"] = "shoes03 authored profile outside bounded shaft-height/sole/profile gate"
    print("GB_CIV1_FOOTWEAR_BOOT ", JSON.stringify(audit))
    return audit

func _natural_world_arm_target(current: Vector3, horizontal_component: float) -> Vector3:
    var horizontal := Vector3(current.x, 0.0, current.z)
    if horizontal.length_squared() < 0.000001:
        horizontal = Vector3.RIGHT
    horizontal = horizontal.normalized()
    var downward := sqrt(maxf(0.0, 1.0 - horizontal_component * horizontal_component))
    return (horizontal * horizontal_component + Vector3.DOWN * downward).normalized()

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