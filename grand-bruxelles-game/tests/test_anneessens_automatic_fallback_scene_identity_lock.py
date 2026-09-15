#!/usr/bin/env python3
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
RUNTIME = PROJECT / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"
FUNCTION = "func _is_authoritative_production_scene(candidate: Node3D) -> bool:"
CANONICAL = "res://game/main.tscn"
CANONICAL_GUARDS = (
    'if candidate.scene_file_path != "res://game/main.tscn":\n        return false',
    'if candidate.scene_file_path == "res://game/main.tscn":',
)


def main() -> int:
    source = RUNTIME.read_text(encoding="utf-8")
    start = source.find(FUNCTION)
    assert start >= 0, "Anneessens authoritative production-scene predicate missing"
    end = source.find("\nfunc ", start + len(FUNCTION))
    assert end > start, "Anneessens authoritative predicate boundary missing"
    predicate = source[start:end]

    current_guard = "if tree.current_scene == candidate:\n        return true"
    current_index = predicate.find(current_guard)
    assert current_index >= 0, "SceneTree.current_scene authority must remain first-class"

    guard_matches = [(guard, predicate.find(guard)) for guard in CANONICAL_GUARDS]
    guard_matches = [(guard, index) for guard, index in guard_matches if index >= 0]
    assert guard_matches, (
        "automatic fallback must enforce an exact candidate.scene_file_path == "
        f"{CANONICAL!r} guard, not merely mention the path"
    )
    _, path_index = min(guard_matches, key=lambda item: item[1])
    assert current_index < path_index, "packed-scene fallback must not override current_scene authority"

    direct_index = predicate.find("if parent == tree.root:")
    viewport_index = predicate.find("and parent is Viewport")
    assert direct_index >= 0, "direct-root fallback rail missing"
    assert viewport_index >= 0, "Viewport fallback rail missing"
    assert path_index < direct_index, "canonical packed-scene identity must gate direct-root fallback"
    assert path_index < viewport_index, "canonical packed-scene identity must gate Viewport fallback"

    print("ANNEESSENS_AUTOMATIC_FALLBACK_SCENE_IDENTITY_LOCK_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
