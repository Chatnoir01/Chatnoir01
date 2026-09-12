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
    var parent := candidate.get_parent()
    if parent == tree.root:
        return str(candidate.name) == "Main"
    return (
        str(candidate.name) == "Main"
        and parent is Viewport
        and parent.get_parent() == tree.root
    )
