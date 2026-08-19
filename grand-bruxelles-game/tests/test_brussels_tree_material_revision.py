from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSET = ROOT / "game/scripts/brussels_street_tree_asset.gd"
RUNTIME = ROOT / "game/scripts/brussels_corridor_tree_runtime.gd"

asset = ASSET.read_text(encoding="utf-8")
runtime = RUNTIME.read_text(encoding="utf-8")

assert 'const MATERIAL_REVISION := 2' in asset, "BRUSSELS_TREE_MATERIAL_FAIL: reusable tree material revision missing"
assert 'ShaderMaterial' in asset, "BRUSSELS_TREE_MATERIAL_FAIL: foliage/trunk still use flat StandardMaterial3D only"
assert 'authored_presentation_not_source_measurement' in asset
assert 'species_claimed' in asset and 'source_dimensions_measured' in asset
assert 'set_material_enhanced_enabled' in runtime, "BRUSSELS_TREE_MATERIAL_FAIL: runtime A/B material toggle missing"
assert 'source_positions_unchanged' in runtime

print("BRUSSELS_TREE_MATERIAL_CONTRACT_OK")
