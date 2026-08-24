extends SceneTree

# Diagnostic only. This deliberately uses Godot's importer-produced BoneMap/
# SkeletonProfileHumanoid normalization instead of another runtime solver.
# The workflow prepares two copies of the same immutable assets:
#   axis_only  = Overwrite Axis, no Fix Silhouette
#   silhouette = Overwrite Axis + Fix Silhouette
# No production asset bytes or population runtime are changed.

const MODES := ["axis_only", "silhouette"]
const CLIPS := ["Jog_Fwd", "Sprint"]
const PROFILE_BONES := [
    "Root", "Hips", "Spine", "Chest", "UpperChest", "Neck", "Head",
    "LeftShoulder", "LeftUpperArm", "LeftLowerArm", "LeftHand",
    "RightShoulder", "RightUpperArm", "RightLowerArm", "RightHand",
    "LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
    "RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes"
]
const SAMPLE_RATE_HZ := 120.0
const MIN_SAMPLES := 80
const EXISTING_GROUND_SPAN_LIMIT_M := 0.18
const GROUND_CLEARANCE_M := 0.02

var _failures: Array[String] = []
var _world: Node3D
var _camera: Camera3D
var _ground: MeshInstance3D

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    root.size = Vector2i(1280, 720)
    _build_world()
    var result := {
        "format": "grand-bruxelles-gate8-variant01-import-normalization-probe-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "normalization_owner": "Godot ResourceImporterScene BoneMap + SkeletonProfileHumanoid",
        "modes": {},
        "selection_state": "MEASURED_REVIEW_REQUIRED",
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "runtime_population_changed": false,
        "failures": _failures
    }

    for mode: String in MODES:
        result["modes"][mode] = await _measure_mode(mode)

    result["failures"] = _failures.duplicate()
    _write_result(result)
    print("GATE8_IMPORT_NORMALIZATION_PROBE modes=%d failures=%d production_authorized=false" % [MODES.size(), _failures.size()])
    if _failures.is_empty():
        print("GATE8_IMPORT_NORMALIZATION_PROBE_OK selection_state=MEASURED_REVIEW_REQUIRED")
        quit(0)
    for failure: String in _failures:
        push_error("GATE8_IMPORT_NORMALIZATION_PROBE_FAIL %s" % failure)
    quit(1)

func _measure_mode(mode: String) -> Dictionary:
    var source_path := "res://assets/%s/animation_source.glb" % mode
    var target_path := "res://assets/%s/npc_gate_01.glb" % mode
    var source_packed := load(source_path) as PackedScene
    var target_packed := load(target_path) as PackedScene
    if source_packed == null or target_packed == null:
        _failures.append("normalized_scene_load_failed mode=%s" % mode)
        return {}

    var source := source_packed.instantiate() as Node3D
    var target := target_packed.instantiate() as Node3D
    if source == null or target == null:
        _failures.append("normalized_scene_instantiate_failed mode=%s" % mode)
        return {}
    _world.add_child(source)
    _world.add_child(target)
    source.visible = false
    await process_frame

    var source_skeleton := _find_skeleton(source)
    var target_skeleton := _find_skeleton(target)
    var source_player := _find_animation_player(source)
    if source_skeleton == null or target_skeleton == null or source_player == null:
        _failures.append("normalized_components_missing mode=%s" % mode)
        source.queue_free()
        target.queue_free()
        await process_frame
        return {}

    var source_inventory := _profile_inventory(source_skeleton)
    var target_inventory := _profile_inventory(target_skeleton)
    if source_inventory.size() < 23 or target_inventory.size() < 23:
        _failures.append("profile_bone_inventory_incomplete mode=%s source=%d target=%d" % [mode, source_inventory.size(), target_inventory.size()])

    var rest_alignment := _rest_alignment(source_skeleton, target_skeleton)
    var rest_bounds := _mesh_world_bounds(target)
    if rest_bounds.size.length() <= 0.001:
        _failures.append("rest_mesh_bounds_empty mode=%s" % mode)

    var rest_capture := await _capture_target(mode, "rest", target, target_skeleton)

    var clips: Dictionary = {}
    for clip: String in CLIPS:
        var animation_name := _resolve_animation_name(source_player, clip)
        if animation_name.is_empty():
            _failures.append("normalized_clip_missing mode=%s clip=%s" % [mode, clip])
            continue
        var source_animation := source_player.get_animation(animation_name)
        if source_animation == null:
            _failures.append("normalized_clip_resource_missing mode=%s clip=%s" % [mode, clip])
            continue
        var animation := source_animation.duplicate(true) as Animation
        clips[clip] = await _measure_clip(mode, clip, animation, target, target_skeleton, rest_bounds)

    source.queue_free()
    target.queue_free()
    await process_frame

    print("GATE8_IMPORT_NORMALIZATION_MODE mode=%s source_profile_bones=%d target_profile_bones=%d rest_rot_mean_deg=%.4f rest_rot_max_deg=%.4f rest_size=(%.3f,%.3f,%.3f)" % [
        mode, source_inventory.size(), target_inventory.size(),
        float(rest_alignment.get("mean_deg", 999.0)), float(rest_alignment.get("max_deg", 999.0)),
        rest_bounds.size.x, rest_bounds.size.y, rest_bounds.size.z
    ])
    return {
        "source_profile_bone_count": source_inventory.size(),
        "target_profile_bone_count": target_inventory.size(),
        "rest_rotation_alignment_mean_deg": rest_alignment.get("mean_deg", 999.0),
        "rest_rotation_alignment_max_deg": rest_alignment.get("max_deg", 999.0),
        "rest_bounds_size": [rest_bounds.size.x, rest_bounds.size.y, rest_bounds.size.z],
        "rest_capture": rest_capture,
        "clips": clips
    }

func _measure_clip(mode: String, clip: String, animation: Animation, target: Node3D, skeleton: Skeleton3D, rest_bounds: AABB) -> Dictionary:
    _reset_skeleton_pose(skeleton)
    var player := AnimationPlayer.new()
    player.name = "ImportedRetargetPlayer"
    target.add_child(player)
    player.root_node = NodePath("..")
    var library := AnimationLibrary.new()
    library.add_animation(StringName(clip), animation)
    player.add_animation_library(&"", library)

    var sample_count := maxi(MIN_SAMPLES, int(ceil(animation.length * SAMPLE_RATE_HZ)))
    var dt := animation.length / float(sample_count)
    var ground_values: Array[float] = []
    var bounds_ratios: Array[float] = []
    var max_bounds_size := Vector3.ZERO
    var finite_samples := 0

    player.play(StringName(clip))
    for sample_idx: int in range(sample_count):
        var t := minf(animation.length - 0.00001, float(sample_idx) * dt)
        player.seek(t, true)
        player.advance(0.0)
        skeleton.force_update_all_bone_transforms()
        var left_idx := skeleton.find_bone("LeftFoot")
        var right_idx := skeleton.find_bone("RightFoot")
        if left_idx < 0 or right_idx < 0:
            _failures.append("normalized_foot_bones_missing mode=%s clip=%s" % [mode, clip])
            break
        var left_y := skeleton.get_bone_global_pose(left_idx).origin.y
        var right_y := skeleton.get_bone_global_pose(right_idx).origin.y
        ground_values.append(minf(left_y, right_y))

        var animated_bounds := _mesh_world_bounds(target)
        max_bounds_size.x = maxf(max_bounds_size.x, animated_bounds.size.x)
        max_bounds_size.y = maxf(max_bounds_size.y, animated_bounds.size.y)
        max_bounds_size.z = maxf(max_bounds_size.z, animated_bounds.size.z)
        var rest_diag := maxf(rest_bounds.size.length(), 0.000001)
        var ratio := animated_bounds.size.length() / rest_diag
        if is_finite(ratio):
            bounds_ratios.append(ratio)
            finite_samples += 1

    var ground_span := _array_max(ground_values) - _array_min(ground_values)
    var max_bounds_ratio := _array_max(bounds_ratios)
    var mean_bounds_ratio := _array_mean(bounds_ratios)
    var passes_existing_ground_gate := ground_span <= EXISTING_GROUND_SPAN_LIMIT_M
    var capture := await _capture_animation(mode, clip, player, animation.length * 0.35, target, skeleton)
    player.stop()
    player.queue_free()
    await process_frame
    _reset_skeleton_pose(skeleton)

    if finite_samples < MIN_SAMPLES:
        _failures.append("normalized_bounds_samples_insufficient mode=%s clip=%s samples=%d" % [mode, clip, finite_samples])
    if not is_finite(ground_span) or not is_finite(max_bounds_ratio):
        _failures.append("normalized_non_finite_metric mode=%s clip=%s" % [mode, clip])

    print("GATE8_IMPORT_NORMALIZED_CLIP mode=%s clip=%s samples=%d ground_span_m=%.4f existing_ground_gate=%s bounds_ratio_mean=%.4f bounds_ratio_max=%.4f max_size=(%.3f,%.3f,%.3f)" % [
        mode, clip, sample_count, ground_span, str(passes_existing_ground_gate), mean_bounds_ratio, max_bounds_ratio,
        max_bounds_size.x, max_bounds_size.y, max_bounds_size.z
    ])
    return {
        "duration_s": animation.length,
        "sample_count": sample_count,
        "ground_span_m": ground_span,
        "passes_existing_ground_span_gate": passes_existing_ground_gate,
        "mesh_bounds_diagonal_ratio_mean": mean_bounds_ratio,
        "mesh_bounds_diagonal_ratio_max": max_bounds_ratio,
        "mesh_bounds_max_size": [max_bounds_size.x, max_bounds_size.y, max_bounds_size.z],
        "capture": capture
    }

func _capture_animation(mode: String, clip: String, player: AnimationPlayer, sample_time: float, target: Node3D, skeleton: Skeleton3D) -> String:
    player.seek(sample_time, true)
    player.advance(0.0)
    skeleton.force_update_all_bone_transforms()
    return await _capture_target(mode, clip.to_lower().replace("_", "-"), target, skeleton)

func _capture_target(mode: String, label: String, target: Node3D, skeleton: Skeleton3D) -> String:
    var hips_idx := skeleton.find_bone("Hips")
    var head_idx := skeleton.find_bone("Head")
    var left_idx := skeleton.find_bone("LeftFoot")
    var right_idx := skeleton.find_bone("RightFoot")
    if hips_idx < 0 or head_idx < 0 or left_idx < 0 or right_idx < 0:
        _failures.append("capture_profile_bones_missing mode=%s label=%s" % [mode, label])
        return ""

    var left := skeleton.get_bone_global_pose(left_idx).origin
    var right := skeleton.get_bone_global_pose(right_idx).origin
    var ground_world := skeleton.to_global(Vector3(0.0, minf(left.y, right.y) - GROUND_CLEARANCE_M, 0.0))
    _ground.global_position.y = ground_world.y
    var hips_world := skeleton.to_global(skeleton.get_bone_global_pose(hips_idx).origin)
    var head_world := skeleton.to_global(skeleton.get_bone_global_pose(head_idx).origin)
    var center := (hips_world + head_world) * 0.5
    _camera.look_at_from_position(center + Vector3(2.9, 0.45, 4.15), center, Vector3.UP)

    await process_frame
    await process_frame
    RenderingServer.force_draw(false)
    await process_frame
    var image := root.get_texture().get_image()
    if image == null or image.is_empty():
        _failures.append("capture_empty mode=%s label=%s" % [mode, label])
        return ""
    if image.get_width() != 1280 or image.get_height() != 720:
        _failures.append("capture_size mode=%s label=%s got=%dx%d" % [mode, label, image.get_width(), image.get_height()])
        return ""
    var path := "res://gate8_import_%s_%s.png" % [mode, label]
    if image.save_png(path) != OK:
        _failures.append("capture_save_failed mode=%s label=%s" % [mode, label])
        return ""
    return path

func _profile_inventory(skeleton: Skeleton3D) -> Array[String]:
    var found: Array[String] = []
    for name: String in PROFILE_BONES:
        if skeleton.find_bone(name) >= 0:
            found.append(name)
    return found

func _rest_alignment(source: Skeleton3D, target: Skeleton3D) -> Dictionary:
    var values: Array[float] = []
    for name: String in PROFILE_BONES:
        var si := source.find_bone(name)
        var ti := target.find_bone(name)
        if si < 0 or ti < 0:
            continue
        var sq := source.get_bone_global_rest(si).basis.get_rotation_quaternion().normalized()
        var tq := target.get_bone_global_rest(ti).basis.get_rotation_quaternion().normalized()
        values.append(rad_to_deg(sq.angle_to(tq)))
    return {"mean_deg": _array_mean(values), "max_deg": _array_max(values), "samples": values.size()}

func _reset_skeleton_pose(skeleton: Skeleton3D) -> void:
    for idx: int in range(skeleton.get_bone_count()):
        skeleton.reset_bone_pose(idx)
    skeleton.force_update_all_bone_transforms()

func _mesh_world_bounds(node: Node3D) -> AABB:
    var have := false
    var min_v := Vector3.ZERO
    var max_v := Vector3.ZERO
    var meshes := node.find_children("*", "MeshInstance3D", true, false)
    for raw: Node in meshes:
        var mesh_instance := raw as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        var aabb := mesh_instance.get_aabb()
        for x: int in range(2):
            for y: int in range(2):
                for z: int in range(2):
                    var local := aabb.position + Vector3(aabb.size.x * x, aabb.size.y * y, aabb.size.z * z)
                    var world_point := mesh_instance.to_global(local)
                    if not have:
                        min_v = world_point
                        max_v = world_point
                        have = true
                    else:
                        min_v = Vector3(minf(min_v.x, world_point.x), minf(min_v.y, world_point.y), minf(min_v.z, world_point.z))
                        max_v = Vector3(maxf(max_v.x, world_point.x), maxf(max_v.y, world_point.y), maxf(max_v.z, world_point.z))
    return AABB(min_v, max_v - min_v) if have else AABB()

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child: Node in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        var ap := node as AnimationPlayer
        var all := true
        for token: String in CLIPS:
            if _resolve_animation_name(ap, token).is_empty():
                all = false
                break
        if all:
            return ap
    for child: Node in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _resolve_animation_name(player: AnimationPlayer, token: String) -> String:
    for raw: StringName in player.get_animation_list():
        var name := String(raw)
        if name == token or name.ends_with("/%s" % token):
            return name
    return ""

func _array_mean(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var total := 0.0
    for value: float in values:
        total += value
    return total / float(values.size())

func _array_min(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var value := INF
    for item: float in values:
        value = minf(value, item)
    return value

func _array_max(values: Array[float]) -> float:
    if values.is_empty():
        return 0.0
    var value := -INF
    for item: float in values:
        value = maxf(value, item)
    return value

func _build_world() -> void:
    _world = Node3D.new()
    _world.name = "Gate8ImportNormalizationWorld"
    root.add_child(_world)
    var environment := WorldEnvironment.new()
    var env := Environment.new()
    env.background_mode = Environment.BG_COLOR
    env.background_color = Color(0.16, 0.18, 0.21, 1.0)
    env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    env.ambient_light_color = Color(0.80, 0.82, 0.86, 1.0)
    env.ambient_light_energy = 1.1
    environment.environment = env
    _world.add_child(environment)
    var light := DirectionalLight3D.new()
    light.rotation_degrees = Vector3(-42.0, -28.0, 0.0)
    light.light_energy = 1.3
    light.shadow_enabled = true
    _world.add_child(light)
    _ground = MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(8.0, 8.0)
    _ground.mesh = plane
    var material := StandardMaterial3D.new()
    material.albedo_color = Color(0.30, 0.31, 0.32, 1.0)
    material.roughness = 0.92
    _ground.material_override = material
    _world.add_child(_ground)
    _camera = Camera3D.new()
    _camera.fov = 58.0
    _camera.current = true
    _world.add_child(_camera)

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_import_normalization_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()
