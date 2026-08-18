#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDENTITY = ROOT / "data/visual/midi_fonsny_perforated_canopy_identity.json"
HERO = ROOT / "game/scripts/midi_hero_zone.gd"

OLD_CANOPY = (
    '_add_box(entrance, "EntranceConcreteCanopy", '
    'Vector3(17.8, 0.48, 25.0), Vector3(-7.0, 4.55, 0.0), _concrete)'
)


class MidiFonsnyPerforatedCanopyContractTest(unittest.TestCase):
    def test_source_contract_and_in_place_replacement(self) -> None:
        identity = json.loads(IDENTITY.read_text(encoding="utf-8"))
        hero = HERO.read_text(encoding="utf-8")

        self.assertEqual(identity["schema"], "grand-bruxelles-midi-fonsny-canopy-v1")
        self.assertEqual(identity["zone"], "midi")
        self.assertEqual(identity["heritage_source"]["urban_id"], 9423)
        self.assertEqual(
            identity["heritage_source"]["url"],
            "https://monument.heritage.brussels/fr/Saint-Gilles/Avenue_Fonsny/47/9423",
        )
        facts = " ".join(identity["heritage_source"]["facts"]).lower()
        self.assertIn("polygonal columns", facts)
        self.assertIn("concrete canopy perforated with glass blocks", facts)
        self.assertIn("three long bays", facts)

        envelope = identity["existing_presentation_envelope"]
        self.assertEqual(envelope["authority"], "existing_authored_visualization_convention_not_survey_geometry")
        self.assertEqual(envelope["size_m"], [17.8, 0.48, 25.0])
        self.assertEqual(envelope["local_position_m"], [-7.0, 4.55, 0.0])
        self.assertTrue(envelope["preserve_size"])
        self.assertTrue(envelope["preserve_local_position"])
        self.assertTrue(envelope["preserve_entrance_root_transform"])

        contract = identity["replacement_contract"]
        self.assertTrue(contract["replace_existing_surface_in_place"])
        self.assertTrue(contract["additive_duplicate_forbidden"])
        self.assertTrue(contract["concrete_frame_required"])
        self.assertTrue(contract["glass_block_infill_required"])
        self.assertFalse(contract["panel_count_is_source_measured"])
        self.assertFalse(contract["rib_spacing_is_source_measured"])
        self.assertFalse(contract["thickness_is_source_measured"])
        self.assertFalse(contract["new_station_plan_geometry"])
        self.assertTrue(contract["urbis_station_plan_authority_preserved"])
        self.assertFalse(contract["runtime_approved"])
        self.assertFalse(contract["realism_complete"])

        # RED-first guard: production currently owns one solid authored canopy.
        # The implementation must replace that exact surface in place rather
        # than stacking another porch/canopy behind it.
        self.assertIn(OLD_CANOPY, hero, "expected current production solid-canopy baseline moved unexpectedly")
        self.assertIn(
            "EntranceSourceBackedPerforatedCanopy",
            hero,
            "source-backed Fonsny canopy replacement missing",
        )
        self.assertRegex(hero, r"CanopyConcreteRib_[^\n]*")
        self.assertRegex(hero, r"CanopyGlassBlockPanel_[^\n]*")
        self.assertIn("fonsny_canopy_dimensions_are_visualization_convention", hero)

        replacement_call = re.search(
            r'_build_fonsny_source_backed_canopy\(entrance[^\n]*\)', hero
        )
        self.assertIsNotNone(replacement_call, "Fonsny source-backed canopy builder is not mounted")


if __name__ == "__main__":
    unittest.main()
