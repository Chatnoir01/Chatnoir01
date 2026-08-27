extends SceneTree

const SOURCE_SCENE := "res://assets/steve.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const RESULT_PATH := "res://gate8_variant01_steve_canonical_native_probe_result.json"
const SAMPLE_COUNT := 16
const MAX_TRANSFER_ERROR_DEG := 3.0
const MAX_GROUNDING_SPAN_M := 0.18
const MAX_SKIN_EDGE_CHANGE_M := 0.25
const MAX_SKIN_STRETCH_RATIO := 3.0
const MIN_SKIN_COMPRESSION_RATIO := 0.25
const MIN_EDGE_M := 0.00001
const MAX_COLLAPSED_REST_POSITION_ERROR_M := 0.000001
const MAX_COLLAPSED_REST_ROTATION_ERROR_DEG := 0.001
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
var target_meshes:Array[MeshInstance3D]=[]

func _init()->void:
    call_deferred("_run")

func _run()->void:
    source_root=load(SOURCE_SCENE).instantiate() as Node3D
    target_root=load(TARGET_SCENE).instantiate() as Node3D
    if source_root==null or target_root==null:
        _finish("BLOCKED_SCENE_LOAD",{})
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
        _finish("BLOCKED_IMPORT",{})
        return
    if source_skeleton.get_bone_count()!=17: failures.append("source_bones=%d expected=17"%source_skeleton.get_bone_count())
    if target_skeleton.get_bone_count()<53: failures.append("target_bones=%d expected>=53"%target_skeleton.get_bone_count())
    var integrity:=_validate_target_integrity()
    _validate_maps()
    if not failures.is_empty():
        _finish("BLOCKED_INTEGRITY",integrity)
        return
    source_probe=_build_collapsed_target_probe("NativeSource")
    target_probe=_build_collapsed_target_probe("NativeTarget")
    var collapsed_rest:=_validate_collapsed_rest_roundtrip(target_probe)
    if not failures.is_empty():
        _finish("BLOCKED_COLLAPSED_REST",{"target_integrity":integrity,"collapsed_rest":collapsed_rest})
        return
    root.add_child(source_probe)
    var modifier:=RetargetModifier3D.new()
    modifier.name="SteveCanonicalWalkNativeRetarget"
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
        _finish("BLOCKED_WALK",integrity)
        return
    var max_transfer:=0.0
    var max_transfer_role:=""
    var left_min:=INF
    var left_max:=-INF
    var right_min:=INF
    var right_max:=-INF
    var deformation={"max_absolute_edge_change_m":0.0,"max_stretch_ratio":1.0,"min_compression_ratio":1.0,"edge_count":0}
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
            var a:=source_probe.get_bone_pose_rotation(source_probe.find_bone(_canonical(role))).normalized()
            var b:=target_probe.get_bone_pose_rotation(pi).normalized()
            var err:=rad_to_deg(a.angle_to(b))
            if err>max_transfer:
                max_transfer=err
                max_transfer_role=role
            var ti:=target_skeleton.find_bone(String(TARGET[role]))
            var probe_rest_rotation:=target_probe.get_bone_rest(pi).basis.orthonormalized().get_rotation_quaternion().normalized()
            var target_rest_rotation:=target_skeleton.get_bone_rest(ti).basis.orthonormalized().get_rotation_quaternion().normalized()
            var probe_delta:Quaternion=(probe_rest_rotation.inverse()*b).normalized()
            target_skeleton.set_bone_pose_rotation(ti,(target_rest_rotation*probe_delta).normalized())
        target_skeleton.force_update_all_bone_transforms()
        var ly:=target_skeleton.get_bone_global_pose(target_skeleton.find_bone("foot_l")).origin.y
        var ry:=target_skeleton.get_bone_global_pose(target_skeleton.find_bone("foot_r")).origin.y
        left_min=minf(left_min,ly)
        left_max=maxf(left_max,ly)
        right_min=minf(right_min,ry)
        right_max=maxf(right_max,ry)
        _measure_skin_edges(deformation)
    var grounding_span:=maxf(left_max-left_min,right_max-right_min)
    if max_transfer>MAX_TRANSFER_ERROR_DEG: failures.append("native_transfer_error_deg=%.6f role=%s"%[max_transfer,max_transfer_role])
    if grounding_span>MAX_GROUNDING_SPAN_M: failures.append("grounding_span_m=%.6f"%grounding_span)
    if float(deformation.max_absolute_edge_change_m)>MAX_SKIN_EDGE_CHANGE_M: failures.append("skin_edge_change_m=%.6f"%float(deformation.max_absolute_edge_change_m))
    if float(deformation.max_stretch_ratio)>MAX_SKIN_STRETCH_RATIO: failures.append("skin_stretch_ratio=%.6f"%float(deformation.max_stretch_ratio))
    if float(deformation.min_compression_ratio)<MIN_SKIN_COMPRESSION_RATIO: failures.append("skin_compression_ratio=%.6f"%float(deformation.min_compression_ratio))
    var metrics={"walk_animation":"walk","walk_length_s":anim.length,"samples":SAMPLE_COUNT,"max_transfer_error_deg":max_transfer,"max_transfer_error_role":max_transfer_role,"left_foot_y_span_m":left_max-left_min,"right_foot_y_span_m":right_max-right_min,"grounding_span_m":grounding_span,"collapsed_rest":collapsed_rest,"hierarchy_collapse_policy":"target_global_rest_rebased_to_reviewed_parent","mirror_policy":"collapsed_probe_delta_composed_with_actual_target_rest","skin_space":deformation,"target_integrity":integrity}
    _finish("READY_FOR_CANONICAL_FOOT_SLIDE_PROBE" if failures.is_empty() else "BLOCKED_CANONICAL_NATIVE_WALK_MECHANICS",metrics)

func _validate_maps()->void:
    var seen_source={}
    var seen_target={}
    for role in ROLES:
        var si:=source_skeleton.find_bone(String(SOURCE[role]))
        var ti:=target_skeleton.find_bone(String(TARGET[role]))
        if si<0: failures.append("source_role_missing=%s"%role)
        elif seen_source.has(si): failures.append("source_duplicate_role=%s"%role)
        else: seen_source[si]=role
        if ti<0: failures.append("target_role_missing=%s"%role)
        elif seen_target.has(ti): failures.append("target_duplicate_role=%s"%role)
        else: seen_target[ti]=role

func _validate_target_integrity()->Dictionary:
    var surfaces:=0
    var materials:=0
    for mesh in target_meshes:
        for s in range(mesh.mesh.get_surface_count()):
            surfaces+=1
            if mesh.get_active_material(s)!=null: materials+=1
    if target_meshes.size()!=8: failures.append("skinned_meshes=%d expected=8"%target_meshes.size())
    if surfaces!=8: failures.append("skinned_surfaces=%d expected=8"%surfaces)
    if materials!=8: failures.append("material_surfaces=%d expected=8"%materials)
    return {"skinned_meshes":target_meshes.size(),"skinned_surfaces":surfaces,"material_surfaces":materials,"target_bones":target_skeleton.get_bone_count()}

func _build_collapsed_target_probe(node_name:String)->Skeleton3D:
    var p:=Skeleton3D.new()
    p.name=node_name
    var by_role={}
    for role in ROLES:
        var idx:=p.get_bone_count()
        p.add_bone(_canonical(role))
        by_role[role]=idx
        var parent:=String(PARENT[role])
        if not parent.is_empty():
            p.set_bone_parent(idx,int(by_role[parent]))
        var target_index:=target_skeleton.find_bone(String(TARGET[role]))
        var target_global_rest:=target_skeleton.get_bone_global_rest(target_index)
        var collapsed_rest:=target_global_rest
        if not parent.is_empty():
            var parent_index:=int(by_role[parent])
            collapsed_rest=p.get_bone_global_rest(parent_index).affine_inverse()*target_global_rest
        p.set_bone_rest(idx,collapsed_rest)
        p.set_bone_pose(idx,collapsed_rest)
    return p

func _validate_collapsed_rest_roundtrip(p:Skeleton3D)->Dictionary:
    var max_position_error:=0.0
    var max_rotation_error:=0.0
    var worst_position_role:=""
    var worst_rotation_role:=""
    for role in ROLES:
        var pi:=p.find_bone(_canonical(role))
        var ti:=target_skeleton.find_bone(String(TARGET[role]))
        var a:=p.get_bone_global_rest(pi)
        var b:=target_skeleton.get_bone_global_rest(ti)
        var position_error:=a.origin.distance_to(b.origin)
        var rotation_error:=rad_to_deg(a.basis.orthonormalized().get_rotation_quaternion().angle_to(b.basis.orthonormalized().get_rotation_quaternion()))
        if position_error>max_position_error:
            max_position_error=position_error
            worst_position_role=role
        if rotation_error>max_rotation_error:
            max_rotation_error=rotation_error
            worst_rotation_role=role
    if max_position_error>MAX_COLLAPSED_REST_POSITION_ERROR_M:
        failures.append("collapsed_rest_position_error_m=%.9f role=%s"%[max_position_error,worst_position_role])
    if max_rotation_error>MAX_COLLAPSED_REST_ROTATION_ERROR_DEG:
        failures.append("collapsed_rest_rotation_error_deg=%.9f role=%s"%[max_rotation_error,worst_rotation_role])
    return {"max_position_error_m":max_position_error,"max_rotation_error_deg":max_rotation_error,"worst_position_role":worst_position_role,"worst_rotation_role":worst_rotation_role,"max_position_error_allowed_m":MAX_COLLAPSED_REST_POSITION_ERROR_M,"max_rotation_error_allowed_deg":MAX_COLLAPSED_REST_ROTATION_ERROR_DEG}

func _build_profile()->SkeletonProfile:
    var p:=SkeletonProfile.new()
    p.set_bone_size(ROLES.size())
    for i in range(ROLES.size()):
        var role:=String(ROLES[i])
        p.set_bone_name(i,_canonical(role))
        var parent:=String(PARENT[role])
        p.set_bone_parent(i,StringName() if parent.is_empty() else _canonical(parent))
        p.set_required(i,true)
    p.set_root_bone(_canonical("hips"))
    p.set_scale_base_bone(_canonical("hips"))
    return p

func _reset_probe(p:Skeleton3D)->void:
    p.reset_bone_poses()

func _measure_skin_edges(out:Dictionary)->void:
    for mesh in target_meshes:
        var skin:=mesh.skin
        for s in range(mesh.mesh.get_surface_count()):
            var arrays:=mesh.mesh.surface_get_arrays(s)
            var vertices=arrays[Mesh.ARRAY_VERTEX]
            var bones=arrays[Mesh.ARRAY_BONES]
            var weights=arrays[Mesh.ARRAY_WEIGHTS]
            var indices=arrays[Mesh.ARRAY_INDEX]
            if vertices==null or bones==null or weights==null or vertices.size()<3 or bones.size()==0 or bones.size()!=weights.size() or bones.size()%vertices.size()!=0: continue
            var ipv:=int(bones.size()/vertices.size())
            var ids:Array[int]=[]
            if indices!=null and indices.size()>=3:
                for v in indices: ids.append(int(v))
            else:
                for v in range(vertices.size()): ids.append(v)
            for tri in range(int(ids.size()/3)):
                var tri_ids=[ids[tri*3],ids[tri*3+1],ids[tri*3+2]]
                for pair in [[tri_ids[0],tri_ids[1]],[tri_ids[1],tri_ids[2]],[tri_ids[2],tri_ids[0]]]:
                    var a:=int(pair[0])
                    var b:=int(pair[1])
                    var ra:=_skin_vertex(vertices[a],a,bones,weights,ipv,skin,true)
                    var rb:=_skin_vertex(vertices[b],b,bones,weights,ipv,skin,true)
                    var pa:=_skin_vertex(vertices[a],a,bones,weights,ipv,skin,false)
                    var pb:=_skin_vertex(vertices[b],b,bones,weights,ipv,skin,false)
                    var rl:=ra.distance_to(rb)
                    if rl<MIN_EDGE_M: continue
                    var pl:=pa.distance_to(pb)
                    var ratio:=pl/rl
                    var delta:=absf(pl-rl)
                    out.edge_count=int(out.edge_count)+1
                    out.max_absolute_edge_change_m=maxf(float(out.max_absolute_edge_change_m),delta)
                    out.max_stretch_ratio=maxf(float(out.max_stretch_ratio),ratio)
                    out.min_compression_ratio=minf(float(out.min_compression_ratio),ratio)

func _skin_vertex(vertex:Vector3,vertex_index:int,bones,weights,ipv:int,skin:Skin,use_rest:bool)->Vector3:
    var acc:=Vector3.ZERO
    var tw:=0.0
    for j in range(ipv):
        var slot:=vertex_index*ipv+j
        var w:=float(weights[slot])
        if w<=0.0: continue
        var bind:=int(bones[slot])
        if bind<0 or bind>=skin.get_bind_count(): continue
        var bi:=skin.get_bind_bone(bind)
        if bi<0: bi=target_skeleton.find_bone(String(skin.get_bind_name(bind)))
        if bi<0: continue
        var bt:=target_skeleton.get_bone_global_rest(bi) if use_rest else target_skeleton.get_bone_global_pose(bi)
        acc+=(bt*skin.get_bind_pose(bind))*vertex*w
        tw+=w
    return vertex if tw<=0.000001 else acc/tw

func _find_skeleton(n:Node)->Skeleton3D:
    if n is Skeleton3D: return n as Skeleton3D
    for c in n.get_children():
        var f:=_find_skeleton(c)
        if f!=null: return f
    return null

func _find_exact_walk_player(n:Node)->AnimationPlayer:
    if n is AnimationPlayer and (n as AnimationPlayer).has_animation("walk"): return n as AnimationPlayer
    for c in n.get_children():
        var f:=_find_exact_walk_player(c)
        if f!=null: return f
    return null

func _collect_skinned_meshes(n:Node,out:Array[MeshInstance3D])->void:
    if n is MeshInstance3D and (n as MeshInstance3D).mesh!=null and (n as MeshInstance3D).skin!=null: out.append(n as MeshInstance3D)
    for c in n.get_children(): _collect_skinned_meshes(c,out)

func _canonical(role:String)->StringName:
    return StringName("gb_humanoid_%s"%role)

func _finish(state:String,metrics:Dictionary)->void:
    var result={"format":"grand-bruxelles-gate8-variant01-steve-canonical-native-probe-v2","engine_version":Engine.get_version_info().get("string","unknown"),"candidate_variant":1,"source":"Steve canonical reviewed proxy","mechanical_state":state,"metrics":metrics,"walk_alias_selected":"","run_alias_selected":"","production_authorized":false,"activation_ready":false,"adoption_ready":false,"visual_approval_claimed":false,"runtime_population_changed":false,"failures":failures}
    var f:=FileAccess.open(RESULT_PATH,FileAccess.WRITE)
    if f!=null:
        f.store_string(JSON.stringify(result,"  "))
        f.close()
    print("GATE8_STEVE_CANONICAL_NATIVE_PROBE state=%s failures=%d production_authorized=false"%[state,failures.size()])
    quit(0 if failures.is_empty() else 1)
