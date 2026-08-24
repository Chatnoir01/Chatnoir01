extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const CLIP := "Jog_Fwd"
const SAMPLE_FRACTION := 0.35
const CAPTURE_SIZE := Vector2i(1280, 720)
const CAMERA_DISTANCE_M := 2.5
const CAMERA_EYE_HEIGHT_M := 1.62
const CAMERA_FOV_DEGREES := 68.0
const SETTLE_FRAMES := 2
const MIN_MOVING_VARIANT_PEAK_DELTA_DEG := 2.0

const ROLE_PAIRS := {
    "hips": ["DEF-hips", "pelvis"],
    "spine": ["DEF-spine.001", "spine_01"],
    "chest": ["DEF-spine.002", "spine_02"],
    "upper_chest": ["DEF-spine.003", "spine_03"],
    "neck": ["DEF-neck", "neck_01"],
    "head": ["DEF-head", "head"],
    "left_shoulder": ["DEF-shoulder.L", "clavicle_l"],
    "left_upper_arm": ["DEF-upper_arm.L", "upperarm_l"],
    "left_forearm": ["DEF-forearm.L", "lowerarm_l"],
    "left_hand": ["DEF-hand.L", "hand_l"],
    "right_shoulder": ["DEF-shoulder.R", "clavicle_r"],
    "right_upper_arm": ["DEF-upper_arm.R", "upperarm_r"],
    "right_forearm": ["DEF-forearm.R", "lowerarm_r"],
    "right_hand": ["DEF-hand.R", "hand_r"],
    "left_upper_leg": ["DEF-thigh.L", "thigh_l"],
    "left_lower_leg": ["DEF-shin.L", "calf_l"],
    "left_foot": ["DEF-foot.L", "foot_l"],
    "left_toe": ["DEF-toe.L", "ball_l"],
    "right_upper_leg": ["DEF-thigh.R", "thigh_r"],
    "right_lower_leg": ["DEF-shin.R", "calf_r"],
    "right_foot": ["DEF-foot.R", "foot_r"],
    "right_toe": ["DEF-toe.R", "ball_r"],
}
const ROLE_ORDER: Array[String] = [
    "hips", "spine", "chest", "upper_chest", "neck", "head",
    "left_shoulder", "left_upper_arm", "left_forearm", "left_hand",
    "right_shoulder", "right_upper_arm", "right_forearm", "right_hand",
    "left_upper_leg", "left_lower_leg", "left_foot", "left_toe",
    "right_upper_leg", "right_lower_leg", "right_foot", "right_toe",
]
const TORSO: Array[String] = ["hips", "spine", "chest", "upper_chest", "neck", "head"]
const ARMS: Array[String] = ["left_shoulder", "left_upper_arm", "left_forearm", "left_hand", "right_shoulder", "right_upper_arm", "right_forearm", "right_hand"]
const LEGS: Array[String] = ["left_upper_leg", "left_lower_leg", "left_foot", "left_toe", "right_upper_leg", "right_lower_leg", "right_foot", "right_toe"]
const VARIANTS := [
    {"id":"rest", "chains":[]},
    {"id":"torso", "chains":["torso"]},
    {"id":"legs", "chains":["legs"]},
    {"id":"arms", "chains":["arms"]},
    {"id":"torso-legs", "chains":["torso", "legs"]},
    {"id":"torso-arms", "chains":["torso", "arms"]},
    {"id":"all", "chains":["torso", "arms", "legs"]},
]

var _failures: Array[String] = []
var _source_scene: Node3D
var _target_scene: Node3D
var _source: Skeleton3D
var _target: Skeleton3D
var _player: AnimationPlayer
var _source_indices: Dictionary = {}
var _target_indices: Dictionary = {}
var _viewport: SubViewport
var _world_root: Node3D
var _camera: Camera3D

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    _source_scene = _instantiate(SOURCE_SCENE)
    _target_scene = _instantiate(TARGET_SCENE)
    if _source_scene == null or _target_scene == null:
        _finish({})
        return
    root.add_child(_source_scene)
    _source_scene.visible = false
    _build_viewport()
    _world_root.add_child(_target_scene)
    await _settle()
    _source = _find_skeleton(_source_scene)
    _target = _find_skeleton(_target_scene)
    _player = _find_player(_source_scene)
    if _source == null or _target == null or _player == null:
        _failures.append("required_source_target_or_player_missing")
        _finish({})
        return
    if not _cache_indices():
        _finish({})
        return
    var integrity := _target_integrity(_target_scene)
    if int(integrity["skinned_meshes"]) <= 0 or int(integrity["missing_material_surfaces"]) != 0:
        _failures.append("target_skin_integrity_failed")

    var animation_name := _resolve_animation_name(_player, CLIP)
    if animation_name.is_empty():
        _failures.append("clip_missing=%s" % CLIP)
        _finish({})
        return
    var animation := _player.get_animation(animation_name)
    if animation == null or animation.length <= 0.0:
        _failures.append("clip_invalid")
        _finish({})
        return
    var sample_time := animation.length * SAMPLE_FRACTION
    _player.play(animation_name)
    _player.seek(sample_time, true)
    _player.advance(0.0)
    _source.force_update_all_bone_transforms()

    var output_dir := OS.get_environment("GATE8_CHAIN_ABLATION_DIR")
    if output_dir.is_empty(): output_dir = "user://gate8_chain_ablation"
    var mkdir_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_dir))
    if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
        _failures.append("output_dir_failed=%s" % error_string(mkdir_error))
        _finish({})
        return

    var rows := {}
    var capture_count := 0
    for raw_variant in VARIANTS:
        var variant: Dictionary = raw_variant
        var variant_id := String(variant["id"])
        var active_roles := _roles_for_chains(variant["chains"])
        _target_scene.position = Vector3.ZERO
        _target.reset_bone_poses()
        _target.force_update_all_bone_transforms()
        _apply_global_motion_roles(active_roles)
        var peak_delta := _peak_target_global_delta_deg(active_roles)
        if variant_id == "rest":
            if peak_delta > 0.01:
                _failures.append("rest_variant_motion_deg=%.5f" % peak_delta)
        elif peak_delta < MIN_MOVING_VARIANT_PEAK_DELTA_DEG:
            _failures.append("variant_motion_too_small id=%s peak_deg=%.3f" % [variant_id, peak_delta])
        var correction := _ground_target()
        var frame := await _capture_frame(variant_id, output_dir)
        if not frame.is_empty(): capture_count += 1
        rows[variant_id] = {
            "chains": variant["chains"],
            "active_roles": active_roles,
            "active_role_count": active_roles.size(),
            "peak_target_global_delta_deg": peak_delta,
            "grounding_correction_m": correction,
            "frame": frame,
        }

    _player.stop()
    if capture_count != VARIANTS.size():
        _failures.append("capture_count=%d expected=%d" % [capture_count, VARIANTS.size()])
    var result := {
        "format":"grand-bruxelles-gate8-variant01-chain-ablation-v1",
        "engine_version":Engine.get_version_info().get("string", "unknown"),
        "candidate_variant":1,
        "clip":CLIP,
        "sample_fraction":SAMPLE_FRACTION,
        "sample_time_s":sample_time,
        "reviewed_roles":ROLE_PAIRS.size(),
        "solver":"source_global_pose_times_source_global_rest_inverse_then_target_global_rest",
        "variants":rows,
        "capture_count":capture_count,
        "capture_size":[CAPTURE_SIZE.x, CAPTURE_SIZE.y],
        "target_integrity":integrity,
        "purpose":"visual_chain_ablation_only",
        "run_alias_selected":"",
        "production_authorized":false,
        "activation_ready":false,
        "adoption_ready":false,
        "runtime_population_changed":false,
        "visual_approval_claimed":false,
        "selection_state":"CHAIN_ABLATION_REVIEW_REQUIRED" if _failures.is_empty() else "BLOCKED_CHAIN_ABLATION",
        "failures":_failures,
    }
    _write_result(result)
    print("GATE8_CHAIN_ABLATION captures=%d variants=%d alias_selected=false production_authorized=false" % [capture_count, VARIANTS.size()])
    _finish(result)

func _roles_for_chains(chains: Array) -> Array[String]:
    var out: Array[String] = []
    for chain_value in chains:
        var chain := String(chain_value)
        var source_roles: Array[String] = []
        if chain == "torso": source_roles = TORSO
        elif chain == "arms": source_roles = ARMS
        elif chain == "legs": source_roles = LEGS
        for role in source_roles:
            if not out.has(role): out.append(role)
    return out

func _apply_global_motion_roles(active_roles: Array[String]) -> void:
    var source_node_basis := _source.global_transform.basis.orthonormalized()
    var target_node_basis := _target.global_transform.basis.orthonormalized()
    var target_node_basis_inverse := target_node_basis.inverse()
    for role in ROLE_ORDER:
        if not active_roles.has(role): continue
        var source_idx: int = _source_indices[role]
        var target_idx: int = _target_indices[role]
        var source_world_rest_basis := (source_node_basis * _source.get_bone_global_rest(source_idx).basis).orthonormalized()
        var source_world_pose_basis := (source_node_basis * _source.get_bone_global_pose(source_idx).basis).orthonormalized()
        var motion_world_basis := (source_world_pose_basis * source_world_rest_basis.inverse()).orthonormalized()
        var target_world_rest_basis := (target_node_basis * _target.get_bone_global_rest(target_idx).basis).orthonormalized()
        var desired_target_skeleton_basis := (target_node_basis_inverse * motion_world_basis * target_world_rest_basis).orthonormalized()
        var current_target_global := _target.get_bone_global_pose(target_idx)
        _target.set_bone_global_pose(target_idx, Transform3D(desired_target_skeleton_basis, current_target_global.origin))
        _target.force_update_all_bone_transforms()

func _peak_target_global_delta_deg(active_roles: Array[String]) -> float:
    var peak := 0.0
    for role in active_roles:
        var idx: int = _target_indices[role]
        var rest_q := _target.get_bone_global_rest(idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        var pose_q := _target.get_bone_global_pose(idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        peak = maxf(peak, rad_to_deg(rest_q.angle_to(pose_q)))
    return peak

func _ground_target() -> float:
    _target_scene.position = Vector3.ZERO
    _target.force_update_all_bone_transforms()
    var left_y := _target.to_global(_target.get_bone_global_pose(int(_target_indices["left_foot"])).origin).y
    var right_y := _target.to_global(_target.get_bone_global_pose(int(_target_indices["right_foot"])).origin).y
    var correction := -minf(left_y, right_y)
    _target_scene.position.y += correction
    _target.force_update_all_bone_transforms()
    return correction

func _capture_frame(variant_id: String, output_dir: String) -> String:
    _target_scene.position.z = -CAMERA_DISTANCE_M
    await _settle()
    var head_world := _target.to_global(_target.get_bone_global_pose(int(_target_indices["head"])).origin)
    var left_world := _target.to_global(_target.get_bone_global_pose(int(_target_indices["left_foot"])).origin)
    var right_world := _target.to_global(_target.get_bone_global_pose(int(_target_indices["right_foot"])).origin)
    var look_target := (head_world + (left_world + right_world) * 0.5) * 0.5
    _camera.position = Vector3(0.0, CAMERA_EYE_HEIGHT_M, 0.0)
    _camera.look_at(look_target, Vector3.UP)
    await _settle()
    await RenderingServer.frame_post_draw
    var image := _viewport.get_texture().get_image()
    if image == null or image.is_empty() or image.get_size() != CAPTURE_SIZE:
        _failures.append("capture_invalid=%s" % variant_id)
        return ""
    var output_path := output_dir.path_join("gate8-variant01-chain-ablation-%s.png" % variant_id)
    var err := image.save_png(output_path)
    if err != OK:
        _failures.append("capture_save_failed=%s error=%s" % [variant_id, error_string(err)])
        return ""
    print("GATE8_CHAIN_ABLATION_FRAME_OK variant=%s size=1280x720 screenshot=%s" % [variant_id, output_path])
    return output_path

func _cache_indices() -> bool:
    for role in ROLE_PAIRS:
        var source_idx := _source.find_bone(String(ROLE_PAIRS[role][0]))
        var target_idx := _target.find_bone(String(ROLE_PAIRS[role][1]))
        if source_idx < 0 or target_idx < 0: _failures.append("role_index_missing=%s" % role)
        else: _source_indices[role]=source_idx; _target_indices[role]=target_idx
    return _source_indices.size()==ROLE_PAIRS.size() and _target_indices.size()==ROLE_PAIRS.size()

func _target_integrity(node: Node) -> Dictionary:
    var skinned_meshes:=0; var skinned_surfaces:=0; var materials:=0; var missing_material_surfaces:=0
    for raw in node.find_children("*","MeshInstance3D",true,false):
        var mesh_instance:=raw as MeshInstance3D
        if mesh_instance==null or mesh_instance.mesh==null: continue
        if mesh_instance.skin!=null or not mesh_instance.skeleton.is_empty():
            skinned_meshes+=1
            for surface in range(mesh_instance.mesh.get_surface_count()):
                skinned_surfaces+=1
                var material:=mesh_instance.get_surface_override_material(surface)
                if material==null: material=mesh_instance.mesh.surface_get_material(surface)
                if material==null: missing_material_surfaces+=1
                else: materials+=1
    return {"skinned_meshes":skinned_meshes,"skinned_surfaces":skinned_surfaces,"materials":materials,"missing_material_surfaces":missing_material_surfaces}

func _build_viewport() -> void:
    _viewport=SubViewport.new(); _viewport.size=CAPTURE_SIZE; _viewport.own_world_3d=true; _viewport.transparent_bg=false; _viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS; root.add_child(_viewport)
    _world_root=Node3D.new(); _viewport.add_child(_world_root)
    var env_node:=WorldEnvironment.new(); var env:=Environment.new(); env.background_mode=Environment.BG_COLOR; env.background_color=Color(0.08,0.10,0.14,1.0); env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.ambient_light_color=Color(0.72,0.75,0.82,1.0); env.ambient_light_energy=0.8; env_node.environment=env; _world_root.add_child(env_node)
    var key:=DirectionalLight3D.new(); key.rotation_degrees=Vector3(-48.0,-24.0,0.0); key.light_energy=1.4; key.shadow_enabled=true; _world_root.add_child(key)
    var fill:=DirectionalLight3D.new(); fill.rotation_degrees=Vector3(-25.0,155.0,0.0); fill.light_energy=0.55; _world_root.add_child(fill)
    var floor:=MeshInstance3D.new(); var floor_mesh:=PlaneMesh.new(); floor_mesh.size=Vector2(14.0,14.0); var mat:=StandardMaterial3D.new(); mat.albedo_color=Color(0.24,0.26,0.29,1.0); mat.roughness=0.96; floor_mesh.material=mat; floor.mesh=floor_mesh; floor.position=Vector3(0.0,-0.005,-3.0); _world_root.add_child(floor)
    _camera=Camera3D.new(); _camera.position=Vector3(0.0,CAMERA_EYE_HEIGHT_M,0.0); _camera.fov=CAMERA_FOV_DEGREES; _camera.near=0.05; _camera.current=true; _world_root.add_child(_camera)

func _find_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer and not _resolve_animation_name(node as AnimationPlayer, CLIP).is_empty(): return node as AnimationPlayer
    for child in node.get_children():
        var found:=_find_player(child)
        if found!=null: return found
    return null
func _resolve_animation_name(player: AnimationPlayer, token: String) -> String:
    for name_value in player.get_animation_list():
        var n:=String(name_value)
        if n.split("/")[-1]==token: return n
    return ""
func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D: return node as Skeleton3D
    for child in node.get_children():
        var found:=_find_skeleton(child)
        if found!=null: return found
    return null
func _instantiate(path: String) -> Node3D:
    var packed:=load(path) as PackedScene
    if packed==null: _failures.append("scene_load_failed=%s"%path); return null
    return packed.instantiate() as Node3D
func _settle() -> void:
    for _i in range(SETTLE_FRAMES): await process_frame
func _write_result(result: Dictionary) -> void:
    var f:=FileAccess.open("res://gate8_variant01_chain_ablation_result.json",FileAccess.WRITE)
    if f==null: _failures.append("result_file_open_failed"); return
    f.store_string(JSON.stringify(result,"  ")); f.close()
func _finish(_result: Dictionary) -> void:
    if _failures.is_empty(): print("GATE8_CHAIN_ABLATION_OK review_required=true production_authorized=false"); quit(0); return
    for failure in _failures: push_error("GATE8_CHAIN_ABLATION_FAIL %s"%failure)
    quit(1)
