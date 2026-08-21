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

# Run 30 proved the sole-preserving approach is mechanically correct, but the
# real feet/ground and 2 m frames still show a conspicuous bare-ankle band above
# the CC0 shoe. Preserve the exact source sole plane and extend only the shoe's
# vertical collar enough to cover part of the visible ankle, with a measured
# top-lift gate. Run 32 still leaves a skin-colored strip. Do not stretch the
# shoe any further: add a tiny review-only dark sock bridge instead, positioned
# from the actual LeftFoot/RightFoot bones, with no body/skeleton/sole mutation.
const FOOTWEAR_HEIGHT_SCALE := 1.48
const MIN_FOOTWEAR_HEIGHT_SCALE := 1.40
const MAX_FOOTWEAR_HEIGHT_SCALE := 1.55
const MAX_FOOTWEAR_SOLE_DRIFT_M := 0.001
const MIN_FOOTWEAR_FINAL_HEIGHT_M := 0.165
const MAX_FOOTWEAR_FINAL_HEIGHT_M := 0.185
const MIN_FOOTWEAR_TOP_LIFT_M := 0.045
const MAX_FOOTWEAR_TOP_LIFT_M := 0.065
const ANKLE_BRIDGE_HEIGHT_M := 0.105
const ANKLE_BRIDGE_OVERLAP_M := 0.018
const ANKLE_BRIDGE_BOTTOM_RADIUS_M := 0.050
const ANKLE_BRIDGE_TOP_RADIUS_M := 0.056
const MIN_ANKLE_BRIDGE_HEIGHT_M := 0.085
const MAX_ANKLE_BRIDGE_HEIGHT_M := 0.120
const MIN_ANKLE_BRIDGE_OVERLAP_M := 0.010
const MAX_ANKLE_BRIDGE_OVERLAP_M := 0.025

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
    var audit := super._add_cc0_footwear(candidate, body_bounds)
    if not bool(audit.get("added", false)):
        return audit
    var shoes := candidate.get_node_or_null("Shoes04_CC0_Review") as MeshInstance3D
    if shoes == null or shoes.mesh == null:
        return {"added": false, "reason": "review footwear node/mesh missing after parent staging"}

    var source := shoes.mesh.get_aabb()
    var sole_y_before := shoes.position.y + source.position.y * shoes.scale.y
    var top_y_before := shoes.position.y + (source.position.y + source.size.y) * shoes.scale.y
    var height_before := source.size.y * shoes.scale.y
    shoes.scale.y *= FOOTWEAR_HEIGHT_SCALE
    shoes.position.y = sole_y_before - source.position.y * shoes.scale.y
    var sole_y_after := shoes.position.y + source.position.y * shoes.scale.y
    var top_y_after := shoes.position.y + (source.position.y + source.size.y) * shoes.scale.y
    var height_after := source.size.y * shoes.scale.y
    var sole_drift := absf(sole_y_after - sole_y_before)
    var top_lift := top_y_after - top_y_before

    var fit_gate := (
        FOOTWEAR_HEIGHT_SCALE >= MIN_FOOTWEAR_HEIGHT_SCALE
        and FOOTWEAR_HEIGHT_SCALE <= MAX_FOOTWEAR_HEIGHT_SCALE
        and height_after >= MIN_FOOTWEAR_FINAL_HEIGHT_M
        and height_after <= MAX_FOOTWEAR_FINAL_HEIGHT_M
        and top_lift >= MIN_FOOTWEAR_TOP_LIFT_M
        and top_lift <= MAX_FOOTWEAR_TOP_LIFT_M
        and sole_drift <= MAX_FOOTWEAR_SOLE_DRIFT_M
    )
    audit["footwear_height_scale"] = FOOTWEAR_HEIGHT_SCALE
    audit["footwear_height_scale_range"] = [MIN_FOOTWEAR_HEIGHT_SCALE, MAX_FOOTWEAR_HEIGHT_SCALE]
    audit["shoe_height_before_m"] = height_before
    audit["shoe_height_after_m"] = height_after
    audit["shoe_height_gate_m"] = [MIN_FOOTWEAR_FINAL_HEIGHT_M, MAX_FOOTWEAR_FINAL_HEIGHT_M]
    audit["shoe_top_y_before_fit"] = top_y_before
    audit["shoe_top_y_after_fit"] = top_y_after
    audit["shoe_top_lift_m"] = top_lift
    audit["shoe_top_lift_gate_m"] = [MIN_FOOTWEAR_TOP_LIFT_M, MAX_FOOTWEAR_TOP_LIFT_M]
    audit["sole_y_before_fit"] = sole_y_before
    audit["sole_y_after_fit"] = sole_y_after
    audit["sole_drift_m"] = sole_drift
    audit["max_sole_drift_m"] = MAX_FOOTWEAR_SOLE_DRIFT_M

    var bridge_audit := _add_review_ankle_bridges(candidate, top_y_after)
    var bridge_gate := bool(bridge_audit.get("added", false))
    audit["ankle_bridge"] = bridge_audit
    audit["fit_gate"] = fit_gate and bridge_gate
    if not bool(audit["fit_gate"]):
        audit["added"] = false
        audit["reason"] = "footwear or ankle-bridge fit outside bounded review gate"
    print("GB_CIV1_FOOTWEAR_FIT ", JSON.stringify(audit))
    return audit

func _add_review_ankle_bridges(candidate: Node3D, shoe_top_y: float) -> Dictionary:
    var skeleton := _find_skeleton(candidate)
    if skeleton == null:
        return {"added": false, "reason": "Skeleton3D missing for ankle bridge placement"}
    var left_foot := skeleton.find_bone("LeftFoot")
    var right_foot := skeleton.find_bone("RightFoot")
    if left_foot < 0 or right_foot < 0:
        return {"added": false, "reason": "LeftFoot/RightFoot bones missing"}

    var height_gate := ANKLE_BRIDGE_HEIGHT_M >= MIN_ANKLE_BRIDGE_HEIGHT_M and ANKLE_BRIDGE_HEIGHT_M <= MAX_ANKLE_BRIDGE_HEIGHT_M
    var overlap_gate := ANKLE_BRIDGE_OVERLAP_M >= MIN_ANKLE_BRIDGE_OVERLAP_M and ANKLE_BRIDGE_OVERLAP_M <= MAX_ANKLE_BRIDGE_OVERLAP_M
    if not height_gate or not overlap_gate:
        return {"added": false, "reason": "ankle bridge dimensions outside gate"}

    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.035, 0.035, 0.045)
    mat.roughness = 0.96
    mat.metallic = 0.0
    mat.cull_mode = BaseMaterial3D.CULL_DISABLED

    var center_y := shoe_top_y + ANKLE_BRIDGE_HEIGHT_M * 0.5 - ANKLE_BRIDGE_OVERLAP_M
    var names := ["LeftAnkleBridge_Review", "RightAnkleBridge_Review"]
    var bones := [left_foot, right_foot]
    var positions: Array = []
    for i in range(2):
        var bone_world := skeleton.to_global(skeleton.get_bone_global_pose(int(bones[i])).origin)
        var local_foot := candidate.to_local(bone_world)
        var mesh := CylinderMesh.new()
        mesh.top_radius = ANKLE_BRIDGE_TOP_RADIUS_M
        mesh.bottom_radius = ANKLE_BRIDGE_BOTTOM_RADIUS_M
        mesh.height = ANKLE_BRIDGE_HEIGHT_M
        mesh.radial_segments = 24
        mesh.rings = 1
        mesh.cap_top = true
        mesh.cap_bottom = true
        var bridge := MeshInstance3D.new()
        bridge.name = str(names[i])
        bridge.mesh = mesh
        bridge.material_override = mat
        bridge.position = Vector3(local_foot.x, center_y, local_foot.z)
        bridge.set_meta("review_only", true)
        bridge.set_meta("production_authorized", false)
        bridge.set_meta("purpose", "cover_visible_ankle_gap_without_mutating_source_shoe")
        candidate.add_child(bridge)
        positions.append([bridge.position.x, bridge.position.y, bridge.position.z])

    var top_y := center_y + ANKLE_BRIDGE_HEIGHT_M * 0.5
    var bottom_y := center_y - ANKLE_BRIDGE_HEIGHT_M * 0.5
    var overlap_actual := shoe_top_y - bottom_y
    var added_gate := candidate.get_node_or_null("LeftAnkleBridge_Review") != null and candidate.get_node_or_null("RightAnkleBridge_Review") != null
    var audit := {
        "added": added_gate,
        "review_only": true,
        "production_authorized": false,
        "count": 2,
        "height_m": ANKLE_BRIDGE_HEIGHT_M,
        "height_gate_m": [MIN_ANKLE_BRIDGE_HEIGHT_M, MAX_ANKLE_BRIDGE_HEIGHT_M],
        "overlap_m": overlap_actual,
        "overlap_gate_m": [MIN_ANKLE_BRIDGE_OVERLAP_M, MAX_ANKLE_BRIDGE_OVERLAP_M],
        "bottom_radius_m": ANKLE_BRIDGE_BOTTOM_RADIUS_M,
        "top_radius_m": ANKLE_BRIDGE_TOP_RADIUS_M,
        "shoe_top_y": shoe_top_y,
        "bridge_bottom_y": bottom_y,
        "bridge_top_y": top_y,
        "positions": positions,
        "placement_source": "LeftFoot/RightFoot bone xz plus sole-preserving shoe top",
        "body_changed": false,
        "skeleton_changed": false,
        "sole_changed": false
    }
    print("GB_CIV1_ANKLE_BRIDGE ", JSON.stringify(audit))
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
