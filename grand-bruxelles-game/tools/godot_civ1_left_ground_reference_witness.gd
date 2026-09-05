extends SceneTree

const BODY_PATH := "res://civ1_body.glb"
const HEAD_PATH := "res://vitruvian_head.glb"
const MAIN_SCENE_PATH := "res://game/main.tscn"
const MAIN_GROUND_PATH := NodePath("Ground")
const HEAD_BONE := "mixamorig_Head"
const WIDTH := 1280
const HEIGHT := 720
const POSE_BONES := ["Hips", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
const TARGET_SAMPLES := [114, 115, 116, 117, 118, 119]
const CANDIDATE_SAMPLES := [115, 116, 117, 118]
# Diagnostic kinematic sole proxy only. This is intentionally not a rendered-mesh contact claim.
const LEFT_SOLE_PROXY_LOCAL := Vector3(0.0, -0.012, 0.08)
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

func _foot_world_transform(skeleton:Skeleton3D, mapping:Dictionary, semantic:String)->Transform3D:
    return skeleton.global_transform*skeleton.get_bone_global_pose(int(mapping[semantic]))

func _ground_hit(world:Node3D, from:Vector3)->Dictionary:
    var query:=PhysicsRayQueryParameters3D.create(from+Vector3.UP*0.25,from+Vector3.DOWN*0.75)
    query.collide_with_areas=false
    query.collide_with_bodies=true
    return world.get_world_3d().direct_space_state.intersect_ray(query)

func _xz_path(records:Array, key:String)->float:
    var path:=0.0
    for j in range(1,records.size()):
        var a:Array=records[j-1][key]; var b:Array=records[j][key]
        path+=Vector2(float(b[0])-float(a[0]),float(b[1])-float(a[1])).length()
    return path

func _run()->void:
    var bundle=_read_json(_bundle_path)
    if not bundle is Dictionary or bundle.get("schema","")!="grand-bruxelles-civ1-skeleton-witness-bundle-v1": push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: bundle"); quit(3); return
    if bool(bundle.get("runtime_authorized",true)) or bool(bundle.get("visual_approval_claimed",true)) or bool(bundle.get("player_view_claimed",true)): push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: rail"); quit(4); return
    var frames:Array=bundle.get("frames",[])
    if frames.size()!=120: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: frames"); quit(5); return
    var body_scene:=load(BODY_PATH) as PackedScene; var head_scene:=load(HEAD_PATH) as PackedScene; var main_scene:=load(MAIN_SCENE_PATH) as PackedScene
    if body_scene==null or head_scene==null or main_scene==null: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: assets_or_main_scene"); quit(6); return
    var canonical_main:=main_scene.instantiate(); var canonical_ground:=canonical_main.get_node_or_null(MAIN_GROUND_PATH) as CSGBox3D
    if canonical_ground==null or not canonical_ground.use_collision: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: canonical_ground"); canonical_main.free(); quit(7); return
    if canonical_ground.rotation.length()>1e-8: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: rotated_ground"); canonical_main.free(); quit(8); return
    var ground_top_y:=canonical_ground.position.y+canonical_ground.size.y*0.5; var ground_copy:=canonical_ground.duplicate() as CSGBox3D; canonical_main.free()
    if ground_copy==null or not ground_copy.use_collision: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: ground_duplicate"); quit(9); return
    ground_copy.name="CanonicalMainGround"
    var world:=Node3D.new(); world.name="CIV1CanonicalGroundWitness"; root.add_child(world); world.add_child(ground_copy)
    var body:=body_scene.instantiate(); world.add_child(body); var skeleton:=_find_skeleton(body)
    if skeleton==null: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: skeleton"); quit(10); return
    var mapping:={}
    for semantic in POSE_BONES:
        var idx:=_bone_index(skeleton,semantic)
        if idx<0: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: bone "+semantic); quit(11); return
        mapping[semantic]=idx
    var head_idx:=skeleton.find_bone(HEAD_BONE)
    if head_idx<0: push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: head bone"); quit(12); return
    var attachment:=BoneAttachment3D.new(); skeleton.add_child(attachment); attachment.bone_idx=head_idx
    var head_rig:=Node3D.new(); attachment.add_child(head_rig); head_rig.global_transform=Transform3D.IDENTITY; head_rig.add_child(head_scene.instantiate())
    var bilateral_floor_y:=INF
    for frame in frames: bilateral_floor_y=min(bilateral_floor_y,_frame_pose(frame,"LeftFoot").origin.y,_frame_pose(frame,"RightFoot").origin.y)
    if not is_finite(bilateral_floor_y): push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: placement_reference"); quit(13); return
    var placement_y:=ground_top_y-bilateral_floor_y; body.position.y=placement_y
    var camera:=Camera3D.new(); camera.position=Vector3(2.35,0.23+placement_y,0.0); camera.fov=32.0; world.add_child(camera); camera.look_at(Vector3(0.0,0.16+placement_y,0.0)); camera.current=true
    var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-35,-25,0); key.light_energy=1.5; world.add_child(key)
    var fill:=OmniLight3D.new(); fill.position=Vector3(1.2,1.0,1.2); fill.omni_range=5.0; fill.light_energy=3.0; world.add_child(fill)
    root.size=Vector2i(WIDTH,HEIGHT)
    var max_pose_error:=_apply_frame(skeleton,mapping,frames[0]); await process_frame; await physics_frame; await process_frame
    var expected0:=skeleton.global_transform*skeleton.get_bone_global_pose(head_idx); var calibration:=expected0.affine_inverse()*attachment.global_transform
    var max_head_follow_error:=0.0; var samples:Array=[]; var captures:Array=[]; DirAccess.make_dir_recursive_absolute(_capture_dir)
    for i in range(frames.size()):
        max_pose_error=max(max_pose_error,_apply_frame(skeleton,mapping,frames[i])); await process_frame; await physics_frame
        var expected:=skeleton.global_transform*skeleton.get_bone_global_pose(head_idx)*calibration; max_head_follow_error=max(max_head_follow_error,attachment.global_transform.origin.distance_to(expected.origin))
        if i in TARGET_SAMPLES:
            var left_tf:=_foot_world_transform(skeleton,mapping,"LeftFoot"); var right_tf:=_foot_world_transform(skeleton,mapping,"RightFoot")
            var left:=left_tf.origin; var right:=right_tf.origin; var sole:=left_tf*LEFT_SOLE_PROXY_LOCAL
            var left_hit:=_ground_hit(world,left); var right_hit:=_ground_hit(world,right); var sole_hit:=_ground_hit(world,sole)
            if left_hit.is_empty() or right_hit.is_empty() or sole_hit.is_empty(): push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: canonical_ground_ray_miss"); quit(14); return
            var left_collider:=left_hit.get("collider") as Object; var right_collider:=right_hit.get("collider") as Object; var sole_collider:=sole_hit.get("collider") as Object
            var left_hit_y:=float(Vector3(left_hit["position"]).y); var right_hit_y:=float(Vector3(right_hit["position"]).y); var sole_hit_y:=float(Vector3(sole_hit["position"]).y)
            samples.append({"sample_index":i,"left_world":[left.x,left.y,left.z],"right_world":[right.x,right.y,right.z],"sole_proxy_world":[sole.x,sole.y,sole.z],"left_ground_hit_y_m":left_hit_y,"right_ground_hit_y_m":right_hit_y,"sole_proxy_ground_hit_y_m":sole_hit_y,"left_clearance_m":left.y-left_hit_y,"right_clearance_m":right.y-right_hit_y,"sole_proxy_clearance_m":sole.y-sole_hit_y,"left_xz":[left.x,left.z],"sole_proxy_xz":[sole.x,sole.z],"left_collider_name":String(left_collider.get("name")) if left_collider!=null else "","right_collider_name":String(right_collider.get("name")) if right_collider!=null else "","sole_proxy_collider_name":String(sole_collider.get("name")) if sole_collider!=null else ""})
            var png:=_capture_dir.path_join("left-ground-side-%03d.png"%i)
            if not await _capture(png): push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: capture"); quit(15); return
            captures.append({"sample_index":i,"png":png,"view":"low_side_contact"})
    var candidate:Array=[]
    for rec in samples:
        if int(rec["sample_index"]) in CANDIDATE_SAMPLES: candidate.append(rec)
    var min_clear:=INF; var max_clear:=-INF; var sole_min:=INF; var sole_max:=-INF
    for rec in candidate:
        min_clear=min(min_clear,float(rec["left_clearance_m"])); max_clear=max(max_clear,float(rec["left_clearance_m"])); sole_min=min(sole_min,float(rec["sole_proxy_clearance_m"])); sole_max=max(sole_max,float(rec["sole_proxy_clearance_m"]))
    var report={"schema":"grand-bruxelles-civ1-left-ground-reference-v3","diagnostic_only":true,"ground_contact_claimed":false,"rendered_sole_contact_claimed":false,"sole_proxy_semantic":"left_foot_bone_oriented_kinematic_proxy_not_rendered_mesh","sole_proxy_local_m":[LEFT_SOLE_PROXY_LOCAL.x,LEFT_SOLE_PROXY_LOCAL.y,LEFT_SOLE_PROXY_LOCAL.z],"reference_is_external_scene_ground":true,"reference_semantic":"canonical_main_ground_collision_raycast","source_scene":MAIN_SCENE_PATH,"source_ground_node":String(MAIN_GROUND_PATH),"ground_use_collision":true,"ground_top_y_m":ground_top_y,"placement_semantic":"align_bilateral_cycle_lower_envelope_to_canonical_ground_top","placement_y_m":placement_y,"camera_semantic":"low_side_contact_view_tracks_placement_y","camera_tracks_placement_y":true,"target_left_candidate_samples":CANDIDATE_SAMPLES,"context_samples":TARGET_SAMPLES,"candidate_left_horizontal_path_m":_xz_path(candidate,"left_xz"),"candidate_sole_proxy_horizontal_path_m":_xz_path(candidate,"sole_proxy_xz"),"candidate_left_min_clearance_m":min_clear,"candidate_left_max_clearance_m":max_clear,"candidate_sole_proxy_min_clearance_m":sole_min,"candidate_sole_proxy_max_clearance_m":sole_max,"runtime_authorized":false,"visual_approval_claimed":false,"player_view_claimed":false,"resolution":[WIDTH,HEIGHT],"max_pose_origin_error_m":max_pose_error,"max_head_follow_error_m":max_head_follow_error,"samples":samples,"captures":captures,"verdict":"AMELIORER_CANONICAL_GROUND_SOLE_PROXY_CONTACT_UNPROVEN"}
    if max_pose_error>0.0001 or max_head_follow_error>0.0001: report["verdict"]="JETER_DYNAMIC_TECHNICAL_DRIFT"
    if not _write_json(_report_path,report): push_error("CIV1_LEFT_GROUND_REFERENCE_FAIL: report"); quit(16); return
    print("CIV1_LEFT_GROUND_REFERENCE_OK ground_top=%.6f bone_path=%.6f sole_path=%.6f sole_clearance=[%.6f,%.6f] pose=%.9f head=%.9f"%[ground_top_y,report["candidate_left_horizontal_path_m"],report["candidate_sole_proxy_horizontal_path_m"],sole_min,sole_max,max_pose_error,max_head_follow_error])
    quit(0 if report["verdict"]!="JETER_DYNAMIC_TECHNICAL_DRIFT" else 17)
