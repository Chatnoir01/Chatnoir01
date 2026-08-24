extends SceneTree

const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const TARGET_BONES: Array[String] = [
    "spine_02",
    "spine_03",
    "clavicle_l",
    "clavicle_r",
    "upperarm_l",
    "upperarm_r",
]
const RESET_REST_TRANSLATION_EPS_M := 0.0001
const RESET_REST_ROTATION_EPS_DEG := 0.05
const IDENTITY_TRANSLATION_EPS_M := 0.001
const IDENTITY_ROTATION_EPS_DEG := 0.25
const SYMMETRY_TRANSLATION_EPS_M := 0.01
const SYMMETRY_ROTATION_EPS_DEG := 2.0

var _failures: Array[String] = []
var _target: Skeleton3D
var _meshes: Array[MeshInstance3D] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(TARGET_SCENE) as PackedScene
    if packed == null:
        _failures.append("target_load_failed")
        _finish({})
        return
    var scene := packed.instantiate() as Node3D
    if scene == null:
        _failures.append("target_instance_failed")
        _finish({})
        return
    root.add_child(scene)
    await process_frame
    await process_frame

    _target = _find_skeleton(scene)
    _collect_skinned_meshes(scene, _meshes)
    if _target == null:
        _failures.append("target_skeleton_missing")
    if _meshes.is_empty():
        _failures.append("target_skinned_meshes_missing")
    if not _failures.is_empty():
        _finish({})
        return

    var bone_indices: Dictionary = {}
    for bone_name: String in TARGET_BONES:
        var bone_idx := _target.find_bone(bone_name)
        if bone_idx < 0:
            _failures.append("target_bone_missing=%s" % bone_name)
        else:
            bone_indices[bone_name] = bone_idx
    if not _failures.is_empty():
        _finish({})
        return

    _target.reset_bone_poses()
    _target.force_update_all_bone_transforms()

    var rows: Dictionary = {}
    var bind_observations := 0
    var max_reset_rest_translation := 0.0
    var max_reset_rest_rotation := 0.0
    var max_identity_translation := 0.0
    var max_identity_rotation := 0.0

    for bone_name: String in TARGET_BONES:
        var bone_idx: int = int(bone_indices[bone_name])
        var global_rest := _global_rest(bone_idx)
        var global_pose: Transform3D = _target.get_bone_global_pose(bone_idx)
        var observations: Array[Dictionary] = []
        for mesh_instance: MeshInstance3D in _meshes:
            var skin := mesh_instance.skin
            if skin == null:
                continue
            for bind_idx: int in range(skin.get_bind_count()):
                var resolved_bone := _resolve_skin_bone(skin, bind_idx)
                if resolved_bone != bone_idx:
                    continue
                var bind_pose := skin.get_bind_pose(bind_idx)
                var rest_product := global_rest * bind_pose
                var reset_product := global_pose * bind_pose
                var reset_rest_translation := rest_product.origin.distance_to(reset_product.origin)
                var reset_rest_rotation := _basis_delta_deg(rest_product.basis, reset_product.basis)
                var identity_translation := rest_product.origin.length()
                var identity_rotation := _basis_delta_deg(Basis.IDENTITY, rest_product.basis)
                max_reset_rest_translation = maxf(max_reset_rest_translation, reset_rest_translation)
                max_reset_rest_rotation = maxf(max_reset_rest_rotation, reset_rest_rotation)
                max_identity_translation = maxf(max_identity_translation, identity_translation)
                max_identity_rotation = maxf(max_identity_rotation, identity_rotation)
                bind_observations += 1
                observations.append({
                    "mesh": String(mesh_instance.get_path()),
                    "bind_index": bind_idx,
                    "bind_name": String(skin.get_bind_name(bind_idx)),
                    "bind_bone": skin.get_bind_bone(bind_idx),
                    "rest_product_translation_m": identity_translation,
                    "rest_product_rotation_deg": identity_rotation,
                    "reset_vs_rest_translation_m": reset_rest_translation,
                    "reset_vs_rest_rotation_deg": reset_rest_rotation,
                    "rest_product_origin": _vec3_row(rest_product.origin),
                    "reset_product_origin": _vec3_row(reset_product.origin),
                })
        if observations.is_empty():
            _failures.append("skin_bind_missing_for_bone=%s" % bone_name)
        rows[bone_name] = {
            "bone_index": bone_idx,
            "global_rest_origin": _vec3_row(global_rest.origin),
            "global_pose_origin_after_reset": _vec3_row(global_pose.origin),
            "observations": observations,
        }

    if max_reset_rest_translation > RESET_REST_TRANSLATION_EPS_M:
        _failures.append("reset_rest_translation_drift=%.9f" % max_reset_rest_translation)
    if max_reset_rest_rotation > RESET_REST_ROTATION_EPS_DEG:
        _failures.append("reset_rest_rotation_drift_deg=%.9f" % max_reset_rest_rotation)

    var symmetry := {
        "clavicle": _symmetry_row(rows, "clavicle_l", "clavicle_r"),
        "upperarm": _symmetry_row(rows, "upperarm_l", "upperarm_r"),
    }
    var intentional_offset_present := max_identity_translation > IDENTITY_TRANSLATION_EPS_M or max_identity_rotation > IDENTITY_ROTATION_EPS_DEG
    var state := "STATIC_IMPORTED_BIND_OFFSET_PRESENT" if intentional_offset_present else "REST_BIND_IDENTITY_ALIGNED"

    var result := {
        "format": "grand-bruxelles-gate8-shoulder-bind-residual-diagnostic-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "target_bones": TARGET_BONES,
        "bind_observations": bind_observations,
        "max_reset_vs_rest_translation_m": max_reset_rest_translation,
        "max_reset_vs_rest_rotation_deg": max_reset_rest_rotation,
        "max_rest_product_translation_m": max_identity_translation,
        "max_rest_product_rotation_deg": max_identity_rotation,
        "reset_rest_translation_epsilon_m": RESET_REST_TRANSLATION_EPS_M,
        "reset_rest_rotation_epsilon_deg": RESET_REST_ROTATION_EPS_DEG,
        "identity_translation_epsilon_m": IDENTITY_TRANSLATION_EPS_M,
        "identity_rotation_epsilon_deg": IDENTITY_ROTATION_EPS_DEG,
        "symmetry": symmetry,
        "bones": rows,
        "diagnostic_state": state,
        "target_skin_modified": false,
        "target_rest_modified": false,
        "retarget_applied": false,
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "failures": _failures,
    }
    _write_result(result)
    print("GATE8_SHOULDER_BIND_RESIDUAL state=%s observations=%d reset_rest_m=%.9f reset_rest_deg=%.9f rest_product_m=%.9f rest_product_deg=%.9f" % [state, bind_observations, max_reset_rest_translation, max_reset_rest_rotation, max_identity_translation, max_identity_rotation])
    _finish(result)

func _global_rest(bone_idx: int) -> Transform3D:
    var chain: Array[int] = []
    var current := bone_idx
    while current >= 0:
        chain.push_front(current)
        current = _target.get_bone_parent(current)
    var out := Transform3D.IDENTITY
    for idx: int in chain:
        out = out * _target.get_bone_rest(idx)
    return out

func _resolve_skin_bone(skin: Skin, bind_idx: int) -> int:
    var bind_name := String(skin.get_bind_name(bind_idx))
    if not bind_name.is_empty():
        return _target.find_bone(bind_name)
    return skin.get_bind_bone(bind_idx)

func _symmetry_row(rows: Dictionary, left_name: String, right_name: String) -> Dictionary:
    var left: Dictionary = rows.get(left_name, {})
    var right: Dictionary = rows.get(right_name, {})
    var left_obs: Array = left.get("observations", [])
    var right_obs: Array = right.get("observations", [])
    if left_obs.is_empty() or right_obs.is_empty():
        return {"comparable": false}
    var left_first: Dictionary = left_obs[0]
    var right_first: Dictionary = right_obs[0]
    var translation_delta := absf(float(left_first["rest_product_translation_m"]) - float(right_first["rest_product_translation_m"]))
    var rotation_delta := absf(float(left_first["rest_product_rotation_deg"]) - float(right_first["rest_product_rotation_deg"]))
    return {
        "comparable": true,
        "translation_magnitude_delta_m": translation_delta,
        "rotation_magnitude_delta_deg": rotation_delta,
        "translation_symmetric": translation_delta <= SYMMETRY_TRANSLATION_EPS_M,
        "rotation_symmetric": rotation_delta <= SYMMETRY_ROTATION_EPS_DEG,
    }

func _basis_delta_deg(a: Basis, b: Basis) -> float:
    var qa := a.orthonormalized().get_rotation_quaternion().normalized()
    var qb := b.orthonormalized().get_rotation_quaternion().normalized()
    return rad_to_deg(qa.angle_to(qb))

func _vec3_row(value: Vector3) -> Dictionary:
    return {"x": value.x, "y": value.y, "z": value.z}

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

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_variant01_shoulder_bind_residual_result.json", FileAccess.WRITE)
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
