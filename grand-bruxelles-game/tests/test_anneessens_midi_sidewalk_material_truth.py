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
        self.assertIn('target.set_meta("material_identity_source_backed", false)', text)
        self.assertIn('target.set_meta("material_identity_status", "generic_authored_proxy")', text)
        self.assertIn('target.set_meta("material_reuse_scope", "anneessens_proxy_only")', text)
        self.assertIn('target.set_meta("brussels_material_family_authorized", false)', text)

        self.assertNotIn('material_identity_source_backed", true', text)
        self.assertNotIn('brussels_material_family_authorized", true', text)

    def test_node_and_resource_share_one_fail_closed_material_identity_contract(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        # The same material-identity truth must be applied to both generated nodes and
        # the shared StandardMaterial3D resource. Duplicated literal blocks can drift
        # independently and create contradictory provenance depending on which object
        # a downstream consumer retains.
        self.assertIn('func _apply_material_identity_contract(target: Object) -> void:', text)
        self.assertEqual(text.count('_apply_material_identity_contract(node)'), 1)
        self.assertEqual(text.count('_apply_material_identity_contract(material)'), 1)
        self.assertEqual(text.count('set_meta("material_identity_source_backed", false)'), 1)
        self.assertEqual(text.count('set_meta("material_identity_status", "generic_authored_proxy")'), 1)
        self.assertEqual(text.count('set_meta("material_reuse_scope", "anneessens_proxy_only")'), 1)
        self.assertEqual(text.count('set_meta("brussels_material_family_authorized", false)'), 1)

    def test_shared_material_resource_carries_fail_closed_provenance(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        self.assertIn('func _apply_proxy_material_contract(material: Material) -> void:', text)
        self.assertIn('material.set_meta("source", PROXY_SOURCE)', text)
        self.assertIn('material.set_meta("license", PROXY_LICENSE)', text)
        self.assertIn('material.set_meta("presentation_recipe", PROXY_RECIPE)', text)
        self.assertIn('material.set_meta("alignment_reference", ALIGNMENT_REFERENCE)', text)
        self.assertIn('material.set_meta("road_alignment_source_backed", false)', text)
        self.assertIn('material.set_meta("road_alignment_provenance_status", "unverified_rendered_road")', text)
        self.assertIn('_apply_material_identity_contract(material)', text)
        self.assertIn('_apply_proxy_material_contract(material)', text)


if __name__ == "__main__":
    unittest.main()
