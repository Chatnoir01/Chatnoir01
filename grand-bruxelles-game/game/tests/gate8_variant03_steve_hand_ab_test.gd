extends "res://shoulder_ab.gd"

const HAND_AB_RESULT_PATH := "res://gate8_variant03_steve_hand_ab_result.json"
const HAND_AB_CANDIDATES := [
    {"id":"BASELINE","lowerarm":1.0,"hand":1.0},
    {"id":"HAND_75","lowerarm":1.0,"hand":0.75},
    {"id":"HAND_50","lowerarm":1.0,"hand":0.50},
    {"id":"HAND_25","lowerarm":1.0,"hand":0.25},
    {"id":"HAND_0","lowerarm":1.0,"hand":0.0},
    {"id":"DISTAL_75","lowerarm":0.75,"hand":0.75},
    {"id":"DISTAL_50","lowerarm":0.50,"hand":0.50},
]
const SHOULDER_REGRESSION_EPS := 0.00001

func _init()->void:
    call_deferred("_run_hand")

func _run_hand()->void:
    source_root=load(SOURCE_SCENE).instantiate() as Node3D
    target_root=load(TARGET_SCENE).instantiate() as Node3D
    if source_root==null or target_root==null:
        _finish_hand("BLOCKED_SCENE_LOAD",[])
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
        _finish_hand("BLOCKED_IMPORT",[])
        return
    if source_skeleton.get_bone_count()!=17: failures.append("source_bones=%d expected=17"%source_skeleton.get_bone_count())
    if target_skeleton.get_bone_count()!=53: failures.append("target_bones=%d expected=53"%target_skeleton.get_bone_count())
    _validate_maps()
    var integrity:=_validate_target_integrity()
    if not failures.is_empty():
        _finish_hand("BLOCKED_INTEGRITY",[],integrity)
        return

    source_probe=_build_collapsed_target_probe("NativeSource")
    target_probe=_build_collapsed_target_probe("NativeTarget")
    root.add_child(source_probe)
    var modifier:=RetargetModifier3D.new()
    modifier.name="SteveVariant03HandABRetarget"
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
        _finish_hand("BLOCKED_WALK",[],integrity)
        return

    var results:Array=[]
    var baseline_shoulder_abs:Dictionary={}
    var baseline_shoulder_comp:Dictionary={}
    var baseline_protected:Dictionary={}
    for candidate in HAND_AB_CANDIDATES:
        var measured:Dictionary=await _measure_hand_candidate(candidate,anim)
        if String(candidate["id"])=="BASELINE":
            baseline_shoulder_abs=measured["shoulder_absolute"].duplicate(true)
            baseline_shoulder_comp=measured["shoulder_compression"].duplicate(true)
            baseline_protected=measured["shoulder_local_rotations"].duplicate(true)
        else:
            measured["shoulder_not_worse"]=_shoulder_not_worse(measured,baseline_shoulder_abs,baseline_shoulder_comp)
            var max_protected:=0.0
            for bone_name in baseline_protected.keys():
                max_protected=maxf(max_protected,_stable_angle_deg(baseline_protected[bone_name],measured["shoulder_local_rotations"][bone_name]))
            measured["protected_shoulder_local_error_deg"]=max_protected
            measured["protected_shoulder_local_pose_unchanged"]=max_protected<=LOCAL_ROTATION_EPS_DEG
        measured.erase("shoulder_local_rotations")
        results.append(measured)

    var baseline:Dictionary=results[0]
    if not (49.0<float(baseline["hand_edge"]["ratio"]) and float(baseline["hand_edge"]["ratio"])<52.0):
        failures.append("baseline_hand_stretch_not_reproduced=%.9f"%float(baseline["hand_edge"]["ratio"]))
    if not (0.44<float(baseline["shoulder_absolute"]["absolute_change_m"]) and float(baseline["shoulder_absolute"]["absolute_change_m"])<0.46):
        failures.append("baseline_shoulder_absolute_not_reproduced=%.9f"%float(baseline["shoulder_absolute"]["absolute_change_m"]))
    if not (0.03<float(baseline["shoulder_compression"]["ratio"]) and float(baseline["shoulder_compression"]["ratio"])<0.05):
        failures.append("baseline_shoulder_compression_not_reproduced=%.9f"%float(baseline["shoulder_compression"]["ratio"]))

    var hand_candidates:Array[String]=[]
    for i in range(1,results.size()):
        var item:Dictionary=results[i]
        if bool(item["hand_within_gates"]) and bool(item["shoulder_not_worse"]) and bool(item["protected_shoulder_local_pose_unchanged"]) and float(item["grounding_span_m"])<=MAX_GROUNDING_SPAN_M:
            hand_candidates.append(String(item["id"]))
    var state:="HAND_AB_CANDIDATE_IDENTIFIED_SHOULDER_STILL_BLOCKED" if not hand_candidates.is_empty() else "HAND_AB_NO_CANDIDATE_WITHIN_GATES"
    _finish_hand(state,results,integrity,hand_candidates)

func _measure_hand_candidate(candidate:Dictionary,anim:Animation)->Dictionary:
    var left_min:=INF
    var left_max:=-INF
    var right_min:=INF
    var right_max:=-INF
    var max_transfer:=0.0
    var hand_edge:Dictionary={}
    var shoulder_absolute:Dictionary={}
    var shoulder_compression:Dictionary={}
    var shoulder_local_rotations:Dictionary={}
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

        for role in ROLES:
            var pi:=target_probe.find_bone(_canonical(role))
            var source_pose:=source_probe.get_bone_pose_rotation(source_probe.find_bone(_canonical(role))).normalized()
            var probe_pose:=target_probe.get_bone_pose_rotation(pi).normalized()
            max_transfer=maxf(max_transfer,_stable_angle_deg(source_pose,probe_pose))
            var probe_rest:=target_probe.get_bone_rest(pi).basis.orthonormalized().get_rotation_quaternion().normalized()
            var probe_delta:Quaternion=(probe_rest.inverse()*probe_pose).normalized()
            var factor:=1.0
            if role=="right_forearm": factor=float(candidate["lowerarm"])
            elif role=="right_hand": factor=float(candidate["hand"])
            var ti:=target_skeleton.find_bone(String(TARGET[role]))
            var target_rest:=target_skeleton.get_bone_rest(ti).basis.orthonormalized().get_rotation_quaternion().normalized()
            target_skeleton.set_bone_pose_rotation(ti,(target_rest*_scaled_delta(probe_delta,factor)).normalized())

        target_skeleton.force_update_all_bone_transforms()
        var ly:=target_skeleton.get_bone_global_pose(target_skeleton.find_bone("foot_l")).origin.y
        var ry:=target_skeleton.get_bone_global_pose(target_skeleton.find_bone("foot_r")).origin.y
        left_min=minf(left_min,ly); left_max=maxf(left_max,ly)
        right_min=minf(right_min,ry); right_max=maxf(right_max,ry)
        if sample==SAMPLE_HAND_CONTROL:
            hand_edge=_edge_metric(HAND_MESH,HAND_TRIANGLE,HAND_A,HAND_B)
            shoulder_local_rotations={
                "spine_03":target_skeleton.get_bone_pose_rotation(target_skeleton.find_bone("spine_03")),
                "clavicle_r":target_skeleton.get_bone_pose_rotation(target_skeleton.find_bone("clavicle_r")),
                "upperarm_r":target_skeleton.get_bone_pose_rotation(target_skeleton.find_bone("upperarm_r")),
            }
        elif sample==SAMPLE_COMPRESSION:
            shoulder_compression=_edge_metric(COMP_MESH,COMP_TRIANGLE,COMP_A,COMP_B)
        elif sample==SAMPLE_ABSOLUTE:
            shoulder_absolute=_edge_metric(ABS_MESH,ABS_TRIANGLE,ABS_A,ABS_B)
    var grounding:=maxf(left_max-left_min,right_max-right_min)
    return {
        "id":candidate["id"],
        "factors":{"lowerarm":candidate["lowerarm"],"hand":candidate["hand"]},
        "max_native_transfer_error_deg":max_transfer,
        "grounding_span_m":grounding,
        "hand_edge":hand_edge,
        "hand_within_gates":_edge_within_gates(hand_edge),
        "shoulder_absolute":shoulder_absolute,
        "shoulder_compression":shoulder_compression,
        "shoulder_local_rotations":shoulder_local_rotations,
        "shoulder_not_worse":true if String(candidate["id"])=="BASELINE" else false,
        "protected_shoulder_local_pose_unchanged":true if String(candidate["id"])=="BASELINE" else false,
    }

func _shoulder_not_worse(item:Dictionary,baseline_abs:Dictionary,baseline_comp:Dictionary)->bool:
    var a:Dictionary=item["shoulder_absolute"]
    var c:Dictionary=item["shoulder_compression"]
    return (
        float(a["absolute_change_m"])<=float(baseline_abs["absolute_change_m"])+SHOULDER_REGRESSION_EPS
        and float(a["ratio"])<=float(baseline_abs["ratio"])+SHOULDER_REGRESSION_EPS
        and float(c["absolute_change_m"])<=float(baseline_comp["absolute_change_m"])+SHOULDER_REGRESSION_EPS
        and float(c["ratio"])>=float(baseline_comp["ratio"])-SHOULDER_REGRESSION_EPS
    )

func _finish_hand(state:String,results:Array,integrity:Dictionary={},candidates:Array[String]=[])->void:
    var result={
        "format":"grand-bruxelles-gate8-variant03-steve-hand-ab-v1",
        "engine_version":Engine.get_version_info().get("string","unknown"),
        "candidate_variant":3,
        "mechanical_state":state,
        "experiment":"AB_HAND",
        "results":results,
        "hand_candidates":candidates,
        "target_integrity":integrity,
        "unchanged_gates":{"max_transfer_error_deg":MAX_TRANSFER_ERROR_DEG,"max_grounding_span_m":MAX_GROUNDING_SPAN_M,"max_skin_edge_change_m":MAX_SKIN_EDGE_CHANGE_M,"max_skin_stretch_ratio":MAX_SKIN_STRETCH_RATIO,"min_skin_compression_ratio":MIN_SKIN_COMPRESSION_RATIO},
        "protected_family":"spine_03/clavicle_r/upperarm_r samples2,10",
        "shoulder_ab_artifact_id":9666870216,
        "shoulder_ab_artifact_digest":"sha256:2c7d95d9cb658528e9e61763f2c819297bbd7b0ec14fb3dc87201187ced34425",
        "shoulder_ab_state":"SHOULDER_AB_NO_CANDIDATE_WITHIN_GATES",
        "walk_alias_selected":"",
        "run_alias_selected":"",
        "production_authorized":false,
        "activation_ready":false,
        "adoption_ready":false,
        "visual_approval_claimed":false,
        "retarget_change_authorized":false,
        "skin_weight_change_authorized":false,
        "failures":failures,
    }
    var f:=FileAccess.open(HAND_AB_RESULT_PATH,FileAccess.WRITE)
    if f!=null:
        f.store_string(JSON.stringify(result,"  "))
        f.close()
    print("GATE8_V03_STEVE_HAND_AB state=%s candidates=%d failures=%d production_authorized=false"%[state,candidates.size(),failures.size()])
    quit(0 if failures.is_empty() else 1)
