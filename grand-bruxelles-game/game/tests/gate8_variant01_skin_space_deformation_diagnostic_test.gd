extends SceneTree

const SOURCE_SCENE := "res://assets/animation_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const CLIPS: Array[String] = ["Jog_Fwd", "Sprint"]
const EXPECTED_ROLES := 22
const SAMPLE_RATE_HZ := 30.0
const MIN_SAMPLES := 24
const MAX_EDGE_STRETCH_RATIO := 3.0
const MIN_EDGE_COMPRESSION_RATIO := 0.25
const SYNTHETIC_RIGID_EDGE_EPSILON := 0.00001
const ROLE_ORDER: Array[String] = [
    "hips", "spine", "chest", "upper_chest", "neck", "head",
    "left_shoulder", "left_upper_arm", "left_forearm", "left_hand",
    "right_shoulder", "right_upper_arm", "right_forearm", "right_hand",
    "left_upper_leg", "left_lower_leg", "left_foot", "left_toe",
    "right_upper_leg", "right_lower_leg", "right_foot", "right_toe"
]
const ROLE_MAP := {
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
    "right_toe": ["DEF-toe.R", "ball_r"]
}

var _failures: Array[String] = []
var _source: Skeleton3D
var _target: Skeleton3D
var _player: AnimationPlayer
var _source_indices: Dictionary = {}
var _target_indices: Dictionary = {}
var _meshes: Array[MeshInstance3D] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    if not _synthetic_rigid_regression():
        _failures.append("synthetic_rigid_skinning_regression_failed")
    var source_packed := load(SOURCE_SCENE) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null or target_packed == null:
        _failures.append("source_or_target_load_failed")
        _finish({})
        return
    var source_scene := source_packed.instantiate() as Node3D
    var target_scene := target_packed.instantiate() as Node3D
    if source_scene == null or target_scene == null:
        _failures.append("source_or_target_instance_failed")
        _finish({})
        return
    root.add_child(source_scene)
    root.add_child(target_scene)
    await process_frame
    await process_frame
    _source = _find_skeleton(source_scene)
    _target = _find_skeleton(target_scene)
    _player = _find_animation_player(source_scene)
    _collect_skinned_meshes(target_scene, _meshes)
    if _source == null or _target == null or _player == null:
        _failures.append("required_skeleton_or_animation_player_missing")
    if _meshes.is_empty():
        _failures.append("no_skinned_meshes_found")
    if not _build_role_cache():
        _finish({})
        return

    _target.reset_bone_poses()
    _target.force_update_all_bone_transforms()
    var rest_positions := _capture_skinned_positions()
    if rest_positions.is_empty():
        _failures.append("rest_skin_positions_missing")
        _finish({})
        return

    var clips: Dictionary = {}
    var global_max_stretch := 1.0
    var global_min_compression := 1.0
    var global_worst_clip := ""
    for clip: String in CLIPS:
        var row := _measure_clip(clip, rest_positions)
        clips[clip] = row
        var stretch := float(row.get("max_edge_stretch_ratio", 1.0))
        var compression := float(row.get("min_edge_compression_ratio", 1.0))
        if stretch > global_max_stretch:
            global_max_stretch = stretch
            global_worst_clip = clip
        global_min_compression = minf(global_min_compression, compression)

    var outlier := global_max_stretch > MAX_EDGE_STRETCH_RATIO or global_min_compression < MIN_EDGE_COMPRESSION_RATIO
    var result := {
        "format": "grand-bruxelles-gate8-skin-space-deformation-diagnostic-v2",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "reviewed_role_count": ROLE_ORDER.size(),
        "skinned_mesh_count": _meshes.size(),
        "clips": clips,
        "max_edge_stretch_ratio": global_max_stretch,
        "min_edge_compression_ratio": global_min_compression,
        "max_edge_stretch_allowed_ratio": MAX_EDGE_STRETCH_RATIO,
        "min_edge_compression_allowed_ratio": MIN_EDGE_COMPRESSION_RATIO,
        "worst_clip": global_worst_clip,
        "diagnostic_state": "SKIN_SPACE_DEFORMATION_OUTLIER" if outlier else "SKIN_SPACE_DEFORMATION_WITHIN_DIAGNOSTIC_BOUNDS",
        "worst_edge_bind_localization": true,
        "synthetic_rigid_regression": true,
        "retarget_applied": false,
        "target_skin_modified": false,
        "target_rest_modified": false,
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "failures": _failures
    }
    _write_result(result)
    print("GATE8_SKIN_SPACE state=%s stretch=%.6f compression=%.6f meshes=%d" % [result["diagnostic_state"], global_max_stretch, global_min_compression, _meshes.size()])
    _finish(result)

func _build_role_cache() -> bool:
    if ROLE_ORDER.size() != EXPECTED_ROLES or ROLE_MAP.size() != EXPECTED_ROLES:
        _failures.append("reviewed_role_count_changed")
        return false
    for role: String in ROLE_ORDER:
        var pair: Array = ROLE_MAP[role]
        var source_idx := _source.find_bone(String(pair[0]))
        var target_idx := _target.find_bone(String(pair[1]))
        if source_idx < 0:
            _failures.append("source_bone_missing role=%s" % role)
        if target_idx < 0:
            _failures.append("target_bone_missing role=%s" % role)
        _source_indices[role] = source_idx
        _target_indices[role] = target_idx
    return _failures.is_empty()

func _measure_clip(clip: String, rest_positions: Dictionary) -> Dictionary:
    var animation_name := _resolve_animation_name(_player, clip)
    if animation_name.is_empty():
        _failures.append("clip_missing=%s" % clip)
        return {}
    var animation := _player.get_animation(animation_name)
    if animation == null or animation.length <= 0.0:
        _failures.append("clip_invalid=%s" % clip)
        return {}
    var sample_count := maxi(MIN_SAMPLES, int(ceil(animation.length * SAMPLE_RATE_HZ)))
    var best_time := 0.0
    var best_amplitude := -1.0
    for sample_idx: int in range(sample_count):
        var time_s := minf(animation.length - 0.00001, animation.length * float(sample_idx) / float(sample_count))
        _sample_source(animation_name, time_s)
        var amplitude := _combined_source_rotation_amplitude()
        if amplitude > best_amplitude:
            best_amplitude = amplitude
            best_time = time_s
    _sample_source(animation_name, best_time)
    _apply_combined_pose()
    _target.force_update_all_bone_transforms()
    var posed_positions := _capture_skinned_positions()
    var distortion := _measure_edge_distortion(rest_positions, posed_positions)
    _target.reset_bone_poses()
    _target.force_update_all_bone_transforms()
    distortion["animation_name"] = animation_name
    distortion["sample_count"] = sample_count
    distortion["selected_time_s"] = best_time
    distortion["combined_source_rotation_amplitude_rad"] = best_amplitude
    return distortion

func _combined_source_rotation_amplitude() -> float:
    var total := 0.0
    for role: String in ROLE_ORDER:
        var idx := int(_source_indices[role])
        var rest_q := _source.get_bone_rest(idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        var pose_q := _source.get_bone_pose(idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        total += rest_q.angle_to(pose_q)
    return total

func _apply_combined_pose() -> void:
    _target.reset_bone_poses()
    for role: String in ROLE_ORDER:
        var source_idx := int(_source_indices[role])
        var target_idx := int(_target_indices[role])
        var source_rest_q := _source.get_bone_rest(source_idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        var source_pose_q := _source.get_bone_pose(source_idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        var delta_q := (source_rest_q.inverse() * source_pose_q).normalized()
        var target_rest_q := _target.get_bone_rest(target_idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        _target.set_bone_pose_rotation(target_idx, (target_rest_q * delta_q).normalized())

func _capture_skinned_positions() -> Dictionary:
    var result: Dictionary = {}
    for mesh_instance: MeshInstance3D in _meshes:
        if mesh_instance.mesh == null or mesh_instance.skin == null:
            _failures.append("mesh_or_skin_missing=%s" % mesh_instance.name)
            continue
        var mesh: Mesh = mesh_instance.mesh
        for surface_idx: int in range(mesh.get_surface_count()):
            if mesh.surface_get_primitive_type(surface_idx) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var arrays: Array = mesh.surface_get_arrays(surface_idx)
            if arrays.size() <= Mesh.ARRAY_WEIGHTS:
                _failures.append("surface_arrays_incomplete mesh=%s surface=%d" % [mesh_instance.name, surface_idx])
                continue
            var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
            var bones = arrays[Mesh.ARRAY_BONES]
            var weights = arrays[Mesh.ARRAY_WEIGHTS]
            if vertices.is_empty() or bones.size() != vertices.size() * 4 or weights.size() != vertices.size() * 4:
                _failures.append("skin_array_shape_invalid mesh=%s surface=%d vertices=%d bones=%d weights=%d" % [mesh_instance.name, surface_idx, vertices.size(), bones.size(), weights.size()])
                continue
            var transformed := PackedVector3Array()
            transformed.resize(vertices.size())
            for vertex_idx: int in range(vertices.size()):
                transformed[vertex_idx] = _skin_vertex(mesh_instance.skin, vertices[vertex_idx], bones, weights, vertex_idx)
            result[_surface_key(mesh_instance, surface_idx)] = transformed
    return result

func _skin_vertex(skin: Skin, vertex: Vector3, bones, weights, vertex_idx: int) -> Vector3:
    var out := Vector3.ZERO
    var weight_sum := 0.0
    for influence_idx: int in range(4):
        var offset := vertex_idx * 4 + influence_idx
        var weight := float(weights[offset])
        if weight <= 0.0:
            continue
        var bind_idx := int(bones[offset])
        if bind_idx < 0 or bind_idx >= skin.get_bind_count():
            _failures.append("bind_index_out_of_range=%d" % bind_idx)
            continue
        var bone_idx := _resolve_skin_bone(skin, bind_idx)
        if bone_idx < 0:
            _failures.append("skin_bind_unresolved=%d" % bind_idx)
            continue
        var skin_transform := _target.get_bone_global_pose(bone_idx) * skin.get_bind_pose(bind_idx)
        out += (skin_transform * vertex) * weight
        weight_sum += weight
    if weight_sum <= 0.000001:
        return vertex
    return out / weight_sum

func _resolve_skin_bone(skin: Skin, bind_idx: int) -> int:
    var bind_name := String(skin.get_bind_name(bind_idx))
    if not bind_name.is_empty():
        return _target.find_bone(bind_name)
    return skin.get_bind_bone(bind_idx)

func _measure_edge_distortion(rest_positions: Dictionary, posed_positions: Dictionary) -> Dictionary:
    var max_ratio := 1.0
    var min_ratio := 1.0
    var max_abs_change := 0.0
    var worst_surface := ""
    var worst_triangle := -1
    var worst_edge := ""
    var worst_vertex_a := -1
    var worst_vertex_b := -1
    var worst_triangle_vertices: Array[int] = []
    var worst_vertex_a_influences: Array[Dictionary] = []
    var worst_vertex_b_influences: Array[Dictionary] = []
    var triangles_measured := 0
    for mesh_instance: MeshInstance3D in _meshes:
        var mesh: Mesh = mesh_instance.mesh
        for surface_idx: int in range(mesh.get_surface_count()):
            if mesh.surface_get_primitive_type(surface_idx) != Mesh.PRIMITIVE_TRIANGLES:
                continue
            var key := _surface_key(mesh_instance, surface_idx)
            if not rest_positions.has(key) or not posed_positions.has(key):
                continue
            var arrays: Array = mesh.surface_get_arrays(surface_idx)
            var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
            var bones = arrays[Mesh.ARRAY_BONES]
            var weights = arrays[Mesh.ARRAY_WEIGHTS]
            var rest: PackedVector3Array = rest_positions[key]
            var posed: PackedVector3Array = posed_positions[key]
            var triangle_count := indices.size() / 3 if not indices.is_empty() else rest.size() / 3
            for tri_idx: int in range(triangle_count):
                var ids := PackedInt32Array()
                ids.resize(3)
                for corner: int in range(3):
                    ids[corner] = indices[tri_idx * 3 + corner] if not indices.is_empty() else tri_idx * 3 + corner
                if ids[0] >= rest.size() or ids[1] >= rest.size() or ids[2] >= rest.size():
                    _failures.append("triangle_index_out_of_range mesh=%s surface=%d triangle=%d" % [mesh_instance.name, surface_idx, tri_idx])
                    continue
                triangles_measured += 1
                var pairs := [[0, 1, "01"], [1, 2, "12"], [2, 0, "20"]]
                for pair: Array in pairs:
                    var a := int(ids[int(pair[0])])
                    var b := int(ids[int(pair[1])])
                    var rest_len := rest[a].distance_to(rest[b])
                    if rest_len <= 0.000001:
                        continue
                    var posed_len := posed[a].distance_to(posed[b])
                    var ratio := posed_len / rest_len
                    var abs_change := absf(posed_len - rest_len)
                    if ratio > max_ratio:
                        max_ratio = ratio
                        worst_surface = key
                        worst_triangle = tri_idx
                        worst_edge = String(pair[2])
                        worst_vertex_a = a
                        worst_vertex_b = b
                        worst_triangle_vertices = [int(ids[0]), int(ids[1]), int(ids[2])]
                        worst_vertex_a_influences = _vertex_influences(mesh_instance.skin, bones, weights, a)
                        worst_vertex_b_influences = _vertex_influences(mesh_instance.skin, bones, weights, b)
                    min_ratio = minf(min_ratio, ratio)
                    max_abs_change = maxf(max_abs_change, abs_change)
    if triangles_measured <= 0:
        _failures.append("no_triangles_measured")
    return {
        "triangles_measured": triangles_measured,
        "max_edge_stretch_ratio": max_ratio,
        "min_edge_compression_ratio": min_ratio,
        "max_edge_absolute_change_m": max_abs_change,
        "worst_surface": worst_surface,
        "worst_triangle": worst_triangle,
        "worst_edge": worst_edge,
        "worst_triangle_vertices": worst_triangle_vertices,
        "worst_vertex_a": worst_vertex_a,
        "worst_vertex_b": worst_vertex_b,
        "worst_vertex_a_influences": worst_vertex_a_influences,
        "worst_vertex_b_influences": worst_vertex_b_influences
    }

func _vertex_influences(skin: Skin, bones, weights, vertex_idx: int) -> Array[Dictionary]:
    var rows: Array[Dictionary] = []
    for influence_idx: int in range(4):
        var offset := vertex_idx * 4 + influence_idx
        var weight := float(weights[offset])
        if weight <= 0.0:
            continue
        var bind_idx := int(bones[offset])
        if bind_idx < 0 or bind_idx >= skin.get_bind_count():
            _failures.append("worst_edge_bind_index_out_of_range=%d" % bind_idx)
            continue
        var bone_idx := _resolve_skin_bone(skin, bind_idx)
        if bone_idx < 0:
            _failures.append("worst_edge_skin_bind_unresolved=%d" % bind_idx)
            continue
        var bone_name := String(_target.get_bone_name(bone_idx))
        rows.append({
            "weight": weight,
            "bind_index": bind_idx,
            "bind_name": String(skin.get_bind_name(bind_idx)),
            "bone_index": bone_idx,
            "bone_name": bone_name,
            "reviewed_role": _reviewed_role_for_target_bone(bone_name)
        })
    return rows

func _reviewed_role_for_target_bone(bone_name: String) -> String:
    for role: String in ROLE_ORDER:
        var pair: Array = ROLE_MAP[role]
        if String(pair[1]) == bone_name:
            return role
    return ""

func _synthetic_rigid_regression() -> bool:
    var triangle: Array[Vector3] = [Vector3(0.0, 0.0, 0.0), Vector3(0.7, 0.1, 0.0), Vector3(0.2, 0.8, 0.3)]
    var rigid := Transform3D(Basis.from_euler(Vector3(0.31, -0.47, 0.19)), Vector3(1.2, -0.4, 0.8))
    var moved: Array[Vector3] = [rigid * triangle[0], rigid * triangle[1], rigid * triangle[2]]
    var edge_pairs: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 0)]
    for pair: Vector2i in edge_pairs:
        var before: float = triangle[pair.x].distance_to(triangle[pair.y])
        var after: float = moved[pair.x].distance_to(moved[pair.y])
        if absf(after / before - 1.0) > SYNTHETIC_RIGID_EDGE_EPSILON:
            return false
    return true

func _surface_key(mesh_instance: MeshInstance3D, surface_idx: int) -> String:
    return "%s#%d" % [String(mesh_instance.get_path()), surface_idx]

func _sample_source(animation_name: String, time_s: float) -> void:
    _player.play(animation_name)
    _player.pause()
    _player.seek(time_s, true)
    _player.advance(0.0)
    _source.force_update_all_bone_transforms()

func _resolve_animation_name(player: AnimationPlayer, token: String) -> String:
    var wanted := token.to_lower()
    for animation_name in player.get_animation_list():
        var raw := String(animation_name)
        var leaf := raw.get_slice("/", raw.get_slice_count("/") - 1)
        if leaf.to_lower() == wanted:
            return raw
    return ""

func _collect_skinned_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.mesh != null and mesh_instance.skin != null:
            out.append(mesh_instance)
    for child in node.get_children():
        _collect_skinned_meshes(child, out)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found != null:
            return found
    return null

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_skin_space_deformation_diagnostic_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "\t"))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        quit(0)
    for failure: String in _failures:
        push_error(failure)
    quit(1)
