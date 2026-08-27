extends "res://base_probe.gd"

var binding_diagnostic:Dictionary={}

func _run()->void:
    binding_diagnostic=_diagnose_binding()
    await super._run()

func _diagnose_binding()->Dictionary:
    var packed:=load(SOURCE_SCENE)
    if packed==null: return {"state":"SOURCE_LOAD_FAILED"}
    var n:=packed.instantiate()
    if n==null: return {"state":"SOURCE_INSTANTIATE_FAILED"}
    var sk:=_find_skeleton(n)
    var players:Array[AnimationPlayer]=[]
    _collect_players_local(n,players)
    var records:Array=[]
    var walk_tracks:Array=[]
    var walk_player_path:=""
    var walk_root_node:=""
    for p in players:
        var names:Array[String]=[]
        for a in p.get_animation_list():
            var an:=String(a); names.append(an)
            if walk_tracks.is_empty() and _is_walk_name(an):
                walk_player_path=String(n.get_path_to(p)); walk_root_node=String(p.root_node)
                var anim:=p.get_animation(an)
                for i in range(anim.get_track_count()):
                    var path:=String(anim.track_get_path(i))
                    var hits:Array[String]=[]
                    for bone in SOURCE.values():
                        if path.contains(String(bone)): hits.append(String(bone))
                    walk_tracks.append({"index":i,"type":int(anim.track_get_type(i)),"path":path,"enabled":anim.track_is_enabled(i),"key_count":anim.track_get_key_count(i),"reviewed_bone_hits":hits})
        records.append({"path":String(n.get_path_to(p)),"root_node":String(p.root_node),"animations":names})
    var named:=0
    for t in walk_tracks:
        if not (t.reviewed_bone_hits as Array).is_empty(): named+=1
    n.free()
    return {"state":"TRACK_INVENTORY_CAPTURED","skeleton_bones":sk.get_bone_count() if sk!=null else -1,"animation_player_count":players.size(),"players":records,"walk_player_path":walk_player_path,"walk_player_root_node":walk_root_node,"walk_track_count":walk_tracks.size(),"walk_reviewed_bone_named_track_count":named,"walk_tracks":walk_tracks}

func _collect_players_local(n:Node,out:Array[AnimationPlayer])->void:
    if n is AnimationPlayer: out.append(n as AnimationPlayer)
    for c in n.get_children(): _collect_players_local(c,out)

func _finish(state:String,metrics:Dictionary)->void:
    metrics["walk_import_binding_diagnostic"]=binding_diagnostic
    super._finish(state,metrics)

# A contact threshold derived independently for each foot can classify an
# always-airborne foot as planted, because its own high minimum becomes its
# support floor. Use the shared cycle floor from both feet instead.
func _measure_slide(left:Array[Vector3],right:Array[Vector3],dt:float)->Dictionary:
    var lmin:=INF
    var rmin:=INF
    var lpath:=0.0
    var rpath:=0.0
    for i in range(left.size()):
        lmin=minf(lmin,left[i].y)
        rmin=minf(rmin,right[i].y)
    for i in range(1,left.size()):
        lpath+=Vector2(left[i].x-left[i-1].x,left[i].z-left[i-1].z).length()
        rpath+=Vector2(right[i].x-right[i-1].x,right[i].z-right[i-1].z).length()
    var shared_floor_y:=minf(lmin,rmin)
    var contact_threshold_y:=shared_floor_y+CONTACT_HEIGHT_EPS_M
    var raw_sum:=0.0
    var raw_peak:=0.0
    var residual_sum:=0.0
    var residual_peak:=0.0
    var root_sum:=0.0
    var root_peak:=0.0
    var disagreement_peak:=0.0
    var contact_vel_count:=0
    var interval_count:=0
    var double_support_count:=0
    var left_contact_count:=0
    var right_contact_count:=0
    for i in range(1,left.size()):
        var lv:=Vector2(left[i].x-left[i-1].x,left[i].z-left[i-1].z)/dt
        var rv:=Vector2(right[i].x-right[i-1].x,right[i].z-right[i-1].z)/dt
        var lc:=left[i].y<=contact_threshold_y and left[i-1].y<=contact_threshold_y
        var rc:=right[i].y<=contact_threshold_y and right[i-1].y<=contact_threshold_y
        if not lc and not rc: continue
        interval_count+=1
        if lc: left_contact_count+=1
        if rc: right_contact_count+=1
        var root:=Vector2.ZERO
        if lc and rc:
            root=-(lv+rv)*0.5; double_support_count+=1; disagreement_peak=maxf(disagreement_peak,(lv-rv).length())
        elif lc: root=-lv
        else: root=-rv
        var root_speed:=root.length(); root_sum+=root_speed; root_peak=maxf(root_peak,root_speed)
        if lc:
            var raw:=lv.length(); var residual:=(lv+root).length(); raw_sum+=raw; raw_peak=maxf(raw_peak,raw); residual_sum+=residual; residual_peak=maxf(residual_peak,residual); contact_vel_count+=1
        if rc:
            var raw:=rv.length(); var residual:=(rv+root).length(); raw_sum+=raw; raw_peak=maxf(raw_peak,raw); residual_sum+=residual; residual_peak=maxf(residual_peak,residual); contact_vel_count+=1
    return {"contact_model":"shared_cycle_floor_v2","contact_height_epsilon_m":CONTACT_HEIGHT_EPS_M,"shared_cycle_floor_y_m":shared_floor_y,"contact_threshold_y_m":contact_threshold_y,"left_cycle_min_y_m":lmin,"right_cycle_min_y_m":rmin,"left_foot_path_m":lpath,"right_foot_path_m":rpath,"contact_interval_count":interval_count,"left_contact_interval_count":left_contact_count,"right_contact_interval_count":right_contact_count,"contact_velocity_sample_count":contact_vel_count,"double_support_interval_count":double_support_count,"raw_contact_slide_mean_mps":raw_sum/float(maxi(1,contact_vel_count)),"raw_contact_slide_peak_mps":raw_peak,"optimal_root_compensation_mean_mps":root_sum/float(maxi(1,interval_count)),"optimal_root_compensation_peak_mps":root_peak,"irreducible_contact_slide_mean_mps":residual_sum/float(maxi(1,contact_vel_count)),"irreducible_contact_slide_peak_mps":residual_peak,"double_support_velocity_disagreement_peak_mps":disagreement_peak}
