extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const PROBE_ROLE := "left_upper_arm"
const PROBE_DEGREES := 20.0
const MIN_TRANSFER_DEGREES := 1.0
const MAX_TRANSFER_ABS_ERROR_DEGREES := 3.0
const MIN_TRANSFER_GAIN := 0.85
const MAX_TRANSFER_GAIN := 1.15
const MAX_RESET_DEGREES := 0.25
const MAX_SOURCE_REST_BASELINE_ERROR_DEGREES := 0.05
const SETTLE_FRAMES := 2
const ROLE_PAIRS := {"hips":["DEF-hips","pelvis"],"spine":["DEF-spine.001","spine_01"],"chest":["DEF-spine.002","spine_02"],"upper_chest":["DEF-spine.003","spine_03"],"neck":["DEF-neck","neck_01"],"head":["DEF-head","head"],"left_shoulder":["DEF-shoulder.L","clavicle_l"],"left_upper_arm":["DEF-upper_arm.L","upperarm_l"],"left_forearm":["DEF-forearm.L","lowerarm_l"],"left_hand":["DEF-hand.L","hand_l"],"right_shoulder":["DEF-shoulder.R","clavicle_r"],"right_upper_arm":["DEF-upper_arm.R","upperarm_r"],"right_forearm":["DEF-forearm.R","lowerarm_r"],"right_hand":["DEF-hand.R","hand_r"],"left_upper_leg":["DEF-thigh.L","thigh_l"],"left_lower_leg":["DEF-shin.L","calf_l"],"left_foot":["DEF-foot.L","foot_l"],"left_toe":["DEF-toe.L","ball_l"],"right_upper_leg":["DEF-thigh.R","thigh_r"],"right_lower_leg":["DEF-shin.R","calf_r"],"right_foot":["DEF-foot.R","foot_r"],"right_toe":["DEF-toe.R","ball_r"]}
const ROLE_PARENT := {"hips":"","spine":"hips","chest":"spine","upper_chest":"chest","neck":"upper_chest","head":"neck","left_shoulder":"upper_chest","left_upper_arm":"left_shoulder","left_forearm":"left_upper_arm","left_hand":"left_forearm","right_shoulder":"upper_chest","right_upper_arm":"right_shoulder","right_forearm":"right_upper_arm","right_hand":"right_forearm","left_upper_leg":"hips","left_lower_leg":"left_upper_leg","left_foot":"left_lower_leg","left_toe":"left_foot","right_upper_leg":"hips","right_lower_leg":"right_upper_leg","right_foot":"right_lower_leg","right_toe":"right_foot"}
var _failures: Array[String] = []
func _init() -> void: call_deferred("_run")
func _run() -> void:
    var source_scene := _instantiate(SOURCE_SCENE); var target_scene := _instantiate(TARGET_SCENE)
    if source_scene == null or target_scene == null: _finish({}); return
    root.add_child(source_scene); root.add_child(target_scene); await process_frame
    var source_real := _find_skeleton(source_scene); var target_real := _find_skeleton(target_scene)
    if source_real == null or target_real == null: _failures.append("real_skeleton_missing"); _finish({}); return
    var source := _clone_skeleton_data(source_real); var target := _clone_skeleton_data(target_real)
    var source_bone_count := source.get_bone_count(); var target_bone_count := target.get_bone_count()
    source_scene.queue_free(); target_scene.queue_free(); await process_frame
    source.name="CanonicalSourceSkeleton"; target.name="CanonicalTargetSkeleton"; root.add_child(source); await process_frame
    if source.get_child_count()!=0 or target.get_child_count()!=0: _failures.append("probe_skeleton_not_skinless")
    var source_rest_snapshot:=_snapshot_rests(source,0); var target_rest_snapshot:=_snapshot_rests(target,1)
    var source_renamed:=_canonicalize(source,0); var target_renamed:=_canonicalize(target,1)
    _verify_rests(source,source_rest_snapshot,"source"); _verify_rests(target,target_rest_snapshot,"target")
    var profile:=_build_profile(); var modifier:=RetargetModifier3D.new(); modifier.name="NativeRetargetModifier"; modifier.set_use_global_pose(false); modifier.set_position_enabled(false); modifier.set_rotation_enabled(true); modifier.set_scale_enabled(false); source.add_child(modifier); modifier.add_child(target); modifier.set_profile(profile); await _settle()
    var source_probe_idx:=source.find_bone(_canonical(PROBE_ROLE)); var target_probe_idx:=target.find_bone(_canonical(PROBE_ROLE))
    if source_probe_idx<0 or target_probe_idx<0: _failures.append("probe_role_missing"); _finish({}); return
    source.reset_bone_poses(); source.force_update_all_bone_transforms(); await _settle(); target.force_update_all_bone_transforms()
    var source_rest_rotation:=source.get_bone_rest(source_probe_idx).basis.get_rotation_quaternion(); var source_baseline_rotation:=source.get_bone_pose_rotation(source_probe_idx)
    var source_rest_baseline_error_deg:=rad_to_deg(source_rest_rotation.angle_to(source_baseline_rotation)); if source_rest_baseline_error_deg>MAX_SOURCE_REST_BASELINE_ERROR_DEGREES: _failures.append("source_reset_not_at_rest error_deg=%.6f"%source_rest_baseline_error_deg)
    var target_baseline:=target.get_bone_pose_rotation(target_probe_idx); var probe_delta:=Quaternion(Vector3.FORWARD,deg_to_rad(PROBE_DEGREES)); var source_probe_pose:=source_rest_rotation*probe_delta
    source.set_bone_pose_rotation(source_probe_idx,source_probe_pose); source.force_update_all_bone_transforms(); await _settle(); target.force_update_all_bone_transforms()
    var source_after:=source.get_bone_pose_rotation(source_probe_idx); var source_delta_deg:=rad_to_deg(source_baseline_rotation.angle_to(source_after)); var target_after:=target.get_bone_pose_rotation(target_probe_idx); var target_transfer_deg:=rad_to_deg(target_baseline.angle_to(target_after)); var transfer_abs_error_deg:=absf(target_transfer_deg-source_delta_deg); var transfer_gain:=target_transfer_deg/source_delta_deg if source_delta_deg>0.001 else INF
    if not is_finite(source_delta_deg) or not is_finite(target_transfer_deg) or not is_finite(transfer_gain): _failures.append("non_finite_probe_rotation")
    if source_delta_deg<PROBE_DEGREES-0.5: _failures.append("source_probe_not_applied_deg=%.4f"%source_delta_deg)
    if target_transfer_deg<MIN_TRANSFER_DEGREES: _failures.append("native_modifier_did_not_transfer_rotation_deg=%.4f"%target_transfer_deg)
    if transfer_abs_error_deg>MAX_TRANSFER_ABS_ERROR_DEGREES: _failures.append("native_modifier_rotation_amplification source=%.4f target=%.4f error=%.4f"%[source_delta_deg,target_transfer_deg,transfer_abs_error_deg])
    if transfer_gain<MIN_TRANSFER_GAIN or transfer_gain>MAX_TRANSFER_GAIN: _failures.append("native_modifier_transfer_gain_out_of_range gain=%.4f expected=%.2f..%.2f"%[transfer_gain,MIN_TRANSFER_GAIN,MAX_TRANSFER_GAIN])
    source.reset_bone_poses(); source.force_update_all_bone_transforms(); await _settle(); target.force_update_all_bone_transforms(); var target_reset_deg:=rad_to_deg(target_baseline.angle_to(target.get_bone_pose_rotation(target_probe_idx))); if target_reset_deg>MAX_RESET_DEGREES: _failures.append("native_modifier_stale_after_reset_deg=%.4f"%target_reset_deg)
    var result:={"format":"grand-bruxelles-gate8-variant01-native-modifier-probe-v4","engine_version":Engine.get_version_info().get("string","unknown"),"candidate_variant":1,"reviewed_roles":ROLE_PAIRS.size(),"source_clone_bones":source_bone_count,"target_clone_bones":target_bone_count,"skinless_probe_skeletons":source.get_child_count()==1 and target.get_child_count()==0,"source_renamed_roles":source_renamed,"target_renamed_roles":target_renamed,"profile_bone_count":profile.bone_size,"use_global_pose":modifier.is_using_global_pose(),"position_enabled":modifier.is_position_enabled(),"rotation_enabled":modifier.is_rotation_enabled(),"scale_enabled":modifier.is_scale_enabled(),"probe_role":PROBE_ROLE,"rest_relative_probe_injection":true,"source_rest_baseline_error_deg":source_rest_baseline_error_deg,"source_probe_delta_deg":source_delta_deg,"target_transfer_delta_deg":target_transfer_deg,"transfer_abs_error_deg":transfer_abs_error_deg,"transfer_gain":transfer_gain,"transfer_gain_bounds":[MIN_TRANSFER_GAIN,MAX_TRANSFER_GAIN],"target_reset_delta_deg":target_reset_deg,"rest_pose_unchanged":not _failures.any(func(v:String)->bool:return v.contains("rest_changed")),"retarget_modifier_exercised":target_transfer_deg>=MIN_TRANSFER_DEGREES,"retarget_applied_to_runtime_population":false,"run_alias_selected":"","production_authorized":false,"activation_ready":false,"adoption_ready":false,"selection_state":"READY_NATIVE_AB_MEASUREMENT" if _failures.is_empty() else "BLOCKED_NATIVE_TRANSFER_FIDELITY","failures":_failures}
    _write_result(result); print("GATE8_NATIVE_MODIFIER_PROBE roles=%d source_bones=%d target_bones=%d source_deg=%.3f target_deg=%.3f gain=%.3f reset_deg=%.3f state=%s"%[ROLE_PAIRS.size(),source_bone_count,target_bone_count,source_delta_deg,target_transfer_deg,transfer_gain,target_reset_deg,result["selection_state"]]); _finish(result)
func _clone_skeleton_data(real:Skeleton3D)->Skeleton3D:
    var clone:=Skeleton3D.new(); clone.motion_scale=real.motion_scale
    for idx in range(real.get_bone_count()): clone.add_bone(real.get_bone_name(idx)); clone.set_bone_rest(idx,real.get_bone_rest(idx)); clone.set_bone_pose_position(idx,real.get_bone_pose_position(idx)); clone.set_bone_pose_rotation(idx,real.get_bone_pose_rotation(idx)); clone.set_bone_pose_scale(idx,real.get_bone_pose_scale(idx))
    for idx in range(real.get_bone_count()): clone.set_bone_parent(idx,real.get_bone_parent(idx))
    return clone
func _settle()->void:
    for _i in range(SETTLE_FRAMES): await process_frame
func _build_profile()->SkeletonProfile:
    var profile:=SkeletonProfile.new(); profile.bone_size=ROLE_PAIRS.size(); var i:=0
    for role:String in ROLE_PAIRS: profile.set_bone_name(i,_canonical(role)); var parent_role:=String(ROLE_PARENT[role]); if not parent_role.is_empty(): profile.set_bone_parent(i,_canonical(parent_role)); profile.set_required(i,true); i+=1
    profile.root_bone=_canonical("hips"); profile.scale_base_bone=_canonical("hips"); return profile
func _canonicalize(skeleton:Skeleton3D,side:int)->int:
    var renamed:=0
    for role:String in ROLE_PAIRS:
        var pair:Array=ROLE_PAIRS[role]; var idx:=skeleton.find_bone(String(pair[side])); if idx<0: _failures.append("bone_missing side=%d role=%s"%[side,role]); continue
        skeleton.set_bone_name(idx,_canonical(role)); if skeleton.get_bone_name(idx)==_canonical(role): renamed+=1
    return renamed
func _snapshot_rests(skeleton:Skeleton3D,side:int)->Dictionary:
    var rows:={}
    for role:String in ROLE_PAIRS: var pair:Array=ROLE_PAIRS[role]; var idx:=skeleton.find_bone(String(pair[side])); if idx>=0: rows[role]=skeleton.get_bone_rest(idx)
    return rows
func _verify_rests(skeleton:Skeleton3D,rows:Dictionary,label:String)->void:
    for role_value:Variant in rows.keys(): var role:=String(role_value); var idx:=skeleton.find_bone(_canonical(role)); if idx<0 or not skeleton.get_bone_rest(idx).is_equal_approx(rows[role]): _failures.append("rest_changed label=%s role=%s"%[label,role])
func _canonical(role:String)->String: return "gb_humanoid_%s"%role
func _instantiate(path:String)->Node3D:
    var packed:=load(path) as PackedScene; if packed==null: _failures.append("scene_load_failed=%s"%path); return null
    return packed.instantiate() as Node3D
func _find_skeleton(node:Node)->Skeleton3D:
    if node is Skeleton3D: return node as Skeleton3D
    for child:Node in node.get_children(): var found:=_find_skeleton(child); if found!=null:return found
    return null
func _write_result(result:Dictionary)->void:
    var file:=FileAccess.open("res://gate8_variant01_native_modifier_probe_result.json",FileAccess.WRITE); if file==null: _failures.append("result_file_open_failed"); return
    file.store_string(JSON.stringify(result,"  ")); file.close()
func _finish(_result:Dictionary)->void:
    if _failures.is_empty(): print("GATE8_NATIVE_MODIFIER_PROBE_OK transfer_fidelity=true production_authorized=false"); quit(0); return
    for failure:String in _failures: push_error("GATE8_NATIVE_MODIFIER_PROBE_FAIL %s"%failure)
    quit(1)