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

        self.assertIn('func _apply_material_identity_contract(target: Object) -> void:', text)
        self.assertEqual(text.count('_apply_material_identity_contract(node)'), 1)
        self.assertEqual(text.count('_apply_material_identity_contract(material)'), 1)
        self.assertEqual(text.count('set_meta("material_identity_source_backed", false)'), 1)
        self.assertEqual(text.count('set_meta("material_identity_status", "generic_authored_proxy")'), 1)
        self.assertEqual(text.count('set_meta("material_reuse_scope", "anneessens_proxy_only")'), 1)
        self.assertEqual(text.count('set_meta("brussels_material_family_authorized", false)'), 1)

    def test_node_and_resource_share_one_fail_closed_alignment_contract(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        self.assertIn('func _apply_alignment_contract(target: Object) -> void:', text)
        self.assertEqual(text.count('_apply_alignment_contract(node)'), 1)
        self.assertEqual(text.count('_apply_alignment_contract(material)'), 1)
        self.assertEqual(text.count('set_meta("alignment_reference", ALIGNMENT_REFERENCE)'), 1)
        self.assertEqual(text.count('set_meta("road_alignment_source_backed", false)'), 1)
        self.assertEqual(text.count('set_meta("road_alignment_provenance_status", "unverified_rendered_road")'), 1)

    def test_each_proxy_snapshots_the_rendered_road_alignment_witness(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        # GeneratedRoads is explicitly an unverified alignment reference. Preserve the
        # exact rendered-road state consumed by each proxy so later scene mutations can
        # be audited without pretending the witness is source-backed Brussels truth.
        self.assertIn('pavement.set_meta("alignment_witness_road", road.name)', text)
        self.assertIn('pavement.set_meta("alignment_witness_transform", road.global_transform)', text)
        self.assertIn('pavement.set_meta("alignment_witness_size", road.size)', text)
        self.assertIn('pavement.set_meta("alignment_witness_source_backed", false)', text)

    def test_each_proxy_snapshots_its_derived_placement_recipe(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        # The road witness alone is insufficient to reproduce the authored proxy: the
        # chosen width, side, lateral vector and offset are also inputs to placement.
        # Preserve them without upgrading any value to source-backed Brussels truth.
        self.assertIn('pavement.set_meta("placement_witness_width", width)', text)
        self.assertIn('pavement.set_meta("placement_witness_side", side)', text)
        self.assertIn('pavement.set_meta("placement_witness_lateral", lateral)', text)
        self.assertIn('pavement.set_meta("placement_witness_offset", offset)', text)
        self.assertIn('pavement.set_meta("placement_witness_source_backed", false)', text)

    def test_each_proxy_snapshots_final_rendered_transform_after_assignment(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        position_assignment = 'pavement.global_position = road.global_position + lateral * offset * side + Vector3(0.0, 0.06, 0.0)'
        rotation_assignment = 'pavement.global_rotation = road.global_rotation'
        final_witness = 'pavement.set_meta("placement_witness_global_transform", pavement.global_transform)'
        self.assertIn(position_assignment, text)
        self.assertIn(rotation_assignment, text)
        self.assertIn(final_witness, text)
        self.assertLess(text.index(position_assignment), text.index(final_witness))
        self.assertLess(text.index(rotation_assignment), text.index(final_witness))
        self.assertIn('pavement.set_meta("placement_witness_global_transform_source_backed", false)', text)

    def test_each_proxy_snapshots_final_rendered_dimensions(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        # Placement evidence is incomplete without the exact box dimensions actually
        # rendered. Keep that final result auditable without upgrading authored width,
        # height or road-derived length to source-backed sidewalk truth.
        size_assignment = 'pavement.size = Vector3(width, SIDEWALK_HEIGHT_M, road.size.z)'
        size_witness = 'pavement.set_meta("placement_witness_rendered_size", pavement.size)'
        self.assertIn(size_assignment, text)
        self.assertIn(size_witness, text)
        self.assertLess(text.index(size_assignment), text.index(size_witness))
        self.assertIn('pavement.set_meta("placement_witness_rendered_size_source_backed", false)', text)

    def test_node_and_resource_share_one_proxy_provenance_contract(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        self.assertIn('func _apply_proxy_provenance_contract(target: Object) -> void:', text)
        self.assertEqual(text.count('_apply_proxy_provenance_contract(node)'), 1)
        self.assertEqual(text.count('_apply_proxy_provenance_contract(material)'), 1)
        self.assertEqual(text.count('set_meta("source", PROXY_SOURCE)'), 1)
        self.assertEqual(text.count('set_meta("license", PROXY_LICENSE)'), 1)
        self.assertEqual(text.count('set_meta("presentation_recipe", PROXY_RECIPE)'), 1)

    def test_material_recipe_metadata_matches_rendered_parameters(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        self.assertIn('const PROXY_MATERIAL_REVISION := 1', text)
        self.assertIn('const PROXY_ALBEDO := Color(0.40, 0.385, 0.36, 1.0)', text)
        self.assertIn('const PROXY_ROUGHNESS := 0.92', text)
        self.assertIn('material.albedo_color = PROXY_ALBEDO', text)
        self.assertIn('material.roughness = PROXY_ROUGHNESS', text)
        self.assertIn('material.set_meta("presentation_revision", PROXY_MATERIAL_REVISION)', text)
        self.assertIn('material.set_meta("presentation_albedo", PROXY_ALBEDO)', text)
        self.assertIn('material.set_meta("presentation_roughness", PROXY_ROUGHNESS)', text)
        self.assertIn('material.set_meta("presentation_parameters_source_backed", false)', text)

    def test_shared_material_resource_carries_fail_closed_provenance(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        self.assertIn('func _apply_proxy_material_contract(material: Material) -> void:', text)
        self.assertIn('_apply_proxy_provenance_contract(material)', text)
        self.assertIn('_apply_alignment_contract(material)', text)
        self.assertIn('_apply_material_identity_contract(material)', text)
        self.assertIn('_apply_proxy_material_contract(material)', text)


if __name__ == "__main__":
    unittest.main()
