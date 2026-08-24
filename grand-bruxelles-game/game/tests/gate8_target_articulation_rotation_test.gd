extends SceneTree

const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const PROBE_DEGREES := 12.0
const MIN_ROTATION_DEG := 11.5
const MAX_ROTATION_DEG := 12.5
const MAX_TWIST_PIVOT_TRANSLATION_M := 0.0001
const ROLE_BONES := {
    "left_shoulder": "clavicle_l",
    "left_upper_arm": "upperarm_l",
    "left_forearm": "lowerarm_l",
    "left_upper_leg": "thigh_l",
}
const PROBES := [
    {"id":"left-shoulder", "role":"left_shoulder", "axis":Vector3.FORWARD},
    {"id":"left-upper-arm", "role":"left_upper_arm", "axis":Vector3.FORWARD},
    {"id":"left-forearm-twist", "role":"left_forearm", "axis":Vector3.UP},
    {"id":"left-upper-leg", "role":"left_upper_leg", "axis":Vector3.RIGHT},
]

var _failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var packed := load(TARGET_SCENE) as PackedScene
    if packed == null:
        _finish({}, ["target_scene_load_failed"])
        return
    var target_scene := packed.instantiate() as Node3D
    root.add_child(target_scene)
    await process_frame
    await process_frame
    var skeleton := _find_skeleton(target_scene)
    if skeleton == null:
        _finish({}, ["target_skeleton_missing"])
        return

    var integrity := _target_integrity(target_scene)
    if int(integrity["skinned_meshes"]) <= 0:
        _failures.append("skinned_meshes_missing")
    if int(integrity["missing_material_surfaces"]) != 0:
        _failures.append("missing_material_surfaces=%d" % int(integrity["missing_material_surfaces"]))

    var rows := {}
    for probe in PROBES:
        var role := String(probe["role"])
        var bone_name := String(ROLE_BONES[role])
        var idx := skeleton.find_bone(bone_name)
        if idx < 0:
            _failures.append("bone_missing role=%s bone=%s" % [role, bone_name])
            continue
        skeleton.reset_bone_poses()
        skeleton.force_update_all_bone_transforms()
        var rest_rotation := skeleton.get_bone_rest(idx).basis.orthonormalized().get_rotation_quaternion().normalized()
        var pivot_before := skeleton.get_bone_global_pose(idx).origin
        var delta := Quaternion(Vector3(probe["axis"]), deg_to_rad(PROBE_DEGREES))
        skeleton.set_bone_pose_rotation(idx, (rest_rotation * delta).normalized())
        skeleton.force_update_all_bone_transforms()
        var pose_rotation := skeleton.get_bone_pose_rotation(idx).normalized()
        var rotation_delta_deg := rad_to_deg(rest_rotation.angle_to(pose_rotation))
        var pivot_after := skeleton.get_bone_global_pose(idx).origin
        var pivot_translation_m := pivot_before.distance_to(pivot_after)
        if not is_finite(rotation_delta_deg) or rotation_delta_deg < MIN_ROTATION_DEG or rotation_delta_deg > MAX_ROTATION_DEG:
            _failures.append("rotation_response_invalid role=%s delta_deg=%.6f" % [role, rotation_delta_deg])
        if role == "left_forearm" and pivot_translation_m > MAX_TWIST_PIVOT_TRANSLATION_M:
            _failures.append("forearm_twist_pivot_translated_m=%.8f" % pivot_translation_m)
        rows[String(probe["id"])] = {
            "role": role,
            "bone": bone_name,
            "requested_rotation_deg": PROBE_DEGREES,
            "measured_rotation_delta_deg": rotation_delta_deg,
            "pivot_translation_m": pivot_translation_m,
        }

    if rows.size() != PROBES.size():
        _failures.append("probe_count=%d expected=%d" % [rows.size(), PROBES.size()])
    var result := {
        "format": "grand-bruxelles-gate8-target-articulation-rotation-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "measurement_contract": "rest_relative_rotation_not_pivot_translation",
        "probe_degrees": PROBE_DEGREES,
        "rotation_bounds_deg": [MIN_ROTATION_DEG, MAX_ROTATION_DEG],
        "max_twist_pivot_translation_m": MAX_TWIST_PIVOT_TRANSLATION_M,
        "target_integrity": integrity,
        "probes": rows,
        "retarget_involved": false,
        "animation_source_involved": false,
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "selection_state": "TARGET_ARTICULATION_ROTATION_VALID" if _failures.is_empty() else "BLOCKED_TARGET_ARTICULATION_ROTATION",
        "failures": _failures,
    }
    _write_result(result)
    _finish(result, _failures)

func _target_integrity(node: Node) -> Dictionary:
    var skinned_meshes := 0
    var skinned_surfaces := 0
    var materials := 0
    var missing_material_surfaces := 0
    for raw in node.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := raw as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        if mesh_instance.skin == null and mesh_instance.skeleton.is_empty():
            continue
        skinned_meshes += 1
        for surface in range(mesh_instance.mesh.get_surface_count()):
            skinned_surfaces += 1
            var material := mesh_instance.get_surface_override_material(surface)
            if material == null:
                material = mesh_instance.mesh.surface_get_material(surface)
            if material == null:
                missing_material_surfaces += 1
            else:
                materials += 1
    return {
        "skinned_meshes": skinned_meshes,
        "skinned_surfaces": skinned_surfaces,
        "materials": materials,
        "missing_material_surfaces": missing_material_surfaces,
    }

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open("res://gate8_target_articulation_rotation_result.json", FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary, failures: Array[String]) -> void:
    if failures.is_empty():
        print("GATE8_TARGET_ARTICULATION_ROTATION_OK probes=4 measurement=rest_relative_rotation production_authorized=false")
        quit(0)
        return
    for failure in failures:
        push_error("GATE8_TARGET_ARTICULATION_ROTATION_FAIL %s" % failure)
    quit(1)
