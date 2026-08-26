extends SceneTree

const SOURCE_SCENE := "res://assets/steve_reviewed_proxy.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const RESULT_PATH := "res://gate8_variant01_steve_reviewed_proxy_result.json"
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
    var source_gaps:=_collect_chain_gaps(source,SOURCE_ROLE_MAP)
    var target_gaps:=_collect_chain_gaps(target,TARGET_ROLE_MAP)
    if not source_gaps.is_empty(): failures.append("source_topology_gaps=%s expected=[]"%JSON.stringify(source_gaps))
    if not target_gaps.is_empty(): failures.append("target_topology_gaps=%s expected=[]"%JSON.stringify(target_gaps))
    if source.get_bone_count()!=17: failures.append("source_proxy_bone_count=%d expected=17"%source.get_bone_count())
    if target.get_bone_count()<53: failures.append("target_bone_count=%d expected>=53"%target.get_bone_count())
    var source_walk:=_find_exact_loop_animation(_animation_inventory(source_root),"walk")
    if source_walk.is_empty(): failures.append("source_walk_animation_missing_after_proxy_import")
    var source_leg:=_mean_leg_length(source,SOURCE_ROLE_MAP)
    var target_leg:=_mean_leg_length(target,TARGET_ROLE_MAP)
    var ratio:=target_leg/source_leg if source_leg>0.000001 else 0.0
    if source_leg<=0.000001 or target_leg<=0.000001: failures.append("invalid_leg_length")
    elif ratio<0.45 or ratio>2.20: failures.append("leg_length_ratio=%.6f outside=0.45..2.20"%ratio)
    var result:={
        "format":"grand-bruxelles-gate8-variant01-steve-reviewed-retarget-proxy-result-v11",
        "engine_version":Engine.get_version_info().get("string","unknown"),
        "source_proxy_bone_count":source.get_bone_count(),
        "target_bone_count":target.get_bone_count(),
        "source_topology_gaps":source_gaps,
        "target_topology_gaps":target_gaps,
        "source_walk_animation_name":source_walk,
        "target_to_source_leg_ratio":ratio,
        "source_proxy_verified":source_gaps.is_empty() and source.get_bone_count()==17,
        "mechanical_state":"READY_FOR_NATIVE_RETARGET_PROBE" if failures.is_empty() else "BLOCKED_REVIEWED_PROXY_PREFLIGHT",
        "bonemap_applied":false,"retarget_applied":false,"walk_alias_selected":"","run_alias_selected":"",
        "production_authorized":false,"activation_ready":false,"adoption_ready":false,"visual_approval_claimed":false,
        "failures":failures
    }
    _write_result(result); _finish(result)

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
    if not _find_exact_loop_animation(["Idle_To_Walk"],"walk").is_empty(): failures.append("regression_walk_transition")

func _write_result(result:Dictionary)->void:
    var f:=FileAccess.open(RESULT_PATH,FileAccess.WRITE)
    if f==null: failures.append("result_file_open_failed"); return
    f.store_string(JSON.stringify(result,"  ")); f.close()

func _finish(_result:Dictionary)->void:
    if failures.is_empty():
        print("GATE8_STEVE_REVIEWED_PROXY_PREFLIGHT_OK state=READY_FOR_NATIVE_RETARGET_PROBE source_bones=17 gaps=0 aliases=false production_authorized=false")
        quit(0); return
    for failure in failures: push_error("GATE8_STEVE_REVIEWED_PROXY_PREFLIGHT_FAIL %s"%failure)
    quit(1)
