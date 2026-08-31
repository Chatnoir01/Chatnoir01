from pathlib import Path

RUNTIME = Path("grand-bruxelles-game/game/scripts/anneessens_osm_furniture_runtime.gd")
OWNER_KEY = "shared_environment_visual_owner"
OWNER_VALUE = "anneessens_osm_furniture_runtime"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"TREE_VISUAL_OWNERSHIP_FAIL: {message}")


def main() -> None:
    text = RUNTIME.read_text(encoding="utf-8")
    require(f'const VISUAL_OWNER_META := "{OWNER_KEY}"' in text, "owner metadata key is not declared")
    require(f'const VISUAL_OWNER_ID := "{OWNER_VALUE}"' in text, "owner identity is not declared")
    require("func _is_owned_tree_visual(node: Node) -> bool:" in text, "owned-visual predicate is missing")
    require('str(node.get_meta(VISUAL_OWNER_META, "")) == VISUAL_OWNER_ID' in text, "owned-visual predicate is not identity based")
    require("func _mark_owned_tree_visual(node: Node) -> void:" in text, "owned-visual marker is missing")
    require("node.set_meta(VISUAL_OWNER_META, VISUAL_OWNER_ID)" in text, "visual nodes are not marked with the exact owner")
    require("if existing != null and _is_owned_tree_visual(existing):" in text, "cleanup is not fail-closed on owner identity")
    require("_mark_owned_tree_visual(legacy)" in text, "legacy visual is not marked before ownership-sensitive teardown")
    require("TREE_ASSET.populate(tree, osm_id, _tree_materials)" in text, "enhanced Brussels tree population was removed")
    require("geometry_changed" not in text.lower(), "test scope must not manufacture geometry semantics")
    print("SHARED_ENVIRONMENT_TREE_VISUAL_OWNERSHIP_OK: exact_owner_cleanup=locked foreign_same_name=preserved normal_tree_population=preserved")


if __name__ == "__main__":
    main()
