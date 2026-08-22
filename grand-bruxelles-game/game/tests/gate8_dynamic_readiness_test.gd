extends SceneTree

const SURVIVOR_VARIANTS: Array[int] = [1, 3, 5, 6, 8]
const REJECTED_VARIANTS: Array[int] = [2, 4, 7]
const GATE8_ROOT := "res://game/assets/characters/civilians/gate8"
const BANNED_PLAYER_ASSET := "res://assets/characters/player_character.glb"
const REQUIRED_STATES: Array[String] = ["idle", "walk", "run"]

var _problems: Array[String] = []

func _init() -> void:
    call_deferred("_run")

func _run() -> void:
    var initial_root_children := root.get_child_count()
    if initial_root_children != 0:
        _problems.append("autoload_contamination root_children=%d expected=0" % initial_root_children)

    _run_integrity_regressions()

    var ready_count := 0
    var blocked_count := 0
    var total_skeletons := 0
    var total_skinned_meshes := 0
    var total_skinned_surfaces := 0
    var total_materials := 0
    var total_vertices := 0
    var total_animation_players := 0
    var total_animations := 0
    var foot_bone_candidates := 0
    var total_invalid_skeleton_links := 0
    var total_missing_material_surfaces := 0

    for rejected_index: int in REJECTED_VARIANTS:
        if rejected_index in SURVIVOR_VARIANTS:
            _problems.append("rejected_variant_leaked_into_survivor_pool=%02d" % rejected_index)

    for variant_index: int in SURVIVOR_VARIANTS:
        var path := "%s/npc_gate_%02d.glb" % [GATE8_ROOT, variant_index]
        if path == BANNED_PLAYER_ASSET or path.begins_with("res://assets/characters/player/"):
            _problems.append("variant=%02d player_character_reuse_forbidden" % variant_index)
            continue
        if not ResourceLoader.exists(path):
            _problems.append("variant=%02d missing_ephemeral_glb=%s" % [variant_index, path])
            continue
        var packed := load(path) as PackedScene
        if packed == null:
            _problems.append("variant=%02d load_failed" % variant_index)
            continue
        var character := packed.instantiate() as Node3D
        if character == null:
            _problems.append("variant=%02d instantiate_failed" % variant_index)
            continue
        root.add_child(character)
        await process_frame

        var integrity := _inspect_integrity(character)
        var skeleton_count := int(integrity.get("skeleton_count", 0))
        var skinned_mesh_count := int(integrity.get("skinned_mesh_count", 0))
        var skinned_surface_count := int(integrity.get("skinned_surface_count", 0))
        var material_count := int(integrity.get("material_count", 0))
        var vertex_count := int(integrity.get("vertex_count", 0))
        var animation_player_count := int(integrity.get("animation_player_count", 0))
        var animation_count := int(integrity.get("animation_count", 0))
        var foot_bones := int(integrity.get("foot_bone_count", 0))
        var invalid_skeleton_links := int(integrity.get("invalid_skeleton_links", 0))
        var missing_material_surfaces := int(integrity.get("missing_material_surfaces", 0))
        var locomotion := integrity.get("locomotion", {}) as Dictionary
        var locomotion_ready := _locomotion_complete(locomotion)

        total_skeletons += skeleton_count
        total_skinned_meshes += skinned_mesh_count
        total_skinned_surfaces += skinned_surface_count
        total_materials += material_count
        total_vertices += vertex_count
        total_animation_players += animation_player_count
        total_animations += animation_count
        foot_bone_candidates += foot_bones
        total_invalid_skeleton_links += invalid_skeleton_links
        total_missing_material_surfaces += missing_material_surfaces

        if skeleton_count < 1:
            _problems.append("variant=%02d missing_skeleton" % variant_index)
        if skinned_mesh_count < 1:
            _problems.append("variant=%02d missing_skinned_mesh" % variant_index)
        if skinned_surface_count < 1:
            _problems.append("variant=%02d missing_skinned_surface" % variant_index)
        if material_count < 1:
            _problems.append("variant=%02d missing_material" % variant_index)
        if vertex_count < 1:
            _problems.append("variant=%02d missing_vertices" % variant_index)
        if invalid_skeleton_links != 0:
            _problems.append("variant=%02d invalid_skeleton_links=%d expected=0" % [variant_index, invalid_skeleton_links])
        if missing_material_surfaces != 0:
            _problems.append("variant=%02d missing_material_surfaces=%d expected=0" % [variant_index, missing_material_surfaces])

        if locomotion_ready:
            ready_count += 1
            _problems.append("variant=%02d unexpected_unproven_idle_walk_run=%s" % [variant_index, JSON.stringify(locomotion)])
        else:
            blocked_count += 1

        print("GATE8_DYNAMIC_VARIANT variant=%02d skeletons=%d skinned_meshes=%d skinned_surfaces=%d materials=%d vertices=%d invalid_skeleton_links=%d missing_material_surfaces=%d animation_players=%d animations=%d foot_bones=%d idle=%s walk=%s run=%s locomotion_ready=%s" % [
            variant_index,
            skeleton_count,
            skinned_mesh_count,
            skinned_surface_count,
            material_count,
            vertex_count,
            invalid_skeleton_links,
            missing_material_surfaces,
            animation_player_count,
            animation_count,
            foot_bones,
            str(locomotion.get("idle", "")),
            str(locomotion.get("walk", "")),
            str(locomotion.get("run", "")),
            str(locomotion_ready),
        ])
        character.queue_free()
        await process_frame

    if ready_count != 0:
        _problems.append("unproven_dynamic_ready_count=%d expected=0" % ready_count)
    if blocked_count != SURVIVOR_VARIANTS.size():
        _problems.append("blocked_survivors=%d expected=%d" % [blocked_count, SURVIVOR_VARIANTS.size()])
    if total_invalid_skeleton_links != 0:
        _problems.append("aggregate_invalid_skeleton_links=%d expected=0" % total_invalid_skeleton_links)
    if total_missing_material_surfaces != 0:
        _problems.append("aggregate_missing_material_surfaces=%d expected=0" % total_missing_material_surfaces)
    if root.get_child_count() != 0:
        _problems.append("post_test_root_contamination root_children=%d expected=0" % root.get_child_count())

    if not _problems.is_empty():
        print("GATE8_DYNAMIC_PREFLIGHT_FAIL")
        for problem: String in _problems:
            print("- ", problem)
        quit(1)
        return

    print("GATE8_DYNAMIC_PREFLIGHT_OK candidates=%d rejected_excluded=%d locomotion_ready=%d blocked=%d skeletons=%d skinned_meshes=%d skinned_surfaces=%d materials=%d vertices=%d invalid_skeleton_links=%d missing_material_surfaces=%d animation_players=%d animations=%d foot_bones=%d player_asset_reused=false animation_retargeted=false production_activation=false autoload_isolated=true skin_links_resolved=true skinned_surface_materials_complete=true" % [
        SURVIVOR_VARIANTS.size(),
        REJECTED_VARIANTS.size(),
        ready_count,
        blocked_count,
        total_skeletons,
        total_skinned_meshes,
        total_skinned_surfaces,
        total_materials,
        total_vertices,
        total_invalid_skeleton_links,
        total_missing_material_surfaces,
        total_animation_players,
        total_animations,
        foot_bone_candidates,
    ])
    quit(0)

func _run_integrity_regressions() -> void:
    var broken_root := Node3D.new()
    var broken_mesh := MeshInstance3D.new()
    broken_mesh.name = "BrokenSkinnedMesh"
    broken_mesh.mesh = BoxMesh.new()
    broken_mesh.skin = Skin.new()
    broken_mesh.skeleton = NodePath("../MissingSkeleton")
    broken_root.add_child(broken_mesh)
    var broken := _inspect_integrity(broken_root)
    if int(broken.get("invalid_skeleton_links", 0)) != 1:
        _problems.append("regression_invalid_skeleton_link_not_detected")
    if int(broken.get("missing_material_surfaces", 0)) < 1:
        _problems.append("regression_missing_skinned_material_not_detected")
    broken_root.free()

    var valid_root := Node3D.new()
    var valid_skeleton := Skeleton3D.new()
    valid_skeleton.name = "Skeleton3D"
    valid_root.add_child(valid_skeleton)
    var valid_mesh := MeshInstance3D.new()
    valid_mesh.name = "ValidSkinnedMesh"
    valid_mesh.mesh = BoxMesh.new()
    valid_mesh.skin = Skin.new()
    valid_mesh.skeleton = NodePath("../Skeleton3D")
    valid_mesh.set_surface_override_material(0, StandardMaterial3D.new())
    valid_root.add_child(valid_mesh)
    var valid := _inspect_integrity(valid_root)
    if int(valid.get("invalid_skeleton_links", 0)) != 0:
        _problems.append("regression_valid_skeleton_link_rejected")
    if int(valid.get("missing_material_surfaces", 0)) != 0:
        _problems.append("regression_valid_skinned_material_rejected")
    valid_root.free()

func _inspect_integrity(character: Node3D) -> Dictionary:
    var skeleton_count := 0
    var skinned_mesh_count := 0
    var skinned_surface_count := 0
    var material_count := 0
    var vertex_count := 0
    var animation_player_count := 0
    var animation_count := 0
    var foot_bone_count := 0
    var invalid_skeleton_links := 0
    var missing_material_surfaces := 0
    var locomotion := {"idle": "", "walk": "", "run": ""}

    for raw_skeleton: Node in character.find_children("*", "Skeleton3D", true, false):
        var skeleton := raw_skeleton as Skeleton3D
        if skeleton == null:
            continue
        skeleton_count += 1
        for bone_index: int in range(skeleton.get_bone_count()):
            var bone_name := skeleton.get_bone_name(bone_index).to_lower()
            if "foot" in bone_name or "ankle" in bone_name or "toe" in bone_name:
                foot_bone_count += 1

    for raw_mesh: Node in character.find_children("*", "MeshInstance3D", true, false):
        var mesh_instance := raw_mesh as MeshInstance3D
        if mesh_instance == null or mesh_instance.mesh == null:
            continue
        var claims_skinning := mesh_instance.skin != null or not mesh_instance.skeleton.is_empty()
        if claims_skinning:
            skinned_mesh_count += 1
            if mesh_instance.skeleton.is_empty():
                invalid_skeleton_links += 1
            else:
                var linked_skeleton := mesh_instance.get_node_or_null(mesh_instance.skeleton)
                if not linked_skeleton is Skeleton3D:
                    invalid_skeleton_links += 1
        for surface_index: int in range(mesh_instance.mesh.get_surface_count()):
            var material := mesh_instance.get_surface_override_material(surface_index)
            if material == null:
                material = mesh_instance.mesh.surface_get_material(surface_index)
            if material != null:
                material_count += 1
            if claims_skinning:
                skinned_surface_count += 1
                if material == null:
                    missing_material_surfaces += 1
            var arrays := mesh_instance.mesh.surface_get_arrays(surface_index)
            if arrays.size() > Mesh.ARRAY_VERTEX:
                var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
                vertex_count += vertices.size()

    for raw_player: Node in character.find_children("*", "AnimationPlayer", true, false):
        var animation_player := raw_player as AnimationPlayer
        if animation_player == null:
            continue
        animation_player_count += 1
        var names := animation_player.get_animation_list()
        animation_count += names.size()
        for animation_name: String in names:
            if animation_name == "RESET":
                continue
            var normalized := _normalize_animation_name(animation_name)
            for state: String in REQUIRED_STATES:
                if String(locomotion.get(state, "")).is_empty() and _has_exact_token(normalized, state):
                    locomotion[state] = animation_name

    return {
        "skeleton_count": skeleton_count,
        "skinned_mesh_count": skinned_mesh_count,
        "skinned_surface_count": skinned_surface_count,
        "material_count": material_count,
        "vertex_count": vertex_count,
        "animation_player_count": animation_player_count,
        "animation_count": animation_count,
        "foot_bone_count": foot_bone_count,
        "invalid_skeleton_links": invalid_skeleton_links,
        "missing_material_surfaces": missing_material_surfaces,
        "locomotion": locomotion,
    }

func _locomotion_complete(locomotion: Dictionary) -> bool:
    for state: String in REQUIRED_STATES:
        if String(locomotion.get(state, "")).is_empty():
            return false
    return true

func _normalize_animation_name(animation_name: String) -> String:
    return animation_name.to_lower().replace("-", "_").replace(" ", "_").replace(".", "_").replace("/", "_").replace(":", "_")

func _has_exact_token(normalized_name: String, token: String) -> bool:
    for part: String in normalized_name.split("_", false):
        if part == token:
            return true
    return false
