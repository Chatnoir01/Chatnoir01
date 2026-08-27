extends SceneTree

const SOURCE_SCENE := "res://assets/steve_reviewed_proxy.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const RESULT_PATH := "res://gate8_variant01_steve_foot_slide_probe_result.json"
const SAMPLE_RATE_HZ := 120.0
const CONTACT_HEIGHT_EPS_M := 0.035
const MIN_SOURCE_POSE_EXCITATION_DEG := 5.0
const MIN_TARGET_FOOT_PATH_M := 0.01
const ROLES := ["hips","spine","chest","neck","head","left_upper_arm","left_forearm","left_hand","right_upper_arm","right_forearm","right_hand","left_upper_leg","left_lower_leg","left_foot","right_upper_leg","right_lower_leg","right_foot"]
const SOURCE := {"hips":"pelvis","spine":"waist","chest":"torso","neck":"neck","head":"head","left_upper_arm":"armup.L","left_forearm":"armlo.L","left_hand":"hand.L","right_upper_arm":"armup.R","right_forearm":"armlo.R","right_hand":"hand.R","left_upper_leg":"legup.L","left_lower_leg":"leglo.L","left_foot":"foot1.L","right_upper_leg":"legup.R","right_lower_leg":"leglo.R","right_foot":"foot1.R"}
const TARGET := {"hips":"pelvis","spine":"spine_01","chest":"spine_02","neck":"neck_01","head":"head","left_upper_arm":"upperarm_l","left_forearm":"lowerarm_l","left_hand":"hand_l","right_upper_arm":"upperarm_r","right_forearm":"lowerarm_r","right_hand":"hand_r","left_upper_leg":"thigh_l","left_lower_leg":"calf_l","left_foot":"foot_l","right_upper_leg":"thigh_r","right_lower_leg":"calf_r","right_foot":"foot_r"}
const PARENT := {"hips":"","spine":"hips","chest":"spine","neck":"chest","head":"neck","left_upper_arm":"chest","left_forearm":"left_upper_arm","left_hand":"left_forearm","right_upper_arm":"chest","right_forearm":"right_upper_arm","right_hand":"right_forearm","left_upper_leg":"hips","left_lower_leg":"left_upper_leg","left_foot":"left_lower_leg","right_upper_leg":"hips","right_lower_leg":"right_upper_leg","right_foot":"right_lower_leg"}

var failures:Array[String]=[]
var source_root:Node3D
var target_root:Node3D
var source_skeleton:Skeleton3D
var target_skeleton:Skeleton3D
var source_player:AnimationPlayer
var source_probe:Skeleton3D
var target_probe:Skeleton3D

func _init()->void:
    call_deferred("_run")

func _run()->void:
    _run_math_regressions()
    source_root=load(SOURCE_SCENE).instantiate() as Node3D
    target_root=load(TARGET_SCENE).instantiate() as Node3D
    if source_root==null or target_root==null:
        _finish("BLOCKED_SCENE_LOAD",{}); return
    root.add_child(source_root); root.add_child(target_root); await process_frame
    source_skeleton=_find_skeleton(source_root); target_skeleton=_find_skeleton(target_root); source_player=_find_walk_player(source_root)
    if source_skeleton==null: failures.append("source_skeleton_missing")
    if target_skeleton==null: failures.append("target_skeleton_missing")
    if source_player==null: failures.append("source_walk_player_missing")
    if not failures.is_empty(): _finish("BLOCKED_IMPORT",{}); return
    if source_skeleton.get_bone_count()!=17: failures.append("source_bones=%d expected=17"%source_skeleton.get_bone_count())
    if target_skeleton.get_bone_count()<53: failures.append("target_bones=%d expected>=53"%target_skeleton.get_bone_count())
    _validate_maps()
    if not failures.is_empty(): _finish("BLOCKED_INTEGRITY",{}); return
    source_probe=_build_probe("NativeSource"); target_probe=_build_probe("NativeTarget"); root.add_child(source_probe)
    var modifier:=RetargetModifier3D.new(); modifier.name="SteveWalkNativeRetarget"; source_probe.add_child(modifier); modifier.add_child(target_probe)
    modifier.set_use_global_pose(false); modifier.set_position_enabled(false); modifier.set_rotation_enabled(true); modifier.set_scale_enabled(false); modifier.set_profile(_build_profile())
    await process_frame; await process_frame
    var walk_name:=_walk_name(source_player); var anim:=source_player.get_animation(walk_name)
    if anim==null or anim.length<=0.0: failures.append("walk_invalid"); _finish("BLOCKED_WALK",{}); return
    var sample_count:=maxi(3,int(ceil(anim.length*SAMPLE_RATE_HZ))+1); var dt:=anim.length/float(sample_count-1)
    var left:Array[Vector3]=[]; var right:Array[Vector3]=[]; var source_excitation:=0.0
    source_player.play(walk_name)
    for sample in range(sample_count):
        var t:=minf(anim.length,dt*float(sample)); source_player.seek(t,true); source_player.advance(0.0); source_skeleton.force_update_all_bone_transforms()
        _reset_probe(source_probe); _reset_probe(target_probe)
        for role in ROLES:
            var si:=source_skeleton.find_bone(String(SOURCE[role])); var pi:=source_probe.find_bone(_canonical(role)); var ti:=target_skeleton.find_bone(String(TARGET[role]))
            var sr:=source_skeleton.get_bone_rest(si).basis.orthonormalized().get_rotation_quaternion().normalized(); var sp:=source_skeleton.get_bone_pose_rotation(si).normalized(); var tr:=target_skeleton.get_bone_rest(ti).basis.orthonormalized().get_rotation_quaternion().normalized(); var delta:Quaternion=(sr.inverse()*sp).normalized()
            source_excitation=maxf(source_excitation,rad_to_deg(Quaternion.IDENTITY.angle_to(delta)))
            source_probe.set_bone_pose_rotation(pi,(tr*delta).normalized())
        await process_frame; await process_frame
        for role in ROLES:
            var ti:=target_skeleton.find_bone(String(TARGET[role])); var b:=target_probe.get_bone_pose_rotation(target_probe.find_bone(_canonical(role))).normalized(); target_skeleton.set_bone_pose_rotation(ti,b)
        target_skeleton.force_update_all_bone_transforms()
        left.append(target_skeleton.get_bone_global_pose(target_skeleton.find_bone("foot_l")).origin)
        right.append(target_skeleton.get_bone_global_pose(target_skeleton.find_bone("foot_r")).origin)
    var metrics:=_measure_slide(left,right,dt)
    metrics["walk_animation"]=walk_name; metrics["walk_length_s"]=anim.length; metrics["sample_rate_hz"]=SAMPLE_RATE_HZ; metrics["sample_count"]=sample_count; metrics["source_pose_excitation_max_deg"]=source_excitation
    if source_excitation<MIN_SOURCE_POSE_EXCITATION_DEG: failures.append("source_pose_excitation_too_low_deg=%.6f"%source_excitation)
    if maxf(float(metrics.left_foot_path_m),float(metrics.right_foot_path_m))<MIN_TARGET_FOOT_PATH_M: failures.append("target_foot_path_too_low_m=%.6f"%maxf(float(metrics.left_foot_path_m),float(metrics.right_foot_path_m)))
    if int(metrics.contact_interval_count)<=0: failures.append("no_contact_intervals")
    _finish("FOOT_SLIDE_CHARACTERIZED" if failures.is_empty() else "BLOCKED_FOOT_SLIDE_MEASUREMENT",metrics)

func _measure_slide(left:Array[Vector3],right:Array[Vector3],dt:float)->Dictionary:
    var lmin:=INF; var rmin:=INF; var lpath:=0.0; var rpath:=0.0
    for i in range(left.size()): lmin=minf(lmin,left[i].y); rmin=minf(rmin,right[i].y)
    for i in range(1,left.size()): lpath+=Vector2(left[i].x-left[i-1].x,left[i].z-left[i-1].z).length(); rpath+=Vector2(right[i].x-right[i-1].x,right[i].z-right[i-1].z).length()
    var lthr:=lmin+CONTACT_HEIGHT_EPS_M; var rthr:=rmin+CONTACT_HEIGHT_EPS_M
    var raw_sum:=0.0; var raw_peak:=0.0; var residual_sum:=0.0; var residual_peak:=0.0; var root_sum:=0.0; var root_peak:=0.0; var disagreement_peak:=0.0; var contact_vel_count:=0; var interval_count:=0; var double_support_count:=0
    for i in range(1,left.size()):
        var lv:=Vector2(left[i].x-left[i-1].x,left[i].z-left[i-1].z)/dt; var rv:=Vector2(right[i].x-right[i-1].x,right[i].z-right[i-1].z)/dt
        var lc:=left[i].y<=lthr and left[i-1].y<=lthr; var rc:=right[i].y<=rthr and right[i-1].y<=rthr
        if not lc and not rc: continue
        interval_count+=1
        var root:=Vector2.ZERO
        if lc and rc: root=-(lv+rv)*0.5; double_support_count+=1; disagreement_peak=maxf(disagreement_peak,(lv-rv).length())
        elif lc: root=-lv
        else: root=-rv
        var root_speed:=root.length(); root_sum+=root_speed; root_peak=maxf(root_peak,root_speed)
        if lc:
            var raw:=lv.length(); var residual:=(lv+root).length(); raw_sum+=raw; raw_peak=maxf(raw_peak,raw); residual_sum+=residual; residual_peak=maxf(residual_peak,residual); contact_vel_count+=1
        if rc:
            var raw:=rv.length(); var residual:=(rv+root).length(); raw_sum+=raw; raw_peak=maxf(raw_peak,raw); residual_sum+=residual; residual_peak=maxf(residual_peak,residual); contact_vel_count+=1
    return {"contact_height_epsilon_m":CONTACT_HEIGHT_EPS_M,"left_contact_threshold_y_m":lthr,"right_contact_threshold_y_m":rthr,"left_foot_path_m":lpath,"right_foot_path_m":rpath,"contact_interval_count":interval_count,"contact_velocity_sample_count":contact_vel_count,"double_support_interval_count":double_support_count,"raw_contact_slide_mean_mps":raw_sum/float(maxi(1,contact_vel_count)),"raw_contact_slide_peak_mps":raw_peak,"optimal_root_compensation_mean_mps":root_sum/float(maxi(1,interval_count)),"optimal_root_compensation_peak_mps":root_peak,"irreducible_contact_slide_mean_mps":residual_sum/float(maxi(1,contact_vel_count)),"irreducible_contact_slide_peak_mps":residual_peak,"double_support_velocity_disagreement_peak_mps":disagreement_peak}

func _run_math_regressions()->void:
    var single_left:Array[Vector3]=[Vector3(0,0,0),Vector3(1,0,0)]; var single_right:Array[Vector3]=[Vector3(0,1,0),Vector3(0,1,0)]; var m:=_measure_slide(single_left,single_right,1.0)
    if absf(float(m.raw_contact_slide_mean_mps)-1.0)>0.000001 or float(m.irreducible_contact_slide_mean_mps)>0.000001: failures.append("regression_single_support_root_compensation")
    var opposed_left:Array[Vector3]=[Vector3(0,0,0),Vector3(1,0,0)]; var opposed_right:Array[Vector3]=[Vector3(0,0,0),Vector3(-1,0,0)]; var d:=_measure_slide(opposed_left,opposed_right,1.0)
    if absf(float(d.double_support_velocity_disagreement_peak_mps)-2.0)>0.000001 or absf(float(d.irreducible_contact_slide_mean_mps)-1.0)>0.000001: failures.append("regression_double_support_disagreement")

func _validate_maps()->void:
    var seen_source:={}; var seen_target:={}
    for role in ROLES:
        var si:=source_skeleton.find_bone(String(SOURCE[role])); var ti:=target_skeleton.find_bone(String(TARGET[role]))
        if si<0: failures.append("source_role_missing=%s"%role)
        elif seen_source.has(si): failures.append("source_duplicate_role=%s"%role)
        else: seen_source[si]=role
        if ti<0: failures.append("target_role_missing=%s"%role)
        elif seen_target.has(ti): failures.append("target_duplicate_role=%s"%role)
        else: seen_target[ti]=role

func _build_probe(node_name:String)->Skeleton3D:
    var p:=Skeleton3D.new(); p.name=node_name; var by_role:={}
    for role in ROLES:
        var idx:=p.get_bone_count(); p.add_bone(_canonical(role)); by_role[role]=idx; var parent:=String(PARENT[role]); if not parent.is_empty(): p.set_bone_parent(idx,int(by_role[parent])); var rest:=target_skeleton.get_bone_rest(target_skeleton.find_bone(String(TARGET[role]))); p.set_bone_rest(idx,rest); p.set_bone_pose_position(idx,rest.origin); p.set_bone_pose_rotation(idx,rest.basis.orthonormalized().get_rotation_quaternion().normalized()); p.set_bone_pose_scale(idx,rest.basis.get_scale())
    return p

func _build_profile()->SkeletonProfile:
    var p:=SkeletonProfile.new(); p.set_bone_size(ROLES.size())
    for i in range(ROLES.size()): var role:=String(ROLES[i]); p.set_bone_name(i,_canonical(role)); var parent:=String(PARENT[role]); p.set_bone_parent(i,StringName() if parent.is_empty() else _canonical(parent)); p.set_required(i,true)
    p.set_root_bone(_canonical("hips")); p.set_scale_base_bone(_canonical("hips")); return p

func _reset_probe(p:Skeleton3D)->void:
    for i in range(p.get_bone_count()): var r:=p.get_bone_rest(i); p.set_bone_pose_position(i,r.origin); p.set_bone_pose_rotation(i,r.basis.orthonormalized().get_rotation_quaternion().normalized()); p.set_bone_pose_scale(i,r.basis.get_scale())

func _find_skeleton(n:Node)->Skeleton3D:
    if n is Skeleton3D: return n as Skeleton3D
    for c in n.get_children(): var f:=_find_skeleton(c); if f!=null: return f
    return null

func _find_walk_player(n:Node)->AnimationPlayer:
    if n is AnimationPlayer:
        for a in (n as AnimationPlayer).get_animation_list(): if _is_walk_name(String(a)): return n as AnimationPlayer
    for c in n.get_children(): var f:=_find_walk_player(c); if f!=null: return f
    return null

func _is_walk_name(s:String)->bool:
    var t:=s.to_lower().replace("|","_").replace(":","_").split("_",false); return t.has("walk") and not t.has("backward") and not t.has("start") and not t.has("stop") and not t.has("transition") and not t.has("to")

func _walk_name(p:AnimationPlayer)->String:
    for a in p.get_animation_list(): if _is_walk_name(String(a)): return String(a)
    return ""

func _canonical(role:String)->StringName: return StringName("gb_humanoid_%s"%role)

func _finish(state:String,metrics:Dictionary)->void:
    var result={"format":"grand-bruxelles-gate8-variant01-steve-foot-slide-probe-v1","engine_version":Engine.get_version_info().get("string","unknown"),"candidate_variant":1,"source":"Steve reviewed 17-role proxy","mechanical_state":state,"metrics":metrics,"walk_alias_selected":"","run_alias_selected":"","production_authorized":false,"activation_ready":false,"adoption_ready":false,"visual_approval_claimed":false,"runtime_population_changed":false,"failures":failures}
    var f:=FileAccess.open(RESULT_PATH,FileAccess.WRITE); if f!=null: f.store_string(JSON.stringify(result,"  ")); f.close()
    print("GATE8_STEVE_FOOT_SLIDE_PROBE state=%s failures=%d"%[state,failures.size()]); quit(0 if failures.is_empty() else 1)
