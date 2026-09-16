extends "res://game/scripts/anneessens_osm_furniture_runtime.gd"

const PRODUCTION_MAIN_SCENE_PATH := "res://game/main.tscn"

func _is_canonical_packed_main(candidate: Node3D) -> bool:
    return candidate != null and str(candidate.scene_file_path) == PRODUCTION_MAIN_SCENE_PATH

func _is_authoritative_production_scene(candidate: Node3D) -> bool:
    if candidate == null or not _is_production_scene(candidate) or not is_inside_tree():
        return false
    var tree: SceneTree = get_tree()
    if tree == null:
        return false
    if tree.current_scene == candidate:
        return true
    if not _is_canonical_packed_main(candidate):
        return false
    return candidate.get_parent() == tree.root and str(candidate.name) == "Main"

func _sync_build_and_activation() -> void:
    if _tearing_down or not is_instance_valid(_scene):
        return

    # Main/Player is the sole authority at the point where player coordinates are
    # consumed. A cached Player that was reparented elsewhere can remain valid and
    # inside the SceneTree, so validity/liveness alone must never preserve ownership.
    var canonical_player := _scene.get_node_or_null("Player") as Node3D
    if canonical_player == null or not canonical_player.is_inside_tree():
        _player = null
        _apply_tree_activation(false)
        return
    _player = canonical_player

    var activation_radius_value: Variant = _validated_activation_radius_m()
    if activation_radius_value == null:
        _apply_tree_activation(false)
        return
    var player_position := canonical_player.global_position
    var active := Vector2(player_position.x - ANNEESSENS.x, player_position.z - ANNEESSENS.z).length() <= float(activation_radius_value)
    if active and not is_instance_valid(_root):
        _build_once()
    if is_instance_valid(_root):
        _apply_tree_activation(active)
    else:
        _tree_active = false
        _tree_activation_initialized = false

func _process(_delta: float) -> void:
    if _tearing_down or not is_inside_tree():
        return
    if not is_instance_valid(_scene):
        _reset()
        _start_watching()
        call_deferred("_try_bind")
        return
    if is_instance_valid(_root) and _root.get_parent() != _scene:
        _release_owned_root()

    # Do not maintain a second Player authority here. The consumer reconciles the
    # canonical path and liveness immediately before reading global_position.
    _sync_build_and_activation()
