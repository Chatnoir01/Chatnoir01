from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkMaterialTruthTest(unittest.TestCase):
    def test_authored_proxy_material_cannot_claim_brussels_identity(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        # The current sidewalk is an authored visual proxy aligned to rendered roads.
        # Until an exact Brussels pavement source/material is registered, its material
        # must stay explicitly generic and non-source-backed rather than silently
        # becoming a reusable Brussels material family.
        self.assertIn('const PROXY_SOURCE := "authored_proxy"', text)
        self.assertIn('node.set_meta("material_identity_source_backed", false)', text)
        self.assertIn('node.set_meta("material_identity_status", "generic_authored_proxy")', text)
        self.assertIn('node.set_meta("material_reuse_scope", "anneessens_proxy_only")', text)
        self.assertIn('node.set_meta("brussels_material_family_authorized", false)', text)

        self.assertNotIn('material_identity_source_backed", true', text)
        self.assertNotIn('brussels_material_family_authorized", true', text)

    def test_shared_material_resource_carries_fail_closed_provenance(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        # Node metadata alone is insufficient: the StandardMaterial3D is shared by
        # every generated pavement and can be passed around independently of its
        # owning CSG node. Keep the provenance boundary attached to the Resource too.
        self.assertIn('func _apply_proxy_material_contract(material: Material) -> void:', text)
        self.assertIn('material.set_meta("source", PROXY_SOURCE)', text)
        self.assertIn('material.set_meta("license", PROXY_LICENSE)', text)
        self.assertIn('material.set_meta("material_identity_source_backed", false)', text)
        self.assertIn('material.set_meta("material_identity_status", "generic_authored_proxy")', text)
        self.assertIn('material.set_meta("material_reuse_scope", "anneessens_proxy_only")', text)
        self.assertIn('material.set_meta("brussels_material_family_authorized", false)', text)
        self.assertIn('_apply_proxy_material_contract(material)', text)


if __name__ == "__main__":
    unittest.main()
