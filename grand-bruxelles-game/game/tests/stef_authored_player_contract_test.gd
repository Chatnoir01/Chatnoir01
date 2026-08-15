extends SceneTree

const STEF_PATH := "res://assets/characters/player_character.glb"
const WARMUP_FRAMES := 30


func _initialize() -> void:
    call_deferred("_run")


func _fail(message: String) -> void:
    push_error("STEF_AUTHORED_PLAYER_CONTRACT_FAIL: %s" % message)
    quit(1)


func _descendants(root_node: Node) -> Array[Node]:
    var out: Array[Node] = []
    var queue: Array[Node] = [root_node]
    while not queue.is_empty():
        var node: Node = queue.pop_front()
        out.append(node)
        for child: Node in node.get_children():
            queue.append(child)
    return out


func _find_walk_animation(players: Array[AnimationPlayer]) -> Dictionary:
    for player: AnimationPlayer in players:
        for name: StringName in player.get_animation_list():
            if String(name).to_lower().contains("walk"):
                return {"player": player, "name": name}
    return {}


func _snapshot_skeletons(skeletons: Array[Skeleton3D]) -> Array:
    var snapshot: Array = []
    for skeleton: Skeleton3D in skeletons:
        var bones: Array = []
        for bone_idx: int in range(skeleton.get_bone_count()):
            bones.append({
                "position": skeleton.get_bone_pose_position(bone_idx),
                "rotation": skeleton.get_bone_pose_rotation(bone_idx),
            })
        snapshot.append(bones)
    return snapshot


func _count_changed_bones(skeletons: Array[Skeleton3D], before: Array) -> int:
    var changed := 0
    for skeleton_idx: int in range(skeletons.size()):
        var skeleton := skeletons[skeleton_idx]
        var bones_before: Array = before[skeleton_idx]
        for bone_idx: int in range(mini(skeleton.get_bone_count(), bones_before.size())):
            var old: Dictionary = bones_before[bone_idx]
            var pos_delta: float = skeleton.get_bone_pose_position(bone_idx).distance_to(old["position"])
            var rot_delta: float = skeleton.get_bone_pose_rotation(bone_idx).angle_to(old["rotation"])
            if pos_delta > 0.0001 or rot_delta > 0.0001:
                changed += 1
    return changed


func _run() -> void:
    if not ResourceLoader.exists(STEF_PATH):
        _fail("production Stef GLB is missing")
        return

    var packed := load("res://game/main.tscn") as PackedScene
    if packed == null:
        _fail("main scene did not load")
        return
    var scene := packed.instantiate()
    root.add_child(scene)

    for _frame: int in range(WARMUP_FRAMES):
        await process_frame

    var visual := scene.get_node_or_null("Player/VisualUpgrade") as Node3D
    if visual == null:
        _fail("Player/VisualUpgrade missing")
        return
    if not bool(visual.call("is_using_authored_character")):
        _fail("Player did not select authored character")
        return
    var resolved := String(visual.call("resolved_authored_scene_path"))
    if resolved != STEF_PATH:
        _fail("Player resolved %s instead of %s" % [resolved, STEF_PATH])
        return

    var authored := visual.get_node_or_null("AuthoredCharacter")
    if authored == null:
        _fail("AuthoredCharacter instance missing")
        return

    var skeletons: Array[Skeleton3D] = []
    var animation_players: Array[AnimationPlayer] = []
    var mesh_count := 0
    var skinned_mesh_count := 0
    var material_surface_count := 0
    for node: Node in _descendants(authored):
        if node is Skeleton3D:
            skeletons.append(node as Skeleton3D)
        elif node is AnimationPlayer:
            animation_players.append(node as AnimationPlayer)
        elif node is MeshInstance3D:
            var mesh_instance := node as MeshInstance3D
            mesh_count += 1
            if mesh_instance.skin != null or not mesh_instance.skeleton.is_empty():
                skinned_mesh_count += 1
            if mesh_instance.mesh != null:
                for surface_idx: int in range(mesh_instance.mesh.get_surface_count()):
                    if mesh_instance.get_active_material(surface_idx) != null:
                        material_surface_count += 1

    if skeletons.is_empty():
        _fail("authored asset contains no Skeleton3D")
        return
    var bone_count := 0
    for skeleton: Skeleton3D in skeletons:
        bone_count += skeleton.get_bone_count()
    if bone_count < 20:
        _fail("unexpectedly small rig: %d bones" % bone_count)
        return
    if mesh_count <= 0 or skinned_mesh_count <= 0:
        _fail("authored asset has no skinned MeshInstance3D")
        return
    if material_surface_count <= 0:
        _fail("authored asset exposes no material-bound surfaces")
        return
    if animation_players.is_empty():
        _fail("authored asset contains no AnimationPlayer")
        return

    var walk := _find_walk_animation(animation_players)
    if walk.is_empty():
        _fail("authored asset exposes no walk animation")
        return
    var animation_player := walk["player"] as AnimationPlayer
    var walk_name := walk["name"] as StringName
    var pose_before := _snapshot_skeletons(skeletons)
    animation_player.play(walk_name)
    for _frame: int in range(20):
        await process_frame
    if not animation_player.is_playing():
        _fail("walk animation did not enter playing state")
        return
    var changed_bones := _count_changed_bones(skeletons, pose_before)
    if changed_bones <= 0:
        _fail("walk animation plays but changes no skeleton pose")
        return

    print("STEF_AUTHORED_PLAYER_CONTRACT_OK: path=%s skeletons=%d bones=%d meshes=%d skinned=%d material_surfaces=%d animation_players=%d walk=%s changed_bones=%d" % [
        resolved,
        skeletons.size(),
        bone_count,
        mesh_count,
        skinned_mesh_count,
        material_surface_count,
        animation_players.size(),
        String(walk_name),
        changed_bones,
    ])
    scene.queue_free()
    quit(0)
