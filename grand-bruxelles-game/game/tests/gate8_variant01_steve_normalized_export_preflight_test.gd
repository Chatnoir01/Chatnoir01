extends SceneTree

const SOURCE_SCENE := "res://assets/steve_normalized.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const REPORT_PATH := "res://normalization-report.json"
const RESULT_PATH := "res://gate8_variant01_steve_normalized_export_result.json"
const REQUIRED_ROLES: Array[String] = ["hips","spine","chest","neck","head","left_upper_arm","left_forearm","left_hand","right_upper_arm","right_forearm","right_hand","left_upper_leg","left_lower_leg","left_foot","right_upper_leg","right_lower_leg","right_foot"]
const SOURCE_ROLE_MAP := {"hips":"pelvis","spine":"waist","chest":"torso","neck":"neck","head":"head","left_upper_arm":"armup.L","left_forearm":"armlo.L","left_hand":"hand.L","right_upper_arm":"armup.R","right_forearm":"armlo.R","right_hand":"hand.R","left_upper_leg":"legup.L","left_lower_leg":"leglo.L","left_foot":"foot1.L","right_upper_leg":"legup.R","right_lower_leg":"leglo.R","right_foot":"foot1.R"}
const TARGET_ROLE_MAP := {"hips":"pelvis","spine":"spine_01","chest":"spine_02","neck":"neck_01","head":"head","left_upper_arm":"upperarm_l","left_forearm":"lowerarm_l","left_hand":"hand_l","right_upper_arm":"upperarm_r","right_forearm":"lowerarm_r","right_hand":"hand_r","left_upper_leg":"thigh_l","left_lower_leg":"calf_l","left_foot":"foot_l","right_upper_leg":"thigh_r","right_lower_leg":"calf_r","right_foot":"foot_r"}
const CHAINS := [["hips","spine","chest","neck","head"],["left_upper_arm","left_forearm","left_hand"],["right_upper_arm","right_forearm","right_hand"],["left_upper_leg","left_lower_leg","left_foot"],["right_upper_leg","right_lower_leg","right_foot"]]
const FORBIDDEN_WALK_TOKENS := ["back","backward","reverse","start","stop","turn","strafe","to","transition"]
var failures:Array[String]=[]

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _regression_walk_detection()
    var report:=_read_json(REPORT_PATH)
    if report.is_empty(): failures.append("normalization_report_missing_or_invalid")
    var source_root:=await _load_scene(SOURCE_SCENE,"source")
    var target_root:=await _load_scene(TARGET_SCENE,"target")
    if source_root==null or target_root==null:
        _finish({}); return
    var source:=_find_skeleton(source_root)
    var target:=_find_skeleton(target_root)
    if source==null: failures.append("source_skeleton_missing")
    if target==null: failures.append("target_skeleton_missing")
    if source==null or target==null:
        _finish({}); return

    _validate_map(source,SOURCE_ROLE_MAP,"source")
    _validate_map(target,TARGET_ROLE_MAP,"target")
    var protected_bones:Array = report.get("protected_bones", [])
    var omitted_controllers:Array = report.get("omitted_controller_bones", [])
    if protected_bones.size()<17: failures.append("protected_bone_manifest_too_small=%d"%protected_bones.size())
    for bone_value in protected_bones:
        var bone_name:=String(bone_value)
        if source.find_bone(bone_name)<0: failures.append("protected_source_bone_missing=%s"%bone_name)
    for controller_value in omitted_controllers:
        var controller_name:=String(controller_value)
        if source.find_bone(controller_name)>=0: failures.append("nondeform_controller_exported=%s"%controller_name)
    if omitted_controllers.size()!=5: failures.append("omitted_controller_count=%d expected=5"%omitted_controllers.size())
    if source.get_bone_count()<protected_bones.size(): failures.append("source_bone_count=%d protected_manifest=%d"%[source.get_bone_count(),protected_bones.size()])
    if target.get_bone_count()<53: failures.append("target_bone_count=%d expected>=53"%target.get_bone_count())

    var source_role_parent_count:=0
    for role in REQUIRED_ROLES:
        var idx:=source.find_bone(String(SOURCE_ROLE_MAP[role]))
        if idx>=0 and source.get_bone_parent(idx)>=0: source_role_parent_count+=1
    if source_role_parent_count!=0: failures.append("source_role_parent_count=%d expected=0_flattened"%source_role_parent_count)

    var target_gaps:=_collect_chain_gaps(target,TARGET_ROLE_MAP)
    if not target_gaps.is_empty(): failures.append("target_topology_gaps=%s expected=[]"%JSON.stringify(target_gaps))

    var source_walk:=_find_exact_loop_animation(_animation_inventory(source_root),"walk")
    if source_walk.is_empty(): failures.append("source_walk_animation_missing_after_flattened_import")
    var source_leg:=_mean_flat_leg_length(source,SOURCE_ROLE_MAP)
    var target_leg:=_mean_leg_length(target,TARGET_ROLE_MAP)
    var ratio:=target_leg/source_leg if source_leg>0.000001 else 0.0
    if source_leg<=0.000001 or target_leg<=0.000001: failures.append("invalid_leg_length")
    elif ratio<0.45 or ratio>2.20: failures.append("leg_length_ratio=%.6f outside=0.45..2.20"%ratio)

    var state:="READY_FOR_BONEMAP_RETARGET_PROBE_FLAT_SOURCE" if failures.is_empty() else "BLOCKED_FLATTENED_EXPORT_PREFLIGHT"
    var result:={
        "format":"grand-bruxelles-gate8-variant01-steve-normalized-export-result-v3",
        "engine_version":Engine.get_version_info().get("string","unknown"),
        "source_bone_count":source.get_bone_count(),"target_bone_count":target.get_bone_count(),
        "protected_bone_count":protected_bones.size(),"omitted_controller_count":omitted_controllers.size(),
        "source_role_parent_count":source_role_parent_count,"target_topology_gaps":target_gaps,
        "source_walk_animation_name":source_walk,"target_to_source_leg_ratio":ratio,
        "source_visual_roundtrip_verified":float(report.get("max_roundtrip_vertex_position_error_m",1.0))<=0.0001,
        "mechanical_state":state,
        "bonemap_applied":false,"retarget_applied":false,"walk_alias_selected":"","run_alias_selected":"",
        "production_authorized":false,"activation_ready":false,"adoption_ready":false,"visual_approval_claimed":false,
        "failures":failures
    }
    _write_result(result); _finish(result)

func _read_json(path:String)->Dictionary:
    if not FileAccess.file_exists(path): return {}
    var f:=FileAccess.open(path,FileAccess.READ)
    if f==null: return {}
    var parsed=JSON.parse_string(f.get_as_text())
    f.close()
    return parsed if parsed is Dictionary else {}

func _load_scene(path:String,label:String)->Node:
    if not ResourceLoader.exists(path): failures.append("%s_scene_missing=%s"%[label,path]); return null
    var packed:=load(path) as PackedScene
    if packed==null: failures.append("%s_scene_load_failed=%s"%[label,path]); return null
    var instance:=packed.instantiate(); root.add_child(instance); await process_frame; return instance

func _find_skeleton(node:Node)->Skeleton3D:
    if node is Skeleton3D: return node as Skeleton3D
    for child in node.get_children():
        var found:=_find_skeleton(child)
        if found!=null: return found
    return null

func _validate_map(skeleton:Skeleton3D,mapping:Dictionary,label:String)->void:
    var seen:={}
    for role in REQUIRED_ROLES:
        var name:=String(mapping.get(role,"")); var idx:=skeleton.find_bone(name)
        if idx<0: failures.append("%s_bone_missing role=%s bone=%s"%[label,role,name]); continue
        if seen.has(idx): failures.append("%s_duplicate_bone role=%s prior=%s bone=%s"%[label,role,seen[idx],name])
        else: seen[idx]=role

func _collect_chain_gaps(skeleton:Skeleton3D,mapping:Dictionary)->Array[String]:
    var gaps:Array[String]=[]
    for chain in CHAINS:
        for i in range(chain.size()-1):
            var a:=skeleton.find_bone(String(mapping[chain[i]])); var b:=skeleton.find_bone(String(mapping[chain[i+1]]))
            if a>=0 and b>=0 and not _is_ancestor(skeleton,a,b): gaps.append("%s>%s"%[chain[i],chain[i+1]])
    gaps.sort(); return gaps

func _is_ancestor(skeleton:Skeleton3D,a:int,b:int)->bool:
    var cursor:=b
    while cursor>=0:
        cursor=skeleton.get_bone_parent(cursor)
        if cursor==a: return true
    return false

func _bone_global_rest(skeleton:Skeleton3D,idx:int)->Transform3D:
    var chain:Array[int]=[]; var cursor:=idx
    while cursor>=0: chain.push_front(cursor); cursor=skeleton.get_bone_parent(cursor)
    var t:=Transform3D.IDENTITY
    for bone_idx in chain: t=t*skeleton.get_bone_rest(bone_idx)
    return t

func _mean_leg_length(skeleton:Skeleton3D,mapping:Dictionary)->float:
    var total:=0.0
    for side in ["left","right"]:
        var a:=_bone_global_rest(skeleton,skeleton.find_bone(String(mapping["%s_upper_leg"%side]))).origin
        var b:=_bone_global_rest(skeleton,skeleton.find_bone(String(mapping["%s_lower_leg"%side]))).origin
        var c:=_bone_global_rest(skeleton,skeleton.find_bone(String(mapping["%s_foot"%side]))).origin
        total+=a.distance_to(b)+b.distance_to(c)
    return total*0.5

func _mean_flat_leg_length(skeleton:Skeleton3D,mapping:Dictionary)->float:
    var total:=0.0
    for side in ["left","right"]:
        var a:=skeleton.get_bone_rest(skeleton.find_bone(String(mapping["%s_upper_leg"%side]))).origin
        var b:=skeleton.get_bone_rest(skeleton.find_bone(String(mapping["%s_lower_leg"%side]))).origin
        var c:=skeleton.get_bone_rest(skeleton.find_bone(String(mapping["%s_foot"%side]))).origin
        total+=a.distance_to(b)+b.distance_to(c)
    return total*0.5

func _animation_inventory(node:Node)->Array[String]:
    var players:Array[AnimationPlayer]=[]; _collect_players(node,players); var out:Array[String]=[]
    for p in players:
        for n in p.get_animation_list():
            var s:=String(n)
            if not out.has(s): out.append(s)
    out.sort(); return out

func _collect_players(node:Node,out:Array[AnimationPlayer])->void:
    if node is AnimationPlayer: out.append(node as AnimationPlayer)
    for c in node.get_children(): _collect_players(c,out)

func _tokens(name:String)->PackedStringArray:
    var s:=name.to_lower()
    for sep in ["|",":","/","\\","-","."," "]: s=s.replace(sep,"_")
    return s.split("_",false)

func _find_exact_loop_animation(names:Array[String],token:String)->String:
    for name in names:
        var t:=_tokens(name)
        if not t.has(token): continue
        var bad:=false
        for f in FORBIDDEN_WALK_TOKENS:
            if t.has(f): bad=true; break
        if not bad: return name
    return ""

func _regression_walk_detection()->void:
    if _find_exact_loop_animation(["Rig|walk"],"walk")!="Rig|walk": failures.append("regression_walk_namespaced")
    if not _find_exact_loop_animation(["Walk_Backward"],"walk").is_empty(): failures.append("regression_walk_backward")

func _write_result(result:Dictionary)->void:
    var f:=FileAccess.open(RESULT_PATH,FileAccess.WRITE)
    if f==null: failures.append("result_file_open_failed"); return
    f.store_string(JSON.stringify(result,"  ")); f.close()

func _finish(_result:Dictionary)->void:
    if failures.is_empty():
        print("GATE8_STEVE_NORMALIZED_PREFLIGHT_OK state=READY_FOR_BONEMAP_RETARGET_PROBE_FLAT_SOURCE flat_source=true protected=true controllers_absent=true target_gaps=0 production_authorized=false")
        quit(0); return
    for failure in failures: push_error("GATE8_STEVE_NORMALIZED_PREFLIGHT_FAIL %s"%failure)
    quit(1)
