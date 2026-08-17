from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OWNER = ROOT / "game/scripts/corridor_facade_depth_runtime.gd"
HELPER = ROOT / "game/scripts/brussels_corridor_generic_glazing_material.gd"
PROJECT = ROOT / "project.godot"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def main() -> None:
    owner = OWNER.read_text(encoding="utf-8")
    project = PROJECT.read_text(encoding="utf-8")

    # Existing production owner remains the only runtime owner for these meshes.
    require("CorridorWindowGlass" in owner, "corridor window owner missing")
    require("CorridorShopfrontGlass" in owner, "corridor shopfront owner missing")
    require("WINDOW_GLASS_PALETTE" in owner and "SHOP_GLASS_PALETTE" in owner, "baseline glass families missing")

    # RED-first: this helper/family does not exist on production yet.
    require(HELPER.exists(), "reusable generic glazing material helper missing")
    helper = HELPER.read_text(encoding="utf-8")
    require("brussels_corridor_generic_glazing_v1" in helper, "family id missing")
    require("geometry_changed" in helper and "false" in helper, "geometry invariance claim missing")
    require("material_identity_claimed" in helper and "false" in helper, "material identity must remain unclaimed")
    require("exact_rgb_is_photometric_measurement" in helper and "false" in helper, "measured RGB must remain unclaimed")
    require("OpenStreetMap" in helper and "ODbL-1.0" in helper, "OSM provenance boundary missing")

    # The existing owner must consume the helper without adding a parallel autoload/runtime.
    require("BrusselsCorridorGenericGlazingMaterial" in owner, "existing corridor owner does not consume helper")
    require("BrusselsCorridorGenericGlazing" not in project, "generic glazing must not become a parallel autoload")

    # Preserve the existing batching families: five window groups and four shop groups.
    require("WINDOW_GLASS_PALETTE.size()" in owner, "window batching loop removed")
    require("SHOP_GLASS_PALETTE.size()" in owner, "shop batching loop removed")

    print("CORRIDOR_GENERIC_GLAZING_MATERIAL_OK")


if __name__ == "__main__":
    main()
