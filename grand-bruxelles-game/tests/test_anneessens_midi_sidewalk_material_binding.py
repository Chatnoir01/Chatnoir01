from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_midi_sidewalk_runtime.gd"


class AnneessensMidiSidewalkMaterialBindingTest(unittest.TestCase):
    def test_rendered_proxies_bind_the_single_audited_material_resource(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")

        # The current Anneessens sidewalk is explicitly an authored proxy, not a
        # source-backed Brussels pavement material.  Its visible material must therefore
        # be the exact resource whose provenance/presentation metadata was audited.
        create = "var material := StandardMaterial3D.new()"
        albedo = "material.albedo_color = PROXY_ALBEDO"
        roughness = "material.roughness = PROXY_ROUGHNESS"
        contract = "_apply_proxy_material_contract(material)"
        build = "_add_sidewalk_pair(road, material)"
        bind = "pavement.material = material"

        for token in (create, albedo, roughness, contract, build, bind):
            self.assertIn(token, text)

        self.assertEqual(text.count(create), 1)
        self.assertEqual(text.count(contract), 1)
        self.assertEqual(text.count(bind), 1)
        self.assertLess(text.index(create), text.index(albedo))
        self.assertLess(text.index(albedo), text.index(contract))
        self.assertLess(text.index(roughness), text.index(contract))
        self.assertLess(text.index(contract), text.index(build))

        # Fail closed against a later per-proxy replacement that would sever the
        # rendered resource from the audited metadata while leaving recipe constants.
        self.assertNotIn("pavement.material = StandardMaterial3D.new()", text)
        self.assertNotIn("pavement.material_override", text)

    def test_material_contract_stays_non_source_backed_and_non_reusable(self) -> None:
        text = RUNTIME.read_text(encoding="utf-8")
        self.assertIn('target.set_meta("material_identity_source_backed", false)', text)
        self.assertIn('target.set_meta("material_reuse_scope", "anneessens_proxy_only")', text)
        self.assertIn('target.set_meta("brussels_material_family_authorized", false)', text)
        self.assertIn('material.set_meta("presentation_parameters_source_backed", false)', text)
        self.assertNotIn('brussels_material_family_authorized", true', text)


if __name__ == "__main__":
    unittest.main()
