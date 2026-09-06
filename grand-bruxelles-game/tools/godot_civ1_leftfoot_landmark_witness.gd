extends SceneTree

const BODY_PATH := "res://civ1_body.glb"
const MAIN_SCENE_PATH := "res://game/main.tscn"
const MAIN_GROUND_PATH := NodePath("Ground")
const WIDTH := 1280
const HEIGHT := 720
const VERTICAL_FOV_DEG := 45.0
const PLAYER_DISTANCES_M := [2.0, 4.0, 8.0]
const TARGET_SAMPLES := [114, 115, 116, 117, 118]
const POSE_BONES := ["Hips", "RightUpperLeg", "RightLowerLeg", "RightFoot", "LeftUpperLeg", "LeftLowerLeg", "LeftFoot"]
const ALIASES := {
    "Hips":["hips","pelvis"], "RightUpperLeg":["rightupperleg","rightupleg","rupperleg"],
    "RightLowerLeg":["rightlowerleg","rightleg","rlowerleg"], "RightFoot":["rightfoot","rfoot"],
    "LeftUpperLeg":["leftupperleg","leftupleg","lupperleg"], "LeftLowerLeg":["leftlowerleg","leftleg","llowerleg"],
    "LeftFoot":["leftfoot","lfoot"]
}
const MARKER_RADIUS_M := 0.025
const MARKER_COLOR := Color(1.0, 0.0, 1.0, 1.0)
var _bundle_path := ""
var _report_path := ""
var _capture_dir := ""

func _init() -> void:
    var args := OS.get_cmdline_user_args()
    if args.size() != 3:
        push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: args")
        quit(2)
        return
    _bundle_path = args[0]
    _report_path = args[1]
    _capture_dir = args[2]
    call_deferred("_run")

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
        var found:=_find_skeleton(c)
        if found!=null: return found
    return null

func _collect_mesh_integrity(n:Node, skeleton:Skeleton3D, out:Dictionary)->void:
    if n is MeshInstance3D:
        var mi:=n as MeshInstance3D
        if mi.mesh!=null:
            out["mesh_instance_count"]=int(out.get("mesh_instance_count",0))+1
            out["surface_count"]=int(out.get("surface_count",0))+mi.mesh.get_surface_count()
        if mi.skin!=null:
            out["skinned_mesh_count"]=int(out.get("skinned_mesh_count",0))+1
            out["skin_bind_count"]=int(out.get("skin_bind_count",0))+mi.skin.get_bind_count()
            var resolved:=mi.get_node_or_null(mi.skeleton)
            if resolved==skeleton:
                out["same_skeleton_skin_count"]=int(out.get("same_skeleton_skin_count",0))+1
    for c in n.get_children(): _collect_mesh_integrity(c,skeleton,out)

func _read_json(path:String)->Variant:
    var f:=FileAccess.open(path,FileAccess.READ)
    if f==null:return null
    var parsed:Variant=JSON.parse_string(f.get_as_text())
    f.close()
    return parsed

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
    var max_error:=0.0
    for semantic in POSE_BONES:
        s.set_bone_global_pose(int(m[semantic]),_frame_pose(f,semantic))
    s.force_update_all_bone_transforms()
    for semantic in POSE_BONES:
        max_error=max(max_error,s.get_bone_global_pose(int(m[semantic])).origin.distance_to(_frame_pose(f,semantic).origin))
    return max_error

func _capture(path:String)->bool:
    await process_frame
    await RenderingServer.frame_post_draw
    var image:=root.get_texture().get_image()
    return image!=null and image.get_width()==WIDTH and image.get_height()==HEIGHT and image.save_png(path)==OK

func _write_json(path:String,data:Dictionary)->bool:
    var f:=FileAccess.open(path,FileAccess.WRITE)
    if f==null:return false
    f.store_string(JSON.stringify(data,"  "))
    f.close()
    return true

func _run()->void:
    var bundle=_read_json(_bundle_path)
    if not bundle is Dictionary or bundle.get("schema","")!="grand-bruxelles-civ1-skeleton-witness-bundle-v1":
        push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: bundle"); quit(3); return
    for forbidden in ["runtime_authorized","visual_approval_claimed","player_view_claimed"]:
        if bool(bundle.get(forbidden,true)):
            push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: upstream_claim"); quit(4); return
    var frames:Array=bundle.get("frames",[])
    if frames.size()!=120:
        push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: frames"); quit(5); return
    var body_scene:=load(BODY_PATH) as PackedScene
    var main_scene:=load(MAIN_SCENE_PATH) as PackedScene
    if body_scene==null or main_scene==null:
        push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: assets"); quit(6); return
    var canonical_main:=main_scene.instantiate()
    var canonical_ground:=canonical_main.get_node_or_null(MAIN_GROUND_PATH) as CSGBox3D
    if canonical_ground==null or not canonical_ground.use_collision or canonical_ground.rotation.length()>1e-8:
        push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: canonical_ground"); canonical_main.free(); quit(7); return
    var ground_top_y:=canonical_ground.position.y+canonical_ground.size.y*0.5
    var ground_copy:=canonical_ground.duplicate() as CSGBox3D
    canonical_main.free()
    ground_copy.name="CanonicalMainGround"
    var world:=Node3D.new(); root.add_child(world); world.add_child(ground_copy)
    var body:=body_scene.instantiate(); world.add_child(body)
    var skeleton:=_find_skeleton(body)
    if skeleton==null:
        push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: skeleton"); quit(8); return
    var mapping:={}
    for semantic in POSE_BONES:
        var idx:=_bone_index(skeleton,semantic)
        if idx<0:
            push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: bone "+semantic); quit(9); return
        mapping[semantic]=idx
    var integrity:={"mesh_instance_count":0,"surface_count":0,"skinned_mesh_count":0,"skin_bind_count":0,"same_skeleton_skin_count":0}
    _collect_mesh_integrity(body,skeleton,integrity)
    if int(integrity["mesh_instance_count"])<1 or int(integrity["surface_count"])<1 or int(integrity["skinned_mesh_count"])<1 or int(integrity["skin_bind_count"])<1 or int(integrity["same_skeleton_skin_count"])<1:
        push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: skin_integrity "+JSON.stringify(integrity)); quit(10); return
    var bilateral_floor_y:=INF
    for frame in frames:
        bilateral_floor_y=min(bilateral_floor_y,_frame_pose(frame,"LeftFoot").origin.y,_frame_pose(frame,"RightFoot").origin.y)
    if not is_finite(bilateral_floor_y):
        push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: placement"); quit(11); return
    var placement_y:=ground_top_y-bilateral_floor_y
    body.position.y=placement_y
    var marker:=MeshInstance3D.new()
    marker.name="DiagnosticLeftFootLandmark"
    var marker_mesh:=SphereMesh.new(); marker_mesh.radius=MARKER_RADIUS_M; marker_mesh.height=MARKER_RADIUS_M*2.0
    marker.mesh=marker_mesh
    var marker_mat:=StandardMaterial3D.new(); marker_mat.albedo_color=MARKER_COLOR; marker_mat.emission_enabled=true; marker_mat.emission=MARKER_COLOR; marker_mat.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
    marker.material_override=marker_mat
    world.add_child(marker)
    var camera:=Camera3D.new(); camera.fov=VERTICAL_FOV_DEG; world.add_child(camera); camera.current=true
    var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-35,-25,0); key.light_energy=1.5; world.add_child(key)
    root.size=Vector2i(WIDTH,HEIGHT)
    DirAccess.make_dir_recursive_absolute(_capture_dir)
    var max_pose_error:=0.0
    var captures:Array=[]
    for sample_index in TARGET_SAMPLES:
        max_pose_error=max(max_pose_error,_apply_frame(skeleton,mapping,frames[sample_index]))
        var left_local:=skeleton.get_bone_global_pose(int(mapping["LeftFoot"])).origin
        var left_world:=skeleton.to_global(left_local)
        marker.global_position=left_world
        await process_frame
        for distance_m in PLAYER_DISTANCES_M:
            camera.position=Vector3(float(distance_m),0.23+placement_y,0.0)
            camera.look_at(Vector3(0.0,0.16+placement_y,0.0))
            var screen:=camera.unproject_position(left_world)
            var distance_tag:=str(int(distance_m))
            var png:=_capture_dir.path_join("civ1-leftfoot-landmark-%sm-%03d.png"%[distance_tag,sample_index])
            if not await _capture(png):
                push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: capture"); quit(12); return
            captures.append({"sample_index":sample_index,"distance_m":distance_m,"png":png,"expected_screen_xy_px":[screen.x,screen.y],"leftfoot_world":[left_world.x,left_world.y,left_world.z]})
    var report={
        "schema":"grand-bruxelles-civ1-leftfoot-landmark-witness-v1",
        "diagnostic_only":true,
        "landmark_semantic":"leftfoot_bone_pose_with_verified_same_skeleton_skin",
        "marker_color_rgb":[255,0,255],
        "marker_radius_m":MARKER_RADIUS_M,
        "source_scene":MAIN_SCENE_PATH,
        "source_ground_node":String(MAIN_GROUND_PATH),
        "resolution":[WIDTH,HEIGHT],
        "vertical_fov_deg":VERTICAL_FOV_DEG,
        "player_distances_m":PLAYER_DISTANCES_M,
        "sample_indices":TARGET_SAMPLES,
        "capture_count":captures.size(),
        "captures":captures,
        "max_pose_origin_error_m":max_pose_error,
        "skeleton_bone_count":skeleton.get_bone_count(),
        "leftfoot_bone_name":skeleton.get_bone_name(int(mapping["LeftFoot"])),
        "skin_integrity":integrity,
        "perceptual_2_8m_claimed":false,
        "planted_contact_claimed":false,
        "animation_correction_authorized":false,
        "runtime_authorized":false,
        "visual_approval_claimed":false,
        "player_view_claimed":false,
        "verdict":"AMELIORER_LEFTFOOT_LANDMARK_RASTERS_CAPTURED_NO_PROMOTION"
    }
    if max_pose_error>0.0001:
        report["verdict"]="JETER_LEFTFOOT_LANDMARK_POSE_DRIFT"
    if not _write_json(_report_path,report):
        push_error("CIV1_LEFTFOOT_LANDMARK_FAIL: report"); quit(13); return
    print("CIV1_LEFTFOOT_LANDMARK_OK captures=%d pose=%.9f skin=%s"%[captures.size(),max_pose_error,JSON.stringify(integrity)])
    quit(0 if report["verdict"]!="JETER_LEFTFOOT_LANDMARK_POSE_DRIFT" else 14)
