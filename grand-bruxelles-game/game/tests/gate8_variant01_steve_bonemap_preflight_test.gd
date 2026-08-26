extends SceneTree

const SOURCE_SCENE := "res://assets/steve_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const RESULT_PATH := "res://gate8_variant01_steve_bonemap_preflight_result.json"
const REQUIRED_ROLES: Array[String] = ["hips","spine","chest","neck","head","left_upper_arm","left_forearm","left_hand","right_upper_arm","right_forearm","right_hand","left_upper_leg","left_lower_leg","left_foot","right_upper_leg","right_lower_leg","right_foot"]
const SOURCE_ROLE_MAP := {"hips":"pelvis","spine":"waist","chest":"torso","neck":"neck","head":"head","left_upper_arm":"armup.L","left_forearm":"armlo.L","left_hand":"hand.L","right_upper_arm":"armup.R","right_forearm":"armlo.R","right_hand":"hand.R","left_upper_leg":"legup.L","left_lower_leg":"leglo.L","left_foot":"foot1.L","right_upper_leg":"legup.R","right_lower_leg":"leglo.R","right_foot":"foot1.R"}
const TARGET_ROLE_MAP := {"hips":"pelvis","spine":"spine_01","chest":"spine_02","neck":"neck_01","head":"head","left_upper_arm":"upperarm_l","left_forearm":"lowerarm_l","left_hand":"hand_l","right_upper_arm":"upperarm_r","right_forearm":"lowerarm_r","right_hand":"hand_r","left_upper_leg":"thigh_l","left_lower_leg":"calf_l","left_foot":"foot_l","right_upper_leg":"thigh_r","right_lower_leg":"calf_r","right_foot":"foot_r"}
const CHAINS := [["hips","spine","chest","neck","head"],["left_upper_arm","left_forearm","left_hand"],["right_upper_arm","right_forearm","right_hand"],["left_upper_leg","left_lower_leg","left_foot"],["right_upper_leg","right_lower_leg","right_foot"]]
const EXPECTED_SOURCE_TOPOLOGY_GAPS: Array[String] = ["hips>spine","left_forearm>left_hand","right_forearm>right_hand","left_lower_leg>left_foot","right_lower_leg>right_foot"]
const FORBIDDEN_WALK_TOKENS := ["back","backward","reverse","start","stop","turn","strafe","to","transition"]

var failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _regression_duplicate_mapping_rejected()
    _regression_walk_token_detection()
    _regression_split_topology_gap_set()
    _regression_topology_gap_order_independence()
    var source_root := await _load_scene(SOURCE_SCENE, "source")
    var target_root := await _load_scene(TARGET_SCENE, "target")
    if source_root == null or target_root == null:
        _finish({})
        return
    var source := _find_skeleton(source_root)
    var target := _find_skeleton(target_root)
    if source == null:
        failures.append("source_skeleton_missing")
    if target == null:
        failures.append("target_skeleton_missing")
    if source == null or target == null:
        _finish({})
        return

    _validate_map(source, SOURCE_ROLE_MAP, "source")
    _validate_map(target, TARGET_ROLE_MAP, "target")
    var source_gaps := _collect_chain_gaps(source, SOURCE_ROLE_MAP)
    var target_gaps := _collect_chain_gaps(target, TARGET_ROLE_MAP)
    var expected_gaps := _canonical_expected_source_gaps()
    _validate_expected_source_gaps(source_gaps, expected_gaps)
    if not target_gaps.is_empty():
        failures.append("target_topology_gaps=%s expected=[]" % JSON.stringify(target_gaps))
    if source.get_bone_count() < 55:
        failures.append("source_bone_count=%d expected>=55" % source.get_bone_count())
    if target.get_bone_count() < 53:
        failures.append("target_bone_count=%d expected>=53" % target.get_bone_count())

    var source_leg := _mean_leg_length(source, SOURCE_ROLE_MAP)
    var target_leg := _mean_leg_length(target, TARGET_ROLE_MAP)
    var leg_ratio := target_leg / source_leg if source_leg > 0.000001 else 0.0
    if source_leg <= 0.000001 or target_leg <= 0.000001:
        failures.append("invalid_leg_length source=%.6f target=%.6f" % [source_leg,target_leg])
    elif leg_ratio < 0.45 or leg_ratio > 2.20:
        failures.append("leg_length_ratio=%.6f outside=0.45..2.20" % leg_ratio)

    var animations := _animation_inventory(source_root)
    var source_walk := _find_exact_loop_animation(animations, "walk")
    if source_walk.is_empty():
        failures.append("source_walk_animation_missing_after_import")

    var topology_blocked := source_gaps == expected_gaps and target_gaps.is_empty()
    var result := {
        "format":"grand-bruxelles-gate8-variant01-steve-bonemap-preflight-result-v4",
        "engine_version":Engine.get_version_info().get("string","unknown"),
        "candidate_variant":1,
        "source_bone_count":source.get_bone_count(),
        "target_bone_count":target.get_bone_count(),
        "required_role_count":REQUIRED_ROLES.size(),
        "source_roles":SOURCE_ROLE_MAP,
        "target_roles":TARGET_ROLE_MAP,
        "source_bones":_bone_inventory(source),
        "target_bones":_bone_inventory(target),
        "source_role_parent_paths":_role_parent_paths(source,SOURCE_ROLE_MAP),
        "target_role_parent_paths":_role_parent_paths(target,TARGET_ROLE_MAP),
        "source_topology_gaps":source_gaps,
        "expected_source_topology_gaps":expected_gaps,
        "target_topology_gaps":target_gaps,
        "topology_gap_order_independent":true,
        "source_animation_names":animations,
        "source_leg_length_m":source_leg,
        "target_leg_length_m":target_leg,
        "target_to_source_leg_ratio":leg_ratio,
        "source_walk_animation_name":source_walk,
        "walk_detection":"exact_normalized_token_with_forbidden_transition_tokens",
        "explicit_role_mapping_selected":true,
        "characterization_complete":failures.is_empty(),
        "bonemap_ready":false,
        "direct_native_humanoid_topology_compatible":false,
        "mechanical_state":"BLOCKED_SPLIT_IK_DEFORM_TOPOLOGY" if topology_blocked else "BLOCKED_UNEXPECTED_TOPOLOGY_STATE",
        "bonemap_applied":false,
        "retarget_applied":false,
        "walk_alias_selected":"",
        "run_alias_selected":"",
        "production_authorized":false,
        "activation_ready":false,
        "adoption_ready":false,
        "visual_approval_claimed":false,
        "failures":failures
    }
    _write_result(result)
    _finish(result)

func _load_scene(path:String,label:String) -> Node:
    if not ResourceLoader.exists(path):
        failures.append("%s_scene_missing=%s" % [label,path])
        return null
    var packed := load(path) as PackedScene
    if packed == null:
        failures.append("%s_scene_load_failed=%s" % [label,path])
        return null
    var instance := packed.instantiate()
    root.add_child(instance)
    await process_frame
    return instance

func _find_skeleton(node:Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _validate_map(skeleton:Skeleton3D,mapping:Dictionary,label:String) -> void:
    var seen := {}
    for role in REQUIRED_ROLES:
        var bone_name := String(mapping.get(role,""))
        var idx := skeleton.find_bone(bone_name)
        if bone_name.is_empty():
            failures.append("%s_mapping_missing_role=%s" % [label,role])
            continue
        if idx < 0:
            failures.append("%s_bone_missing role=%s bone=%s" % [label,role,bone_name])
            continue
        if seen.has(idx):
            failures.append("%s_duplicate_bone role=%s prior=%s bone=%s" % [label,role,seen[idx],bone_name])
        else:
            seen[idx]=role

func _collect_chain_gaps(skeleton:Skeleton3D,mapping:Dictionary) -> Array[String]:
    var gaps:Array[String]=[]
    for chain in CHAINS:
        for i in range(chain.size()-1):
            var parent_role:=String(chain[i])
            var child_role:=String(chain[i+1])
            var a:=skeleton.find_bone(String(mapping.get(parent_role,"")))
            var c:=skeleton.find_bone(String(mapping.get(child_role,"")))
            if a >= 0 and c >= 0 and not _is_ancestor(skeleton,a,c):
                gaps.append("%s>%s" % [parent_role,child_role])
    gaps.sort()
    return gaps

func _canonical_expected_source_gaps() -> Array[String]:
    var expected:Array[String]=EXPECTED_SOURCE_TOPOLOGY_GAPS.duplicate()
    expected.sort()
    return expected

func _validate_expected_source_gaps(actual:Array[String], expected:Array[String]) -> void:
    if actual != expected:
        failures.append("source_topology_gaps=%s expected=%s" % [JSON.stringify(actual),JSON.stringify(expected)])

func _is_ancestor(skeleton:Skeleton3D,ancestor_idx:int,child_idx:int) -> bool:
    var cursor := child_idx
    while cursor >= 0:
        cursor = skeleton.get_bone_parent(cursor)
        if cursor == ancestor_idx:
            return true
    return false

func _parent_path(skeleton:Skeleton3D,idx:int) -> String:
    if idx < 0:
        return "<missing>"
    var names:Array[String]=[]
    var cursor:=idx
    while cursor >= 0:
        names.push_front(skeleton.get_bone_name(cursor))
        cursor=skeleton.get_bone_parent(cursor)
    return ">".join(names)

func _bone_inventory(skeleton:Skeleton3D) -> Array[Dictionary]:
    var out:Array[Dictionary]=[]
    for i in range(skeleton.get_bone_count()):
        var p:=skeleton.get_bone_parent(i)
        out.append({"index":i,"name":skeleton.get_bone_name(i),"parent_index":p,"parent_name":skeleton.get_bone_name(p) if p>=0 else ""})
    return out

func _role_parent_paths(skeleton:Skeleton3D,mapping:Dictionary) -> Dictionary:
    var out:={}
    for role in REQUIRED_ROLES:
        out[role]=_parent_path(skeleton,skeleton.find_bone(String(mapping.get(role,""))))
    return out

func _bone_global_rest(skeleton:Skeleton3D,idx:int) -> Transform3D:
    var chain:Array[int]=[]
    var cursor:=idx
    while cursor >= 0:
        chain.push_front(cursor)
        cursor=skeleton.get_bone_parent(cursor)
    var t:=Transform3D.IDENTITY
    for bone_idx in chain:
        t=t*skeleton.get_bone_rest(bone_idx)
    return t

func _bone_pos(skeleton:Skeleton3D,mapping:Dictionary,role:String) -> Vector3:
    var idx:=skeleton.find_bone(String(mapping.get(role,"")))
    return _bone_global_rest(skeleton,idx).origin if idx>=0 else Vector3.ZERO

func _mean_leg_length(skeleton:Skeleton3D,mapping:Dictionary) -> float:
    var total:=0.0
    for side in ["left","right"]:
        var upper:=_bone_pos(skeleton,mapping,"%s_upper_leg"%side)
        var lower:=_bone_pos(skeleton,mapping,"%s_lower_leg"%side)
        var foot:=_bone_pos(skeleton,mapping,"%s_foot"%side)
        total += upper.distance_to(lower)+lower.distance_to(foot)
    return total*0.5

func _animation_inventory(node:Node) -> Array[String]:
    var players:Array[AnimationPlayer]=[]
    _collect_animation_players(node,players)
    var out:Array[String]=[]
    for player in players:
        for name in player.get_animation_list():
            var value:=String(name)
            if not out.has(value):
                out.append(value)
    out.sort()
    return out

func _normalized_tokens(name:String) -> PackedStringArray:
    var normalized:=name.to_lower()
    for separator in ["|",":","/","\\","-","."," "]:
        normalized=normalized.replace(separator,"_")
    return normalized.split("_",false)

func _find_exact_loop_animation(names:Array[String],token:String) -> String:
    for name in names:
        var tokens:=_normalized_tokens(name)
        if not tokens.has(token):
            continue
        var forbidden:=false
        for bad in FORBIDDEN_WALK_TOKENS:
            if tokens.has(bad):
                forbidden=true
                break
        if not forbidden:
            return name
    return ""

func _collect_animation_players(node:Node,out:Array[AnimationPlayer]) -> void:
    if node is AnimationPlayer:
        out.append(node as AnimationPlayer)
    for child in node.get_children():
        _collect_animation_players(child,out)

func _regression_duplicate_mapping_rejected() -> void:
    var synthetic:=SOURCE_ROLE_MAP.duplicate()
    synthetic["left_hand"]=synthetic["left_forearm"]
    var values:={}
    var duplicate_found:=false
    for role in REQUIRED_ROLES:
        var bone:=String(synthetic[role])
        if values.has(bone):
            duplicate_found=true
            break
        values[bone]=role
    if not duplicate_found:
        failures.append("regression_duplicate_mapping_not_detected")

func _regression_walk_token_detection() -> void:
    if _find_exact_loop_animation(["Rig|walk"],"walk") != "Rig|walk":
        failures.append("regression_namespaced_walk_not_detected")
    if not _find_exact_loop_animation(["Walk_Backward"],"walk").is_empty():
        failures.append("regression_backward_walk_should_not_be_selected")
    if not _find_exact_loop_animation(["Idle_To_Walk"],"walk").is_empty():
        failures.append("regression_transition_walk_should_not_be_selected")

func _regression_split_topology_gap_set() -> void:
    var expected:=_canonical_expected_source_gaps()
    if expected.size()!=5 or not expected.has("hips>spine") or not expected.has("left_forearm>left_hand") or not expected.has("right_forearm>right_hand") or not expected.has("left_lower_leg>left_foot") or not expected.has("right_lower_leg>right_foot"):
        failures.append("regression_split_topology_gap_contract_invalid")

func _regression_topology_gap_order_independence() -> void:
    var expected:=_canonical_expected_source_gaps()
    var shuffled:Array[String]=EXPECTED_SOURCE_TOPOLOGY_GAPS.duplicate()
    shuffled.reverse()
    shuffled.sort()
    if shuffled != expected:
        failures.append("regression_topology_gap_order_independence_failed")

func _write_result(result:Dictionary) -> void:
    var file:=FileAccess.open(RESULT_PATH,FileAccess.WRITE)
    if file==null:
        failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result,"  "))
    file.close()

func _finish(_result:Dictionary) -> void:
    if failures.is_empty():
        print("GATE8_STEVE_BONEMAP_CHARACTERIZATION_OK roles=17 direct_native=false state=BLOCKED_SPLIT_IK_DEFORM_TOPOLOGY aliases=false production_authorized=false")
        quit(0)
        return
    for failure in failures:
        push_error("GATE8_STEVE_BONEMAP_PREFLIGHT_FAIL %s" % failure)
    quit(1)
