from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
RUNTIME = PROJECT / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"
FUNCTION = "func _is_authoritative_production_scene(candidate: Node3D) -> bool:"
NEXT_FUNCTION = "\nfunc _find_nested_production_scene"
CANONICAL = 'res://game/main.tscn'


def main() -> int:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.find(FUNCTION)
    assert start >= 0, "Anneessens authoritative production-scene predicate missing"
    end = text.find(NEXT_FUNCTION, start)
    assert end > start, "Anneessens authoritative predicate boundary missing"
    predicate = text[start:end]

    current_guard = "if tree.current_scene == candidate:\n        return true"
    current_index = predicate.find(current_guard)
    assert current_index >= 0, "SceneTree.current_scene authority must remain first-class"

    fail_closed_guard = 'if candidate.scene_file_path != "res://game/main.tscn":\n        return false'
    positive_guard = 'if candidate.scene_file_path == "res://game/main.tscn":'
    guard_indexes = [index for index in (predicate.find(fail_closed_guard), predicate.find(positive_guard)) if index >= 0]
    assert guard_indexes, f"canonical automatic fallback must explicitly accept only {CANONICAL}"
    path_index = min(guard_indexes)
    assert current_index < path_index, "canonical path guard must not override current_scene authority"

    direct_index = predicate.find("if parent == tree.root:")
    viewport_index = predicate.find("parent is Viewport")
    assert direct_index > path_index, "canonical path identity must be established before direct-root fallback"
    assert viewport_index > path_index, "canonical path identity must be established before Viewport fallback"

    assert 'str(candidate.name) == "Main"' in predicate, "canonical fallback must retain Main-name topology check"
    print("ANNEESSENS_CANONICAL_FALLBACK_PRESERVATION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
