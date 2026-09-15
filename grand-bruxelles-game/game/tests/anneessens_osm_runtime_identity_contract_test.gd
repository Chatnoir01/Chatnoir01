extends SceneTree

const RUNTIME_PATH := "res://game/scripts/anneessens_osm_furniture_runtime.gd"
const CANONICAL_SCENE_PATH := "res://game/main.tscn"

func _initialize() -> void:
    var source := FileAccess.get_file_as_string(RUNTIME_PATH)
    if source.is_empty():
        _fail("runtime source unavailable")
        return

    var function_start := source.find("func _is_authoritative_production_scene(candidate: Node3D) -> bool:")
    var function_end := source.find("\nfunc ", function_start + 1)
    if function_start < 0 or function_end < 0:
        _fail("authoritative production-scene predicate unavailable")
        return
    var predicate := source.substr(function_start, function_end - function_start)

    var current_scene_guard := "if tree.current_scene == candidate:\n        return true"
    var current_scene_index := predicate.find(current_scene_guard)
    var path_index := predicate.find("candidate.scene_file_path")
    if current_scene_index < 0:
        _fail("SceneTree.current_scene authority was not preserved")
        return
    if path_index < 0 or CANONICAL_SCENE_PATH not in predicate:
        _fail("automatic fallback is not bound to canonical packed-scene identity")
        return
    if current_scene_index > path_index:
        _fail("packed-scene fallback check incorrectly overrides current_scene authority")
        return

    if "str(candidate.name) == \"Main\"" in predicate and path_index < 0:
        _fail("node-name-only Main fallback remains authorized")
        return

    print("ANNEESSENS_OSM_RUNTIME_IDENTITY_CONTRACT_OK: current_scene_first=true canonical_fallback=true")
    quit(0)

func _fail(message: String) -> void:
    push_error("ANNEESSENS_OSM_RUNTIME_IDENTITY_CONTRACT_FAIL: %s" % message)
    quit(1)
