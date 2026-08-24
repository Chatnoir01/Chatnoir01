extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const ROLE_PAIRS := {
	"hips":["DEF-hips","pelvis"], "spine":["DEF-spine.001","spine_01"], "chest":["DEF-spine.002","spine_02"], "upper_chest":["DEF-spine.003","spine_03"], "neck":["DEF-neck","neck_01"], "head":["DEF-head","head"],
	"left_shoulder":["DEF-shoulder.L","clavicle_l"], "left_upper_arm":["DEF-upper_arm.L","upperarm_l"], "left_forearm":["DEF-forearm.L","lowerarm_l"], "left_hand":["DEF-hand.L","hand_l"],
	"right_shoulder":["DEF-shoulder.R","clavicle_r"], "right_upper_arm":["DEF-upper_arm.R","upperarm_r"], "right_forearm":["DEF-forearm.R","lowerarm_r"], "right_hand":["DEF-hand.R","hand_r"],
	"left_upper_leg":["DEF-thigh.L","thigh_l"], "left_lower_leg":["DEF-shin.L","calf_l"], "left_foot":["DEF-foot.L","foot_l"], "left_toe":["DEF-toe.L","ball_l"],
	"right_upper_leg":["DEF-thigh.R","thigh_r"], "right_lower_leg":["DEF-shin.R","calf_r"], "right_foot":["DEF-foot.R","foot_r"], "right_toe":["DEF-toe.R","ball_r"]
}
const LOCAL_WARN_DEG := 45.0
const DIRECTION_WARN_DEG := 35.0
var failures:Array[String]=[]

func _init() -> void: call_deferred("_run")

func _run() -> void:
	var s_scene := load(SOURCE_SCENE).instantiate() as Node3D
	var t_scene := load(TARGET_SCENE).instantiate() as Node3D
	if s_scene == null or t_scene == null:
		_finish({"failures":["scene_load_failed"]}); return
	root.add_child(s_scene); root.add_child(t_scene)
	await process_frame
	var s := _find_skeleton(s_scene); var t := _find_skeleton(t_scene)
	if s == null or t == null:
		_finish({"failures":["skeleton_missing"]}); return
	var rows := {}; var local_peak := 0.0; var direction_peak := 0.0; var length_ratio_min := INF; var length_ratio_max := 0.0
	for role in ROLE_PAIRS:
		var si := s.find_bone(String(ROLE_PAIRS[role][0])); var ti := t.find_bone(String(ROLE_PAIRS[role][1]))
		if si < 0 or ti < 0:
			failures.append("role_missing=%s" % role); continue
		var sr := s.get_bone_rest(si); var tr := t.get_bone_rest(ti)
		var local_deg := rad_to_deg(sr.basis.orthonormalized().get_rotation_quaternion().angle_to(tr.basis.orthonormalized().get_rotation_quaternion()))
		var dir_deg := 0.0; var ratio := 1.0
		var sp := s.get_bone_parent(si); var tp := t.get_bone_parent(ti)
		if sp >= 0 and tp >= 0:
			var sd := s.get_bone_global_rest(si).origin - s.get_bone_global_rest(sp).origin
			var td := t.get_bone_global_rest(ti).origin - t.get_bone_global_rest(tp).origin
			if sd.length() <= 0.000001 or td.length() <= 0.000001:
				failures.append("zero_segment=%s" % role)
			else:
				dir_deg = rad_to_deg(sd.normalized().angle_to(td.normalized()))
				ratio = td.length() / sd.length(); length_ratio_min = minf(length_ratio_min,ratio); length_ratio_max=maxf(length_ratio_max,ratio)
		local_peak=maxf(local_peak,local_deg); direction_peak=maxf(direction_peak,dir_deg)
		rows[role]={"source_bone":s.get_bone_name(si),"target_bone":t.get_bone_name(ti),"local_rest_delta_deg":local_deg,"parent_child_direction_delta_deg":dir_deg,"segment_length_ratio":ratio}
	var outliers:Array[String]=[]
	for role in rows:
		var r:Dictionary=rows[role]
		if float(r.local_rest_delta_deg)>LOCAL_WARN_DEG or float(r.parent_child_direction_delta_deg)>DIRECTION_WARN_DEG: outliers.append(String(role))
	var result={"format":"grand-bruxelles-gate8-rest-frame-compatibility-v1","engine_version":Engine.get_version_info().get("string","unknown"),"candidate_variant":1,"reviewed_roles":ROLE_PAIRS.size(),"measured_roles":rows.size(),"local_rest_peak_deg":local_peak,"direction_peak_deg":direction_peak,"segment_length_ratio_min":length_ratio_min,"segment_length_ratio_max":length_ratio_max,"outlier_roles":outliers,"roles":rows,"diagnostic_only":true,"run_alias_selected":"","production_authorized":false,"activation_ready":false,"adoption_ready":false,"selection_state":"REST_FRAME_MISMATCH_MEASURED" if outliers.size()>0 else "REST_FRAME_COMPATIBLE_BY_DIAGNOSTIC","failures":failures}
	_finish(result)

func _find_skeleton(n:Node)->Skeleton3D:
	if n is Skeleton3D: return n
	for c in n.get_children():
		var f:=_find_skeleton(c)
		if f!=null:return f
	return null

func _finish(result:Dictionary)->void:
	var path:="res://gate8_variant01_rest_frame_compatibility.json"
	var f:=FileAccess.open(path,FileAccess.WRITE)
	if f: f.store_string(JSON.stringify(result,"  ")); f.close()
	if result.has("failures") and (result.failures as Array).size()>0:
		for e in result.failures: push_error(String(e))
		quit(1); return
	print("GATE8_REST_FRAME_COMPATIBILITY_OK roles=%d outliers=%d production_authorized=false" % [int(result.get("measured_roles",0)), (result.get("outlier_roles",[]) as Array).size()])
	quit(0)
