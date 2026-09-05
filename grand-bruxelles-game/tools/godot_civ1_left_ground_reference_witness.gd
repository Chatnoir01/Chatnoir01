extends SceneTree

const BODY_PATH := "res://civ1_body.glb"
const HEAD_PATH := "res://vitruvian_head.glb"
const HEAD_BONE := "mixamorig_Head"
const WIDTH := 1280
const HEIGHT := 720
const POSE_BONES := ["Hips", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
const TARGET_SAMPLES := [114, 115, 116, 117, 118, 119]
const ALIASES := {
    "Hips":["hips","pelvis"], "RightUpperLeg":["rightupperleg","rightupleg","rupperleg"],
    "RightLowerLeg":["rightlowerleg","rightleg","rlowerleg"], "RightFoot":["rightfoot","rfoot"],
    "LeftUpperLeg":["leftupperleg","leftupleg","lupperleg"], "LeftLowerLeg":["leftlowerleg","leftleg","llowerleg"],
    "LeftFoot":["leftfoot","lfoot"]
}
var _bundle_path := ""
var _report_path := ""
var _capture_dir := ""

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 3: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: args"); quit(2); return
    _bundle_path=args[0]; _report_path=args[1]; _capture_dir=args[2]; call_deferred("_run")

func _norm(v:String)->String:
    var n:=v.to_lower()
    for t in [":","/",".","-","_"," "]: n=n.replace(t,"")
    for p in ["mixamorig","armature","general","def"]:
        if n.begins_with(p): n=n.trim_prefix(p)
    return n

func _bone_index(s:Skeleton3D, semantic:String)->int:
    for i in range(s.get_bone_count()):
        var n:=_norm(s.get_bone_name(i))
        for a in Array(ALIASES.get(semantic, [])):
            if n==String(a): return i
    return -1

func _find_skeleton(n:Node)->Skeleton3D:
    if n is Skeleton3D: return n as Skeleton3D
    for c in n.get_children():
        var f:=_find_skeleton(c)
        if f!=null: return f
    return null

func _read_json(path:String)->Variant:
    var f:=FileAccess.open(path,FileAccess.READ)
    if f==null:return null
    var p:Variant=JSON.parse_string(f.get_as_text()); f.close(); return p

func _v3(v:Variant)->Vector3:
    if not v is Array or v.size()!=3:return Vector3(INF,INF,INF)
    return Vector3(float(v[0]),float(v[1]),float(v[2]))

func _quat(v:Variant)->Quaternion:
    if not v is Array or v.size()!=4:return Quaternion(INF,INF,INF,INF)
    return Quaternion(float(v[0]),float(v[1]),float(v[2]),float(v[3])).normalized()

func _pose(rec:Dictionary)->Transform3D:
    return Transform3D(Basis(_quat(rec.get("rotation_xyzw",[]))),_v3(rec.get("origin",[])))

func _frame_pose(frame:Dictionary, semantic:String)->Transform3D:
    return _pose(Dictionary(frame.get("poses",{})).get(semantic,{}))

func _apply_frame(s:Skeleton3D,m:Dictionary,f:Dictionary)->float:
    var e:=0.0
    for semantic in POSE_BONES: s.set_bone_global_pose(int(m[semantic]),_frame_pose(f,semantic))
    s.force_update_all_bone_transforms()
    for semantic in POSE_BONES: e=max(e,s.get_bone_global_pose(int(m[semantic])).origin.distance_to(_frame_pose(f,semantic).origin))
    return e

func _capture(path:String)->bool:
    await process_frame; await RenderingServer.frame_post_draw
    var im:=root.get_texture().get_image()
    return im!=null and im.get_width()==WIDTH and im.get_height()==HEIGHT and im.save_png(path)==OK

func _write_json(path:String,data:Dictionary)->bool:
    var f:=FileAccess.open(path,FileAccess.WRITE)
    if f==null:return false
    f.store_string(JSON.stringify(data,"  ")); f.close(); return true

func _run()->void:
    var bundle=_read_json(_bundle_path)
    if not bundle is Dictionary or bundle.get("schema","")!="grand-bruxelles-civ1-skeleton-witness-bundle-v1": push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: bundle"); quit(3); return
    if bool(bundle.get("runtime_authorized",true)) or bool(bundle.get("visual_approval_claimed",true)) or bool(bundle.get("player_view_claimed",true)): push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: rail"); quit(4); return
    var frames:Array=bundle.get("frames",[])
    if frames.size()!=120: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: frames"); quit(5); return
    var body_scene:=load(BODY_PATH) as PackedScene; var head_scene:=load(HEAD_PATH) as PackedScene
    if body_scene==null or head_scene==null: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: assets"); quit(6); return
    var world:=Node3D.new(); root.add_child(world); var body:=body_scene.instantiate(); world.add_child(body); var skeleton:=_find_skeleton(body)
    if skeleton==null: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: skeleton"); quit(7); return
    var mapping:={}
    for semantic in POSE_BONES:
        var idx:=_bone_index(skeleton,semantic)
        if idx<0: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: bone "+semantic); quit(8); return
        mapping[semantic]=idx
    var head_idx:=skeleton.find_bone(HEAD_BONE)
    if head_idx<0: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: head bone"); quit(9); return
    var attachment:=BoneAttachment3D.new(); skeleton.add_child(attachment); attachment.bone_idx=head_idx
    var head_rig:=Node3D.new(); attachment.add_child(head_rig); head_rig.global_transform=Transform3D.IDENTITY
    head_rig.add_child(head_scene.instantiate())
    var bilateral_floor_y:=INF
    for frame in frames:
        bilateral_floor_y=min(bilateral_floor_y,_frame_pose(frame,"LeftFoot").origin.y,_frame_pose(frame,"RightFoot").origin.y)
    if not is_finite(bilateral_floor_y): push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: reference"); quit(10); return
    var plane_mesh:=PlaneMesh.new(); plane_mesh.size=Vector2(2.4,2.4)
    var mat:=StandardMaterial3D.new(); mat.albedo_color=Color(0.28,0.32,0.34,1.0); mat.roughness=1.0; plane_mesh.material=mat
    var plane:=MeshInstance3D.new(); plane.mesh=plane_mesh; plane.position.y=bilateral_floor_y; world.add_child(plane)
    var camera:=Camera3D.new(); camera.position=Vector3(0.0,0.95,3.0); camera.fov=40.0; world.add_child(camera); camera.look_at(Vector3(0.0,0.85,0.0)); camera.current=true
    var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-35,-25,0); key.light_energy=1.5; world.add_child(key)
    var fill:=OmniLight3D.new(); fill.position=Vector3(1.2,1.4,2.0); fill.omni_range=6.0; fill.light_energy=3.0; world.add_child(fill)
    root.size=Vector2i(WIDTH,HEIGHT)
    var max_pose_error:=_apply_frame(skeleton,mapping,frames[0]); await process_frame; await process_frame
    var expected0:=skeleton.global_transform*skeleton.get_bone_global_pose(head_idx); var calibration:=expected0.affine_inverse()*attachment.global_transform
    var max_head_follow_error:=0.0; var clearances:Array=[]; var captures:Array=[]
    DirAccess.make_dir_recursive_absolute(_capture_dir)
    for i in range(frames.size()):
        max_pose_error=max(max_pose_error,_apply_frame(skeleton,mapping,frames[i])); await process_frame
        var expected:=skeleton.global_transform*skeleton.get_bone_global_pose(head_idx)*calibration
        max_head_follow_error=max(max_head_follow_error,attachment.global_transform.origin.distance_to(expected.origin))
        if i in TARGET_SAMPLES:
            var left:=_frame_pose(frames[i],"LeftFoot").origin; var right:=_frame_pose(frames[i],"RightFoot").origin
            var rec={"sample_index":i,"left_clearance_m":left.y-bilateral_floor_y,"right_clearance_m":right.y-bilateral_floor_y,"left_xz":[left.x,left.z]}; clearances.append(rec)
            var png:=_capture_dir.path_join("left-ground-%03d.png"%i)
            if not await _capture(png): push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: capture"); quit(11); return
            captures.append({"sample_index":i,"png":png})
    var candidate:Array=[]
    for rec in clearances:
        if int(rec["sample_index"]) in [115,116,117,118]: candidate.append(rec)
    var path:=0.0
    for j in range(1,candidate.size()):
        var a:Array=candidate[j-1]["left_xz"]; var b:Array=candidate[j]["left_xz"]; path+=Vector2(float(b[0])-float(a[0]),float(b[1])-float(a[1])).length()
    var min_clear:=INF; var max_clear:=-INF
    for rec in candidate: min_clear=min(min_clear,float(rec["left_clearance_m"])); max_clear=max(max_clear,float(rec["left_clearance_m"]))
    var report={"schema":"grand-bruxelles-civ1-left-ground-reference-v1","diagnostic_only":true,"ground_contact_claimed":false,"reference_is_external_scene_ground":false,"reference_semantic":"bilateral_cycle_lower_envelope_y","reference_y_m":bilateral_floor_y,"target_left_candidate_samples":[115,116,117,118],"context_samples":TARGET_SAMPLES,"candidate_left_horizontal_path_m":path,"candidate_left_min_clearance_m":min_clear,"candidate_left_max_clearance_m":max_clear,"runtime_authorized":false,"visual_approval_claimed":false,"player_view_claimed":false,"resolution":[WIDTH,HEIGHT],"max_pose_origin_error_m":max_pose_error,"max_head_follow_error_m":max_head_follow_error,"captures":captures,"verdict":"AMELIORER_REFERENCE_PLANE_ONLY_GROUND_CONTACT_UNPROVEN"}
    if max_pose_error>0.0001 or max_head_follow_error>0.0001: report["verdict"]="JETER_DYNAMIC_TECHNICAL_DRIFT"
    if not _write_json(_report_path,report): push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: report"); quit(12); return
    print("CIV1_LEFT_GROUND_REFERENCE_OK reference_y=%.6f left_path=%.6f clearance=[%.6f,%.6f] pose=%.9f head=%.9f"%[bilateral_floor_y,path,min_clear,max_clear,max_pose_error,max_head_follow_error])
    quit(0 if report["verdict"]!="JETER_DYNAMIC_TECHNICAL_DRIFT" else 13)
