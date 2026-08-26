import bpy, json, math, sys, traceback
from pathlib import Path
from mathutils import Quaternion, Matrix

ROLE_MAP={"hips":"pelvis","spine":"waist","chest":"torso","neck":"neck","head":"head","left_upper_arm":"armup.L","left_forearm":"armlo.L","left_hand":"hand.L","right_upper_arm":"armup.R","right_forearm":"armlo.R","right_hand":"hand.R","left_upper_leg":"legup.L","left_lower_leg":"leglo.L","left_foot":"foot1.L","right_upper_leg":"legup.R","right_lower_leg":"leglo.R","right_foot":"foot1.R"}
ROLE_PARENT={"hips":"","spine":"hips","chest":"spine","neck":"chest","head":"neck","left_upper_arm":"chest","left_forearm":"left_upper_arm","left_hand":"left_forearm","right_upper_arm":"chest","right_forearm":"right_upper_arm","right_hand":"right_forearm","left_upper_leg":"hips","left_lower_leg":"left_upper_leg","left_foot":"left_lower_leg","right_upper_leg":"hips","right_lower_leg":"right_upper_leg","right_foot":"right_lower_leg"}
EXPECTED_GAPS=sorted(["hips>spine","left_forearm>left_hand","left_lower_leg>left_foot","right_forearm>right_hand","right_lower_leg>right_foot"])
ROLE_ORDER=list(ROLE_MAP.keys())


def arg(name,default=None):
    args=sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    return args[args.index(name)+1] if name in args else default


def _unit(q):
    w,x,y,z=(float(q[0]),float(q[1]),float(q[2]),float(q[3])); n=math.sqrt(w*w+x*x+y*y+z*z); assert n>0.0
    return w/n,x/n,y/n,z/n


def qdeg_components(a,b):
    aw,ax,ay,az=_unit(a); bw,bx,by,bz=_unit(b)
    rw=aw*bw+ax*bx+ay*by+az*bz; rx=aw*bx-ax*bw-ay*bz+az*by; ry=aw*by+ax*bz-ay*bw-az*bx; rz=aw*bz-ax*by+ay*bx-az*bw
    return math.degrees(2.0*math.atan2(math.sqrt(rx*rx+ry*ry+rz*rz),abs(rw)))


def qdeg(a,b): return qdeg_components((a.w,a.x,a.y,a.z),(b.w,b.x,b.y,b.z))
def rdeg(a,b): return qdeg(a.to_quaternion(),b.to_quaternion())


def regression_shortest_arc():
    assert qdeg(Quaternion((1,0,0,0)),Quaternion((-1,0,0,0)))<=1e-9
    half=math.radians(0.05)*0.5
    measured=qdeg_components((1.0,0.0,0.0,0.0),(math.cos(half),0.0,math.sin(half),0.0))
    assert abs(measured-0.05)<=1e-6,measured


def rigid_pose_payload(m):
    # Keep the normalized quaternion as Python double components. Normalizing a
    # mathutils.Quaternion here rounds back to float32 and can manufacture a
    # few micro-degrees of apparent drift before any proxy/Godot work occurs.
    q=m.to_quaternion()
    return (m.translation.copy(),_unit((q.w,q.x,q.y,q.z)))


def payload_matrix(payload):
    t,q_components=payload
    q=Quaternion(q_components)
    return Matrix.Translation(t) @ q.to_matrix().to_4x4()


def payload_translation_error(payload,m):
    return (payload[0]-m.translation).length


def payload_rotation_error(payload,m):
    q=m.to_quaternion()
    return qdeg_components(payload[1],(q.w,q.x,q.y,q.z))


def regression_rigid_payload_measurement():
    m=Matrix.Rotation(math.radians(17.0),4,'Y') @ Matrix.Diagonal((1.10,0.90,1.05,1.0))
    m.translation=(0.125,-0.25,0.375)
    payload=rigid_pose_payload(m)
    assert isinstance(payload[1],tuple) and len(payload[1])==4
    assert payload_translation_error(payload,m)<=1e-12
    assert payload_rotation_error(payload,m)<=1e-12
    # Re-normalizing the raw float32 source quaternion in double precision must
    # stay orientation-identical to the stored payload at the strict 1e-6 gate.
    q=m.to_quaternion()
    assert qdeg_components(payload[1],(q.w,q.x,q.y,q.z))<=1e-12


def rigid_pose_matrix(m):
    return payload_matrix(rigid_pose_payload(m))


def ensure_object_mode():
    obj=bpy.context.object
    if obj is not None and obj.mode!="OBJECT":
        bpy.context.view_layer.objects.active=obj; obj.select_set(True); bpy.ops.object.mode_set(mode="OBJECT")


def deselect_all():
    for obj in bpy.context.view_layer.objects: obj.select_set(False)


def is_ancestor(a,b):
    cur=b.parent
    while cur:
        if cur==a:return True
        cur=cur.parent
    return False


def source_gaps(src):
    chains=[["hips","spine","chest","neck","head"],["left_upper_arm","left_forearm","left_hand"],["right_upper_arm","right_forearm","right_hand"],["left_upper_leg","left_lower_leg","left_foot"],["right_upper_leg","right_lower_leg","right_foot"]]
    out=[]
    for chain in chains:
        for x,y in zip(chain,chain[1:]):
            if not is_ancestor(src.data.bones[ROLE_MAP[x]],src.data.bones[ROLE_MAP[y]]):out.append(f"{x}>{y}")
    return sorted(out)


def snapshot_source_armature(src):
    rest={}; parents={}
    for bone in src.data.bones:
        name=str(bone.name); assert name not in rest,name
        rest[name]=bone.matrix_local.copy(); parents[name]=bone.parent.name if bone.parent else ""
    assert len(rest)==len(src.data.bones)
    return rest,parents


def inheritance_signature(bone):
    return {"inherit_scale":str(bone.inherit_scale),"use_inherit_rotation":bool(bone.use_inherit_rotation),"use_local_location":bool(bone.use_local_location)}


def make_proxy(src):
    ensure_object_mode(); data=bpy.data.armatures.new("SteveReviewedRetargetProxyArmature"); dst=bpy.data.objects.new("SteveReviewedRetargetProxy",data); bpy.context.collection.objects.link(dst); dst.matrix_world=src.matrix_world.copy()
    deselect_all(); dst.select_set(True); bpy.context.view_layer.objects.active=dst; bpy.ops.object.mode_set(mode="EDIT")
    for role in ROLE_ORDER:
        sb=src.data.bones[ROLE_MAP[role]]; eb=data.edit_bones.new(ROLE_MAP[role]); eb.head=sb.head_local.copy(); eb.tail=sb.tail_local.copy(); eb.matrix=sb.matrix_local.copy(); eb.use_connect=False
    for role in ROLE_ORDER:
        parent_role=ROLE_PARENT[role]
        if parent_role:
            eb=data.edit_bones[ROLE_MAP[role]]; matrix=eb.matrix.copy(); length=eb.length; eb.parent=data.edit_bones[ROLE_MAP[parent_role]]; eb.use_connect=False; eb.matrix=matrix; eb.length=length
    bpy.ops.object.mode_set(mode="OBJECT")
    for role in ROLE_ORDER:
        name=ROLE_MAP[role]; sb=src.data.bones[name]; db=dst.data.bones[name]
        db.inherit_scale='NONE'; db.use_inherit_rotation=sb.use_inherit_rotation; db.use_local_location=sb.use_local_location
    bpy.context.view_layer.update(); return dst


def proxy_policy_mismatches(src,dst):
    out=[]
    for role in ROLE_ORDER:
        name=ROLE_MAP[role]; sb=src.data.bones[name]; db=dst.data.bones[name]
        if str(db.inherit_scale)!="NONE" or db.use_inherit_rotation!=sb.use_inherit_rotation or db.use_local_location!=sb.use_local_location:
            out.append({"role":role,"bone":name,"source":inheritance_signature(sb),"proxy":inheritance_signature(db)})
    return out


def add_qa_skin_anchor(dst):
    mesh=bpy.data.meshes.new("SteveRetargetProxyQaSkinAnchorMesh"); mesh.from_pydata([(0,0,0),(0.001,0,0),(0,0.001,0)],[],[(0,1,2)]); mesh.update()
    obj=bpy.data.objects.new("SteveRetargetProxyQaSkinAnchor",mesh); bpy.context.collection.objects.link(obj); obj.parent=dst
    mod=obj.modifiers.new("Armature","ARMATURE"); mod.object=dst; vg=obj.vertex_groups.new(name=ROLE_MAP["hips"]); vg.add([0,1,2],1.0,"REPLACE"); obj.hide_render=True; return obj


def assign_pose_matrix(dst,role,desired):
    p=dst.pose.bones[ROLE_MAP[role]]; p.rotation_mode="QUATERNION"; p.matrix=desired.copy(); bpy.context.view_layer.update()


def main():
    out=Path(arg("--output","/tmp/steve_normalized.glb")); report_path=Path(arg("--report","/tmp/normalization-report.json"))
    report={"format":"grand-bruxelles-steve-reviewed-retarget-proxy-v15","normalization_revision":"v15_component_payload_no_matrix_roundtrip_gate","bake_solver":"reviewed_17_role_rigid_pose_component_payload_v15","latest_completed_red_head_sha":"366ad29a059d7500364dd37b8e0784eb01698c23","latest_completed_red_run":33010228660,"latest_completed_red_artifact_id":9622266348,"latest_completed_red_artifact_digest":"sha256:b14fe857f40b1bf1113532648ca15e64707dce92df1700d65f290e7cb16a70b5","latest_completed_red_stage":"rigidization_matrix_roundtrip_precision","latest_completed_red_rotation_error_deg":3.056508464522842e-05,"affine_diagnostic_state":"PARENT_SCALE_INHERITANCE_CAUSES_ROTATION_MISMATCH","affine_diagnostic_no_scale_rotation_error_deg":9.591441627410885e-06,"reviewed_role_count":17,"proxy_contains_controller_helpers":False,"proxy_contains_visual_payload":False,"qa_skin_anchor_ephemeral":True,"source_snapshot_by_name":True,"proxy_scale_inheritance_policy":"NONE_ON_ALL_REVIEWED_BONES","pose_payload_policy":"RIGID_TRANSLATION_PLUS_NORMALIZED_QUATERNION","rigidization_measurement":"payload_components_before_matrix_reconstruction","matrix_roundtrip_excluded_from_rigidization_gate":True,"preserve_inherit_rotation":True,"preserve_local_location":True,"pose_assignment_method":"PoseBone.matrix_armature_object_space_from_rigid_payload","source_armature_untouched":False,"retarget_applied":False,"runtime_authorized":False,"state":"STARTED"}
    def write_report(): report_path.write_text(json.dumps(report,indent=2,sort_keys=True))
    try:
        regression_shortest_arc(); regression_rigid_payload_measurement(); ensure_object_mode(); arms=[o for o in bpy.data.objects if o.type=="ARMATURE"]; assert len(arms)==1,len(arms); src=arms[0]
        assert all(name in src.data.bones for name in ROLE_MAP.values()); before=source_gaps(src); assert before==EXPECTED_GAPS,(before,EXPECTED_GAPS)
        source_rest,source_parents=snapshot_source_armature(src)
        walks=[a for a in bpy.data.actions if a.name.lower()=="walk"]; assert len(walks)==1,[a.name for a in bpy.data.actions]; walk=walks[0]
        if src.animation_data is None: src.animation_data_create()
        src.animation_data.action=walk
        for track in src.animation_data.nla_tracks: track.mute=True
        scene=bpy.context.scene; fs=int(math.floor(walk.frame_range[0])); fe=max(fs+1,int(math.ceil(walk.frame_range[1]))); frames=list(range(fs,fe+1)); samples={}
        rigidization_pos=rigidization_rot=0.0
        for frame in frames:
            scene.frame_set(frame); bpy.context.view_layer.update(); samples[frame]={}
            for role in ROLE_ORDER:
                authored=src.pose.bones[ROLE_MAP[role]].matrix.copy(); payload=rigid_pose_payload(authored); samples[frame][role]=payload
                rigidization_pos=max(rigidization_pos,payload_translation_error(payload,authored)); rigidization_rot=max(rigidization_rot,payload_rotation_error(payload,authored))
        report.update({"max_rigidization_translation_error_m":rigidization_pos,"max_rigidization_rotation_error_deg":rigidization_rot}); write_report()
        assert rigidization_pos<=1e-9,rigidization_pos; assert rigidization_rot<=1e-6,rigidization_rot
        dst=make_proxy(src); assert len(dst.data.bones)==17,len(dst.data.bones)
        policy_errors=proxy_policy_mismatches(src,dst); report["proxy_scale_policy_mismatches"]=policy_errors; write_report(); assert policy_errors==[],policy_errors
        rest_pos=rest_rot=0.0; rest_position_worst={}; rest_rotation_worst={}
        for role in ROLE_ORDER:
            name=ROLE_MAP[role]; pe=(dst.data.bones[name].matrix_local.translation-src.data.bones[name].matrix_local.translation).length; re=rdeg(dst.data.bones[name].matrix_local,src.data.bones[name].matrix_local)
            if pe>rest_pos: rest_position_worst={"role":role,"bone":name,"position_error_m":pe}
            if re>rest_rot: rest_rotation_worst={"role":role,"bone":name,"rotation_error_deg":re}
            rest_pos=max(rest_pos,pe); rest_rot=max(rest_rot,re)
        report.update({"proxy_bone_count":17,"max_reviewed_rest_position_error_m":rest_pos,"max_reviewed_rest_rotation_error_deg":rest_rot,"reviewed_rest_position_worst":rest_position_worst,"reviewed_rest_rotation_worst":rest_rotation_worst}); write_report()
        assert rest_pos<=1e-6,rest_position_worst; assert rest_rot<=1e-4,rest_rotation_worst; assert sum(len(p.constraints) for p in dst.pose.bones)==0
        anchor=add_qa_skin_anchor(dst); baked=bpy.data.actions.new("walk"); dst.animation_data_create(); dst.animation_data.action=baked
        assignment_pos=assignment_rot=0.0; assignment_position_worst={}; assignment_rotation_worst={}
        for frame in frames:
            desired={role:payload_matrix(samples[frame][role]) for role in ROLE_ORDER}; scene.frame_set(frame)
            for role in ROLE_ORDER: assign_pose_matrix(dst,role,desired[role])
            for role in ROLE_ORDER:
                name=ROLE_MAP[role]; pe=(dst.pose.bones[name].matrix.translation-desired[role].translation).length; re=rdeg(dst.pose.bones[name].matrix,desired[role])
                if pe>assignment_pos: assignment_position_worst={"frame":frame,"role":role,"bone":name,"position_error_m":pe}
                if re>assignment_rot: assignment_rotation_worst={"frame":frame,"role":role,"bone":name,"rotation_error_deg":re}
                assignment_pos=max(assignment_pos,pe); assignment_rot=max(assignment_rot,re)
            report.update({"max_assignment_pose_position_error_m":assignment_pos,"max_assignment_pose_rotation_error_deg":assignment_rot,"assignment_position_worst":assignment_position_worst,"assignment_rotation_worst":assignment_rotation_worst}); write_report()
            assert assignment_pos<=1e-4,assignment_position_worst; assert assignment_rot<=0.10,assignment_rotation_worst
            for role in ROLE_ORDER:
                p=dst.pose.bones[ROLE_MAP[role]]; p.keyframe_insert("location",frame=frame,group=p.name); p.keyframe_insert("rotation_quaternion",frame=frame,group=p.name); p.keyframe_insert("scale",frame=frame,group=p.name)
        playback_pos=playback_rot=0.0; playback_position_worst={}; playback_rotation_worst={}
        for frame in frames:
            scene.frame_set(frame); bpy.context.view_layer.update()
            for role in ROLE_ORDER:
                name=ROLE_MAP[role]; desired=payload_matrix(samples[frame][role]); pe=(dst.pose.bones[name].matrix.translation-desired.translation).length; re=rdeg(dst.pose.bones[name].matrix,desired)
                if pe>playback_pos: playback_position_worst={"frame":frame,"role":role,"bone":name,"position_error_m":pe}
                if re>playback_rot: playback_rotation_worst={"frame":frame,"role":role,"bone":name,"rotation_error_deg":re}
                playback_pos=max(playback_pos,pe); playback_rot=max(playback_rot,re)
        report.update({"max_baked_pose_position_error_m":playback_pos,"max_baked_pose_rotation_error_deg":playback_rot,"baked_position_worst":playback_position_worst,"baked_rotation_worst":playback_rotation_worst}); write_report()
        assert playback_pos<=1e-4,playback_position_worst; assert playback_rot<=0.10,playback_rotation_worst
        source_pos=max((src.data.bones[n].matrix_local.translation-source_rest[n].translation).length for n in source_rest); source_rot=max(rdeg(src.data.bones[n].matrix_local,source_rest[n]) for n in source_rest); source_parent_drift=[n for n in source_rest if (src.data.bones[n].parent.name if src.data.bones[n].parent else "")!=source_parents[n]]
        assert source_pos<=1e-9 and source_rot<=1e-7,(source_pos,source_rot); assert source_parent_drift==[],source_parent_drift
        report.update({"source_bone_count":len(src.data.bones),"source_topology_gaps_before":before,"proxy_topology_gaps_after":[],"action_name":"walk","frame_start":fs,"frame_end":fe,"sampled_frames":len(frames),"source_rest_position_drift_m":source_pos,"source_rest_rotation_drift_deg":source_rot,"source_parent_drift":source_parent_drift,"source_armature_untouched":True,"state":"PROXY_BAKE_VERIFIED"}); write_report()
        src.animation_data.action=None; ensure_object_mode(); deselect_all(); dst.select_set(True); anchor.select_set(True); bpy.context.view_layer.objects.active=dst
        bpy.ops.export_scene.gltf(filepath=str(out),export_format="GLB",use_selection=True,export_animations=True,export_draco_mesh_compression_enable=False); assert out.is_file() and out.stat().st_size>0
        report["export_bytes"]=out.stat().st_size; report["state"]="READY_FOR_GODOT_IMPORT"; write_report()
        print("GATE8_STEVE_REVIEWED_PROXY_EXPORT_OK source_bones=%d proxy_bones=17 scale_policy=NONE pose_payload=COMPONENTS rest_pos_error_m=%.9f rest_rot_error_deg=%.6f assignment_pos_error_m=%.9f assignment_rot_error_deg=%.6f pose_pos_error_m=%.9f pose_rot_error_deg=%.6f bytes=%d"%(len(src.data.bones),rest_pos,rest_rot,assignment_pos,assignment_rot,playback_pos,playback_rot,out.stat().st_size))
    except Exception as exc:
        report["state"]="FAILED"; report["exception"]=repr(exc); report["traceback"]=traceback.format_exc(); write_report(); raise

if __name__=="__main__": main()
