extends "res://base_probe.gd"

const AB_RESULT_PATH := "res://gate8_variant03_steve_shoulder_ab_result.json"
const SHOULDER_AB_CANDIDATES := [
    {"id":"BASELINE","upperarm":1.0,"clavicle":0.0,"spine03":0.0},
    {"id":"UPPERARM_75","upperarm":0.75,"clavicle":0.0,"spine03":0.0},
    {"id":"UPPERARM_75_CLAVICLE_25","upperarm":0.75,"clavicle":0.25,"spine03":0.0},
    {"id":"UPPERARM_75_CLAVICLE_15_SPINE03_10","upperarm":0.75,"clavicle":0.15,"spine03":0.10},
    {"id":"UPPERARM_50_CLAVICLE_50","upperarm":0.50,"clavicle":0.50,"spine03":0.0},
]
const SAMPLE_ABSOLUTE := 10
const SAMPLE_COMPRESSION := 2
const SAMPLE_HAND_CONTROL := 0
const ABS_MESH := "Human_female_sportsuit01_004_gate8_export"
const ABS_TRIANGLE := 1438
const ABS_A := 746
const ABS_B := 401
const COMP_MESH := "Human_006_gate8_export"
const COMP_TRIANGLE := 5828
const COMP_A := 3701
const COMP_B := 22
const HAND_MESH := "Human_006_gate8_export"
const HAND_TRIANGLE := 10753
const HAND_A := 260
const HAND_B := 7988
const HAND_REGRESSION_EPS := 0.00001
const LOCAL_ROTATION_EPS_DEG := 0.001

func _init()->void:
    call_deferred("_run")

func _run()->void:
    source_root=load(SOURCE_SCENE).instantiate() as Node3D
    target_root=load(TARGET_SCENE).instantiate() as Node3D
    if source_root==null or target_root==null:
        _finish_ab("BLOCKED_SCENE_LOAD",[])
        return
    root.add_child(source_root)
    root.add_child(target_root)
    await process_frame
    source_skeleton=_find_skeleton(source_root)
    target_skeleton=_find_skeleton(target_root)
    source_player=_find_exact_walk_player(source_root)
    _collect_skinned_meshes(target_root,target_meshes)
    if source_skeleton==null: failures.append("source_skeleton_missing")
    if target_skeleton==null: failures.append("target_skeleton_missing")
    if source_player==null: failures.append("source_exact_walk_player_missing")
    if source_skeleton==null or target_skeleton==null or source_player==null:
        _finish_ab("BLOCKED_IMPORT",[])
        return
    if source_skeleton.get_bone_count()!=17: failures.append("source_bones=%d expected=17"%source_skeleton.get_bone_count())
    if target_skeleton.get_bone_count()!=53: failures.append("target_bones=%d expected=53"%target_skeleton.get_bone_count())
    _validate_maps()
    var integrity:=_validate_target_integrity()
    if not failures.is_empty():
        _finish_ab("BLOCKED_INTEGRITY",[],integrity)
        return
    source_probe=_build_collapsed_target_probe("NativeSource")
    target_probe=_build_collapsed_target_probe("NativeTarget")
    root.add_child(source_probe)
    var modifier:=RetargetModifier3D.new()
    modifier.name="SteveVariant03ShoulderABRetarget"
    source_probe.add_child(modifier)
    modifier.add_child(target_probe)
    modifier.set_use_global_pose(false)
    modifier.set_position_enabled(false)
    modifier.set_rotation_enabled(true)
    modifier.set_scale_enabled(false)
    modifier.set_profile(_build_profile())
    await process_frame
    await process_frame
    var anim:=source_player.get_animation("walk")
    if anim==null or anim.length<=0.0:
        failures.append("walk_invalid")
        _finish_ab("BLOCKED_WALK",[],integrity)
        return

    var results:Array=[]
    var baseline_hand:Dictionary={}
    var baseline_lowerarm:=Quaternion.IDENTITY
    var baseline_hand_local:=Quaternion.IDENTITY
    for candidate in SHOULDER_AB_CANDIDATES:
        var measured:Dictionary=await _measure_candidate(candidate,anim)
        if String(candidate["id"])=="BASELINE":
            baseline_hand=measured["hand_control"].duplicate(true)
            baseline_lowerarm=measured["hand_local_rotations"]["lowerarm"]
            baseline_hand_local=measured["hand_local_rotations"]["hand"]
        else:
            measured["hand_not_worse"]=(float(measured["hand_control"]["absolute_change_m"])<=float(baseline_hand["absolute_change_m"])+HAND_REGRESSION_EPS and float(measured["hand_control"]["ratio"])<=float(baseline_hand["ratio"])+HAND_REGRESSION_EPS)
            measured["protected_lowerarm_local_error_deg"]=_stable_angle_deg(baseline_lowerarm,measured["hand_local_rotations"]["lowerarm"])
            measured["protected_hand_local_error_deg"]=_stable_angle_deg(baseline_hand_local,measured["hand_local_rotations"]["hand"])
            measured["protected_local_pose_unchanged"]=(float(measured["protected_lowerarm_local_error_deg"])<=LOCAL_ROTATION_EPS_DEG and float(measured["protected_hand_local_error_deg"])<=LOCAL_ROTATION_EPS_DEG)
        measured.erase("hand_local_rotations")
        results.append(measured)

    var baseline:Dictionary=results[0]
    if not (float(baseline["shoulder_absolute"]["absolute_change_m"])>0.44 and float(baseline["shoulder_absolute"]["absolute_change_m"])<0.46):
        failures.append("baseline_absolute_not_reproduced=%.9f"%float(baseline["shoulder_absolute"]["absolute_change_m"]))
    if not (float(baseline["hand_control"]["ratio"])>49.0 and float(baseline["hand_control"]["ratio"])<52.0):
        failures.append("baseline_hand_stretch_not_reproduced=%.9f"%float(baseline["hand_control"]["ratio"]))
    if not (float(baseline["shoulder_compression"]["ratio"])>0.03 and float(baseline["shoulder_compression"]["ratio"])<0.05):
        failures.append("baseline_compression_not_reproduced=%.9f"%float(baseline["shoulder_compression"]["ratio"]))

    var shoulder_candidates:Array[String]=[]
    for i in range(1,results.size()):
        var item:Dictionary=results[i]
        if bool(item["shoulder_within_gates"]) and bool(item["hand_not_worse"]) and bool(item["protected_local_pose_unchanged"]) and float(item["grounding_span_m"])<=MAX_GROUNDING_SPAN_M:
            shoulder_candidates.append(String(item["id"]))
    var state:="SHOULDER_AB_CANDIDATE_IDENTIFIED_HAND_STILL_BLOCKED" if not shoulder_candidates.is_empty() else "SHOULDER_AB_NO_CANDIDATE_WITHIN_GATES"
    _finish_ab(state,results,integrity,shoulder_candidates)

func _measure_candidate(candidate:Dictionary,anim:Animation)->Dictionary:
    var left_min:=INF
    var left_max:=-INF
    var right_min:=INF
    var right_max:=-INF
    var max_transfer:=0.0
    var absolute:Dictionary={}
    var compression:Dictionary={}
    var hand_control:Dictionary={}
    var hand_local_rotations:Dictionary={}
    source_player.play("walk")
    for sample in range(SAMPLE_COUNT):
        var t:=anim.length*float(sample)/float(SAMPLE_COUNT-1)
        source_player.seek(t,true)
        source_player.advance(0.0)
        source_skeleton.force_update_all_bone_transforms()
        _reset_probe(source_probe)
        _reset_probe(target_probe)
        target_skeleton.reset_bone_poses()
        for role in ROLES:
            var si:=source_skeleton.find_bone(String(SOURCE[role]))
            var pi:=source_probe.find_bone(_canonical(role))
            var sr:=source_skeleton.get_bone_rest(si).basis.orthonormalized().get_rotation_quaternion().normalized()
            var sp:=source_skeleton.get_bone_pose_rotation(si).normalized()
            var pr:=source_probe.get_bone_rest(pi).basis.orthonormalized().get_rotation_quaternion().normalized()
            var delta:Quaternion=(sr.inverse()*sp).normalized()
            source_probe.set_bone_pose_rotation(pi,(pr*delta).normalized())
        await process_frame
        await process_frame

        var upperarm_delta:=Quaternion.IDENTITY
        for role in ROLES:
            var pi:=target_probe.find_bone(_canonical(role))
            var source_pose:=source_probe.get_bone_pose_rotation(source_probe.find_bone(_canonical(role))).normalized()
            var probe_pose:=target_probe.get_bone_pose_rotation(pi).normalized()
            max_transfer=maxf(max_transfer,_stable_angle_deg(source_pose,probe_pose))
            var probe_rest:=target_probe.get_bone_rest(pi).basis.orthonormalized().get_rotation_quaternion().normalized()
            var probe_delta:Quaternion=(probe_rest.inverse()*probe_pose).normalized()
            if role=="right_upper_arm": upperarm_delta=probe_delta
            var factor:=float(candidate["upperarm"]) if role=="right_upper_arm" else 1.0
            var ti:=target_skeleton.find_bone(String(TARGET[role]))
            var target_rest:=target_skeleton.get_bone_rest(ti).basis.orthonormalized().get_rotation_quaternion().normalized()
            target_skeleton.set_bone_pose_rotation(ti,(target_rest*_scaled_delta(probe_delta,factor)).normalized())

        _apply_intermediate_rotation("clavicle_r",upperarm_delta,float(candidate["clavicle"]))
        _apply_intermediate_rotation("spine_03",upperarm_delta,float(candidate["spine03"]))
        target_skeleton.force_update_all_bone_transforms()
        var ly:=target_skeleton.get_bone_global_pose(target_skeleton.find_bone("foot_l")).origin.y
        var ry:=target_skeleton.get_bone_global_pose(target_skeleton.find_bone("foot_r")).origin.y
        left_min=minf(left_min,ly); left_max=maxf(left_max,ly)
        right_min=minf(right_min,ry); right_max=maxf(right_max,ry)
        if sample==SAMPLE_HAND_CONTROL:
            hand_control=_edge_metric(HAND_MESH,HAND_TRIANGLE,HAND_A,HAND_B)
            hand_local_rotations={"lowerarm":target_skeleton.get_bone_pose_rotation(target_skeleton.find_bone("lowerarm_r")),"hand":target_skeleton.get_bone_pose_rotation(target_skeleton.find_bone("hand_r"))}
        elif sample==SAMPLE_COMPRESSION:
            compression=_edge_metric(COMP_MESH,COMP_TRIANGLE,COMP_A,COMP_B)
        elif sample==SAMPLE_ABSOLUTE:
            absolute=_edge_metric(ABS_MESH,ABS_TRIANGLE,ABS_A,ABS_B)
    var grounding:=maxf(left_max-left_min,right_max-right_min)
    var shoulder_ok:=_edge_within_gates(absolute) and _edge_within_gates(compression)
    return {"id":candidate["id"],"factors":{"upperarm":candidate["upperarm"],"clavicle":candidate["clavicle"],"spine03":candidate["spine03"]},"max_native_transfer_error_deg":max_transfer,"grounding_span_m":grounding,"shoulder_absolute":absolute,"shoulder_compression":compression,"hand_control":hand_control,"hand_local_rotations":hand_local_rotations,"shoulder_within_gates":shoulder_ok,"hand_not_worse":true if String(candidate["id"])=="BASELINE" else false,"protected_local_pose_unchanged":true if String(candidate["id"])=="BASELINE" else false}

func _apply_intermediate_rotation(bone_name:String,delta:Quaternion,factor:float)->void:
    var idx:=target_skeleton.find_bone(bone_name)
    if idx<0:
        failures.append("intermediate_bone_missing=%s"%bone_name)
        return
    var rest_q:=target_skeleton.get_bone_rest(idx).basis.orthonormalized().get_rotation_quaternion().normalized()
    target_skeleton.set_bone_pose_rotation(idx,(rest_q*_scaled_delta(delta,factor)).normalized())

func _scaled_delta(delta:Quaternion,factor:float)->Quaternion:
    return Quaternion.IDENTITY.slerp(delta.normalized(),factor).normalized()

func _stable_angle_deg(a:Quaternion,b:Quaternion)->float:
    var d:Quaternion=(a.normalized().inverse()*b.normalized()).normalized()
    return rad_to_deg(2.0*atan2(Vector3(d.x,d.y,d.z).length(),absf(d.w)))

func _edge_metric(mesh_name:String,triangle:int,a:int,b:int)->Dictionary:
    var found:MeshInstance3D=null
    for mesh in target_meshes:
        if String(mesh.name)==mesh_name:
            found=mesh
            break
    if found==null:
        failures.append("edge_mesh_missing=%s"%mesh_name)
        return {}
    var arrays:=found.mesh.surface_get_arrays(0)
    var vertices=arrays[Mesh.ARRAY_VERTEX]
    var bones=arrays[Mesh.ARRAY_BONES]
    var weights=arrays[Mesh.ARRAY_WEIGHTS]
    var indices=arrays[Mesh.ARRAY_INDEX]
    if a<0 or b<0 or a>=vertices.size() or b>=vertices.size():
        failures.append("edge_vertex_oob=%s:%d:%d"%[mesh_name,a,b])
        return {}
    if indices!=null and indices.size()>=(triangle+1)*3:
        var tri=[int(indices[triangle*3]),int(indices[triangle*3+1]),int(indices[triangle*3+2])]
        if not (a in tri and b in tri): failures.append("edge_triangle_identity_mismatch=%s:%d"%[mesh_name,triangle])
    var ipv:=int(bones.size()/vertices.size())
    var ra:=_skin_vertex(vertices[a],a,bones,weights,ipv,found.skin,true)
    var rb:=_skin_vertex(vertices[b],b,bones,weights,ipv,found.skin,true)
    var pa:=_skin_vertex(vertices[a],a,bones,weights,ipv,found.skin,false)
    var pb:=_skin_vertex(vertices[b],b,bones,weights,ipv,found.skin,false)
    var rest_len:=ra.distance_to(rb)
    var posed_len:=pa.distance_to(pb)
    if rest_len<MIN_EDGE_M:
        failures.append("edge_rest_too_short=%s:%d"%[mesh_name,triangle])
        return {}
    return {"mesh":mesh_name,"triangle":triangle,"vertices":[a,b],"rest_length_m":rest_len,"posed_length_m":posed_len,"absolute_change_m":absf(posed_len-rest_len),"ratio":posed_len/rest_len}

func _edge_within_gates(edge:Dictionary)->bool:
    if edge.is_empty(): return false
    return float(edge["absolute_change_m"])<=MAX_SKIN_EDGE_CHANGE_M and float(edge["ratio"])<=MAX_SKIN_STRETCH_RATIO and float(edge["ratio"])>=MIN_SKIN_COMPRESSION_RATIO

func _finish_ab(state:String,results:Array,integrity:Dictionary={},candidates:Array[String]=[])->void:
    var result={"format":"grand-bruxelles-gate8-variant03-steve-shoulder-ab-v1","engine_version":Engine.get_version_info().get("string","unknown"),"candidate_variant":3,"mechanical_state":state,"experiment":"AB_SHOULDER","results":results,"shoulder_candidates":candidates,"target_integrity":integrity,"unchanged_gates":{"max_transfer_error_deg":MAX_TRANSFER_ERROR_DEG,"max_grounding_span_m":MAX_GROUNDING_SPAN_M,"max_skin_edge_change_m":MAX_SKIN_EDGE_CHANGE_M,"max_skin_stretch_ratio":MAX_SKIN_STRETCH_RATIO,"min_skin_compression_ratio":MIN_SKIN_COMPRESSION_RATIO},"protected_family":"lowerarm_r/hand_r sample0","walk_alias_selected":"","run_alias_selected":"","production_authorized":false,"activation_ready":false,"adoption_ready":false,"visual_approval_claimed":false,"retarget_change_authorized":false,"skin_weight_change_authorized":false,"failures":failures}
    var f:=FileAccess.open(AB_RESULT_PATH,FileAccess.WRITE)
    if f!=null:
        f.store_string(JSON.stringify(result,"  "))
        f.close()
    print("GATE8_V03_STEVE_SHOULDER_AB state=%s candidates=%d failures=%d production_authorized=false"%[state,candidates.size(),failures.size()])
    quit(0 if failures.is_empty() else 1)
