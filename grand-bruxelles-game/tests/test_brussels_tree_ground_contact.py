from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / "game/scripts/brussels_tree_ground_contact_asset.gd"
RUNTIME = ROOT / "game/scripts/brussels_tree_ground_contact_runtime.gd"
PROJECT = ROOT / "project.godot"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"BRUSSELS_TREE_GROUND_CONTACT_FAIL: {message}")


asset = ASSET.read_text(encoding="utf-8") if ASSET.exists() else ""
runtime = RUNTIME.read_text(encoding="utf-8") if RUNTIME.exists() else ""
project = PROJECT.read_text(encoding="utf-8") if PROJECT.exists() else ""

require(asset, "red-first witness: reusable ground-contact asset missing")
require(runtime, "red-first witness: shared ground-contact runtime missing")
require('const GROUND_CONTACT_REVISION := 1' in asset, "ground-contact revision missing")
require('create_ground_contact_mesh' in asset, "reusable ground-contact mesh missing")
require('ground_contact_material' in asset, "reusable ground-contact material missing")
require('GROUND_CONTACT_RADIUS := 0.62' in asset and 'GROUND_CONTACT_HEIGHT := 0.012' in asset, "authored bounded dimensions changed")
require('_ground_batch' in runtime, "shared ground-contact MultiMesh batch missing")
require('set_ground_contact_enabled' in runtime, "ground-contact A/B toggle missing")
require('source_ground_treatment_claimed' in runtime, "source-claim guard missing")
require('source_ground_treatment_claimed", false' in runtime or 'source_ground_treatment_claimed",false' in runtime, "runtime must explicitly refuse sourced ground-treatment claim")
require('geometry_changed_by_tree_ground_contact", false' in runtime or 'geometry_changed_by_tree_ground_contact",false' in runtime, "runtime must preserve source tree geometry truth")
require('EXPECTED_TREE_COUNT := 266' in runtime, "source tree reuse count changed")
require('BrusselsTreeGroundContactRuntime="*res://game/scripts/brussels_tree_ground_contact_runtime.gd"' in project, "ground-contact runtime not mounted")
require('OpenStreetMap contributors via Overpass API' in asset and 'ODbL-1.0' in asset, "OSM provenance missing")

print("BRUSSELS_TREE_GROUND_CONTACT_CONTRACT_OK")
