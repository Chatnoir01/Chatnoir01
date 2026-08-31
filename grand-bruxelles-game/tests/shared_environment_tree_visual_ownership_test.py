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
    require("func _remove_owned_tree_visuals(tree: StaticBody3D) -> void:" in text, "owner-scoped cleanup helper is missing")
    require("for child: Node in tree.get_children():" in text, "cleanup does not enumerate actual children")
    require("if not _is_owned_tree_visual(child):" in text, "cleanup is not fail-closed on owner identity")
    require("_remove_owned_tree_visuals(tree)" in text, "tree rebuild does not use owner-scoped cleanup")
    require("var enhanced_visual := TREE_ASSET.populate(tree, osm_id, _tree_materials)" in text, "enhanced Brussels tree population is not captured for ownership")
    require("_mark_owned_tree_visual(enhanced_visual)" in text, "enhanced visual is not owner-marked")
    require("_mark_owned_tree_visual(legacy)" in text, "legacy visual is not owner-marked")
    require("tree.get_node_or_null(child_name)" not in text, "name-only destructive lookup remains in tree visual rebuild")
    print("SHARED_ENVIRONMENT_TREE_VISUAL_OWNERSHIP_OK: exact_owner_cleanup=locked foreign_same_name=preserved enhanced_and_legacy=owned")


if __name__ == "__main__":
    main()
