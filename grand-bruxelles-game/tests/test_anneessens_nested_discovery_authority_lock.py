from pathlib import Path

PROJECT = Path(__file__).resolve().parents[1]
RUNTIME = PROJECT / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"
FIND_NESTED = "func _find_nested_production_scene(node: Node) -> Node3D:"
FIND_PRODUCTION = "\nfunc _find_production_scene() -> Node3D:"
AUTHORITY_CALL = "_is_authoritative_production_scene(node as Node3D)"


def main() -> int:
    text = RUNTIME.read_text(encoding="utf-8")
    start = text.find(FIND_NESTED)
    assert start >= 0, "Anneessens nested production discovery function missing"
    end = text.find(FIND_PRODUCTION, start)
    assert end > start, "Anneessens nested discovery boundary missing"
    nested = text[start:end]

    # Automatic recursive discovery must have one authority choke point. Once the
    # packed-scene identity guard is fixed there, no direct-root or Viewport walk may
    # bypass it and return a production-looking Main on name/anchors alone.
    assert AUTHORITY_CALL in nested, "nested discovery bypasses authoritative production-scene predicate"
    assert nested.count("return node as Node3D") == 1, "nested discovery gained an unguarded direct return rail"
    guarded_return = nested.find("return node as Node3D")
    authority = nested.find(AUTHORITY_CALL)
    assert 0 <= authority < guarded_return, "nested discovery returns candidate before authority validation"

    assert 'node.name' not in nested and '"Main"' not in nested, (
        "nested discovery must not duplicate name-based production authority outside the canonical predicate"
    )
    assert "scene_file_path" not in nested, (
        "packed-scene identity belongs in the single authoritative predicate, not duplicated in recursion"
    )

    print("ANNEESSENS_NESTED_DISCOVERY_AUTHORITY_LOCK_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
