#!/usr/bin/env python3
from __future__ import annotations

import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDENTITY = ROOT / "data/visual/midi_fonsny_perforated_canopy_identity.json"
HERO = ROOT / "game/scripts/midi_hero_zone.gd"
RUNTIME = ROOT / "game/scripts/midi_fonsny_perforated_canopy_runtime.gd"
MOUNT = ROOT / "game/scripts/midi_architectural_concrete_surface_runtime.gd"

OLD_CANOPY = (
    '_add_box(entrance, "EntranceConcreteCanopy", '
    'Vector3(17.8, 0.48, 25.0), Vector3(-7.0, 4.55, 0.0), _concrete)'
)


class MidiFonsnyPerforatedCanopyContractTest(unittest.TestCase):
    def test_source_contract_and_in_place_replacement(self) -> None:
        identity = json.loads(IDENTITY.read_text(encoding="utf-8"))
        hero = HERO.read_text(encoding="utf-8")
        runtime = RUNTIME.read_text(encoding="utf-8")
        mount = MOUNT.read_text(encoding="utf-8")

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

        # Preserve the exact current-production slab as a hidden same-run A/B
        # baseline. The candidate runtime, not MidiHero geometry placement,
        # owns the visible replacement and must never show both at once.
        self.assertIn(OLD_CANOPY, hero, "current production canopy baseline drifted")
        self.assertIn("EntranceSourceBackedPerforatedCanopy", runtime)
        self.assertIn("CanopyConcreteRib_X_", runtime)
        self.assertIn("CanopyConcreteRib_Z_", runtime)
        self.assertIn("CanopyGlassBlockPanel_", runtime)
        self.assertIn("fonsny_canopy_dimensions_are_visualization_convention", runtime)
        self.assertIn('const CANOPY_SIZE := Vector3(17.8, 0.48, 25.0)', runtime)
        self.assertIn('const CANOPY_POSITION := Vector3(-7.0, 4.55, 0.0)', runtime)
        self.assertIn("_baseline.visible = not enabled", runtime)
        self.assertIn("_replacement.visible = enabled", runtime)
        self.assertIn("set_source_backed_enabled(true)", runtime)
        self.assertIn("panel_count_source_measured", runtime)
        self.assertIn("rib_spacing_source_measured", runtime)
        self.assertIn('official_station_plan_authority", "UrbIS"', runtime)

        self.assertIn('preload("res://game/scripts/midi_fonsny_perforated_canopy_runtime.gd")', mount)
        self.assertIn('name = "MidiFonsnyPerforatedCanopyRuntime"', mount)
        self.assertIn("func fonsny_canopy_runtime() -> Node:", mount)


if __name__ == "__main__":
    unittest.main()
