extends SceneTree

const SOURCE_SCENE := "res://assets/steve_source.glb"
const TARGET_SCENE := "res://assets/npc_gate_01.glb"
const RESULT_PATH := "res://gate8_variant01_steve_godot_import_preflight_result.json"
const MIN_SOURCE_BONES := 55
const MIN_SOURCE_SKINNED_MESHES := 1
const MIN_TARGET_BONES := 53
const MIN_WALK_DURATION_S := 0.1

const REQUIRED_SOURCE_BONES: Array[String] = [
    "pelvis",
    "armup.L",
    "armup.R",
    "foot1.L",
    "foot1.R",
]

const REQUIRED_TARGET_BONES: Array[String] = [
    "pelvis",
    "spine_01",
    "upperarm_l",
    "upperarm_r",
    "foot_l",
    "foot_r",
]

var _failures: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var source_packed := load(SOURCE_SCENE) as PackedScene
    var target_packed := load(TARGET_SCENE) as PackedScene
    if source_packed == null:
        _failures.append("source_scene_load_failed")
    if target_packed == null:
        _failures.append("target_scene_load_failed")
    if not _failures.is_empty():
        _finish({})
        return

    var source_instance := source_packed.instantiate()
    var target_instance := target_packed.instantiate()
    if source_instance == null:
        _failures.append("source_scene_instantiate_failed")
    if target_instance == null:
        _failures.append("target_scene_instantiate_failed")
    if not _failures.is_empty():
        _finish({})
        return

    root.add_child(source_instance)
    root.add_child(target_instance)
    await process_frame

    var source_skeleton := _find_skeleton(source_instance)
    var target_skeleton := _find_skeleton(target_instance)
    if source_skeleton == null:
        _failures.append("source_skeleton_missing")
    if target_skeleton == null:
        _failures.append("target_skeleton_missing")
    if not _failures.is_empty():
        _finish({})
        return

    var source_bone_count := source_skeleton.get_bone_count()
    var target_bone_count := target_skeleton.get_bone_count()
    if source_bone_count < MIN_SOURCE_BONES:
        _failures.append("source_bone_count=%d minimum=%d" % [source_bone_count, MIN_SOURCE_BONES])
    if target_bone_count < MIN_TARGET_BONES:
        _failures.append("target_bone_count=%d minimum=%d" % [target_bone_count, MIN_TARGET_BONES])

    var missing_source_bones: Array[String] = []
    for bone_name: String in REQUIRED_SOURCE_BONES:
        if source_skeleton.find_bone(bone_name) < 0:
            missing_source_bones.append(bone_name)
    if not missing_source_bones.is_empty():
        _failures.append("source_required_bones_missing=%s" % ",".join(missing_source_bones))

    var missing_target_bones: Array[String] = []
    for bone_name: String in REQUIRED_TARGET_BONES:
        if target_skeleton.find_bone(bone_name) < 0:
            missing_target_bones.append(bone_name)
    if not missing_target_bones.is_empty():
        _failures.append("target_required_bones_missing=%s" % ",".join(missing_target_bones))

    var source_skinned_meshes := _count_skinned_meshes(source_instance)
    if source_skinned_meshes < MIN_SOURCE_SKINNED_MESHES:
        _failures.append("source_skinned_meshes=%d minimum=%d" % [source_skinned_meshes, MIN_SOURCE_SKINNED_MESHES])

    var walk := _find_walk_animation(source_instance)
    if not bool(walk.get("found", false)):
        _failures.append("walk_animation_missing_after_godot_import")
    else:
        var duration := float(walk.get("duration_s", 0.0))
        if duration < MIN_WALK_DURATION_S:
            _failures.append("walk_duration_s=%.6f minimum=%.6f" % [duration, MIN_WALK_DURATION_S])
        if int(walk.get("track_count", 0)) <= 0:
            _failures.append("walk_animation_has_no_tracks")

    var state := "READY_FOR_EXPLICIT_BONEMAP_PREFLIGHT" if _failures.is_empty() else "BLOCKED_GODOT_IMPORT_PREFLIGHT"
    var result := {
        "format": "grand-bruxelles-gate8-variant01-steve-godot-import-preflight-result-v1",
        "engine_version": Engine.get_version_info().get("string", "unknown"),
        "candidate_variant": 1,
        "source_bone_count": source_bone_count,
        "target_bone_count": target_bone_count,
        "source_skinned_mesh_count": source_skinned_meshes,
        "required_source_bones": REQUIRED_SOURCE_BONES,
        "missing_source_bones": missing_source_bones,
        "required_target_bones": REQUIRED_TARGET_BONES,
        "missing_target_bones": missing_target_bones,
        "walk_animation_name": String(walk.get("name", "")),
        "walk_duration_s": float(walk.get("duration_s", 0.0)),
        "walk_track_count": int(walk.get("track_count", 0)),
        "mechanical_state": state,
        "explicit_role_mapping_selected": false,
        "retarget_applied": false,
        "walk_alias_selected": "",
        "run_alias_selected": "",
        "production_authorized": false,
        "activation_ready": false,
        "adoption_ready": false,
        "runtime_population_changed": false,
        "visual_approval_claimed": false,
        "failures": _failures,
    }
    _write_result(result)
    _finish(result)

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child: Node in node.get_children():
        var found := _find_skeleton(child)
        if found != null:
            return found
    return null

func _count_skinned_meshes(node: Node) -> int:
    var count := 0
    if node is MeshInstance3D:
        var mesh_instance := node as MeshInstance3D
        if mesh_instance.skin != null or not String(mesh_instance.skeleton).is_empty():
            count += 1
    for child: Node in node.get_children():
        count += _count_skinned_meshes(child)
    return count

func _find_walk_animation(node: Node) -> Dictionary:
    if node is AnimationPlayer:
        var player := node as AnimationPlayer
        for raw_name: StringName in player.get_animation_list():
            var name := String(raw_name)
            if not name.to_lower().contains("walk"):
                continue
            var animation := player.get_animation(raw_name)
            if animation != null:
                return {
                    "found": true,
                    "name": name,
                    "duration_s": animation.length,
                    "track_count": animation.get_track_count(),
                }
    for child: Node in node.get_children():
        var found := _find_walk_animation(child)
        if bool(found.get("found", false)):
            return found
    return {"found": false, "name": "", "duration_s": 0.0, "track_count": 0}

func _write_result(result: Dictionary) -> void:
    var file := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
    if file == null:
        _failures.append("result_file_open_failed")
        return
    file.store_string(JSON.stringify(result, "  "))
    file.close()

func _finish(_result: Dictionary) -> void:
    if _failures.is_empty():
        print("GATE8_STEVE_GODOT_IMPORT_PREFLIGHT_OK source_bones>=55 source_skin=true walk=true target_bones>=53 retarget=false production_authorized=false")
        quit(0)
        return
    for failure: String in _failures:
        push_error("GATE8_STEVE_GODOT_IMPORT_PREFLIGHT_FAIL %s" % failure)
    quit(1)
