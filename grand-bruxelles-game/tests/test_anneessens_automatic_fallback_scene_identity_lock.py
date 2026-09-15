#!/usr/bin/env python3
from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
RUNTIME = PROJECT / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"
FUNCTION = "func _is_authoritative_production_scene(candidate: Node3D) -> bool:"
CANONICAL = 'res://game/main.tscn'


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

    path_index = predicate.find("candidate.scene_file_path")
    assert path_index >= 0, "automatic fallback must inspect candidate.scene_file_path"
    assert CANONICAL in predicate, "automatic fallback must bind to canonical packed main.tscn"
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
