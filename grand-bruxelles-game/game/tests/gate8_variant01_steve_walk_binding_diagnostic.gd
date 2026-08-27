extends SceneTree

const SOURCE_SCENE := "res://assets/steve_reviewed_proxy.glb"
const RESULT_PATH := "res://gate8_variant01_steve_walk_binding_diagnostic.json"
const SOURCE_BONES := ["pelvis","waist","torso","neck","head","armup.L","armlo.L","hand.L","armup.R","armlo.R","hand.R","legup.L","leglo.L","foot1.L","legup.R","leglo.R","foot1.R"]

var failures:Array[String]=[]

func _init()->void:
    call_deferred("_run")

func _run()->void:
    var scene:=load(SOURCE_SCENE)
    if scene==null:
        _finish("BLOCKED_SOURCE_LOAD",{}); return
    var source_root:=scene.instantiate() as Node3D
    if source_root==null:
        _finish("BLOCKED_SOURCE_INSTANTIATE",{}); return
    root.add_child(source_root)
    await process_frame
    var skeleton:=_find_skeleton(source_root)
    var players:Array[AnimationPlayer]=[]
    _collect_players(source_root,players)
    if skeleton==null: failures.append("source_skeleton_missing")
    if players.is_empty(): failures.append("animation_players_missing")
    if not failures.is_empty(): _finish("BLOCKED_STRUCTURE",{"animation_player_count":players.size()}); return

    var player_records:Array=[]
    var selected:AnimationPlayer=null
    var selected_walk:=""
    for player in players:
        var anim_names:Array[String]=[]
        for a in player.get_animation_list():
            anim_names.append(String(a))
            if selected==null and _is_walk_name(String(a)):
                selected=player; selected_walk=String(a)
        player_records.append({
            "path":String(source_root.get_path_to(player)),
            "root_node":String(player.root_node),
            "animations":anim_names
        })
    if selected==null:
        failures.append("walk_animation_player_missing")
        _finish("BLOCKED_WALK_LOOKUP",{"players":player_records}); return

    var anim:=selected.get_animation(selected_walk)
    if anim==null:
        failures.append("walk_animation_missing")
        _finish("BLOCKED_WALK_LOOKUP",{"players":player_records}); return

    var animation_root:Node=selected.get_node_or_null(selected.root_node)
    var tracks:Array=[]
    var enabled_tracks:=0
    var resolved_node_tracks:=0
    var reviewed_bone_named_tracks:=0
    var reviewed_bone_hits:={}
    for bone in SOURCE_BONES: reviewed_bone_hits[bone]=0
    for i in range(anim.get_track_count()):
        var path:NodePath=anim.track_get_path(i)
        var path_text:=String(path)
        var enabled:=anim.track_is_enabled(i)
        if enabled: enabled_tracks+=1
        var names:Array[String]=[]
        for j in range(path.get_name_count()): names.append(String(path.get_name(j)))
        var subnames:Array[String]=[]
        for j in range(path.get_subname_count()): subnames.append(String(path.get_subname(j)))
        var node_path_text:="/".join(names)
        var resolved:Node=null
        if animation_root!=null:
            resolved=animation_root if node_path_text.is_empty() else animation_root.get_node_or_null(NodePath(node_path_text))
        if resolved!=null: resolved_node_tracks+=1
        var bone_hits:Array[String]=[]
        for bone in SOURCE_BONES:
            if path_text.contains(bone):
                bone_hits.append(bone); reviewed_bone_hits[bone]=int(reviewed_bone_hits[bone])+1
        if not bone_hits.is_empty(): reviewed_bone_named_tracks+=1
        tracks.append({
            "index":i,
            "type":int(anim.track_get_type(i)),
            "path":path_text,
            "node_names":names,
            "subnames":subnames,
            "enabled":enabled,
            "key_count":anim.track_get_key_count(i),
            "resolved_node":resolved!=null,
            "resolved_node_class":resolved.get_class() if resolved!=null else "",
            "reviewed_bone_hits":bone_hits
        })

    var skeleton_path:=String(source_root.get_path_to(skeleton))
    var selected_path:=String(source_root.get_path_to(selected))
    var sample_times:=[0.0,anim.length*0.25,anim.length*0.5,anim.length*0.75,anim.length]
    var samples:Array=[]
    var max_pose_delta_deg:=0.0
    selected.play(selected_walk)
    for t in sample_times:
        selected.seek(float(t),true)
        selected.advance(0.0)
        skeleton.force_update_all_bone_transforms()
        var role_deltas:={}
        for bone in SOURCE_BONES:
            var bi:=skeleton.find_bone(bone)
            if bi<0: continue
            var rest_q:=skeleton.get_bone_rest(bi).basis.orthonormalized().get_rotation_quaternion().normalized()
            var pose_q:=skeleton.get_bone_pose_rotation(bi).normalized()
            var deg:=rad_to_deg(rest_q.angle_to(pose_q))
            role_deltas[bone]=deg
            max_pose_delta_deg=maxf(max_pose_delta_deg,deg)
        samples.append({"time_s":float(t),"bone_pose_delta_deg":role_deltas})

    var metrics={
        "source_skeleton_path":skeleton_path,
        "source_skeleton_bones":skeleton.get_bone_count(),
        "animation_player_count":players.size(),
        "players":player_records,
        "selected_player_path":selected_path,
        "selected_player_root_node":String(selected.root_node),
        "animation_root_resolved":animation_root!=null,
        "animation_root_path_from_source":String(source_root.get_path_to(animation_root)) if animation_root!=null else "",
        "walk_animation":selected_walk,
        "walk_length_s":anim.length,
        "walk_track_count":anim.get_track_count(),
        "walk_enabled_track_count":enabled_tracks,
        "walk_resolved_node_track_count":resolved_node_tracks,
        "walk_reviewed_bone_named_track_count":reviewed_bone_named_tracks,
        "reviewed_bone_track_hits":reviewed_bone_hits,
        "tracks":tracks,
        "sampled_pose_deltas":samples,
        "max_sampled_pose_delta_deg":max_pose_delta_deg
    }
    var state:="WALK_TRACK_BINDING_CHARACTERIZED"
    if max_pose_delta_deg<=0.000001:
        state="WALK_TRACKS_PRESENT_BUT_NO_SKELETON_POSE_EXCITATION" if anim.get_track_count()>0 else "WALK_HAS_NO_TRACKS"
    _finish(state,metrics)

func _find_skeleton(n:Node)->Skeleton3D:
    if n is Skeleton3D: return n as Skeleton3D
    for c in n.get_children():
        var f:=_find_skeleton(c)
        if f!=null: return f
    return null

func _collect_players(n:Node,out:Array[AnimationPlayer])->void:
    if n is AnimationPlayer: out.append(n as AnimationPlayer)
    for c in n.get_children(): _collect_players(c,out)

func _is_walk_name(s:String)->bool:
    var t:=s.to_lower().replace("|","_").replace(":","_").split("_",false)
    return t.has("walk") and not t.has("backward") and not t.has("start") and not t.has("stop") and not t.has("transition") and not t.has("to")

func _finish(state:String,metrics:Dictionary)->void:
    var result={"format":"grand-bruxelles-gate8-variant01-steve-walk-binding-diagnostic-v1","engine_version":Engine.get_version_info().get("string","unknown"),"state":state,"metrics":metrics,"failures":failures,"production_authorized":false,"activation_ready":false,"adoption_ready":false}
    var f:=FileAccess.open(RESULT_PATH,FileAccess.WRITE)
    if f!=null: f.store_string(JSON.stringify(result,"  ")); f.close()
    print("GATE8_STEVE_WALK_BINDING_DIAGNOSTIC state=%s tracks=%d max_pose_delta_deg=%.9f failures=%d"%[state,int(metrics.get("walk_track_count",0)),float(metrics.get("max_sampled_pose_delta_deg",0.0)),failures.size()])
    quit(0 if failures.is_empty() else 1)
