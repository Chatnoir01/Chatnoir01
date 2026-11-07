from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "bootstrap_remaining_brussels.py"
SPEC = importlib.util.spec_from_file_location("bootstrap_remaining_brussels", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class BootstrapRemainingBrusselsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = {
            "zones": [
                {"id": "anderlecht", "name": "Anderlecht", "wave": "R1", "priority": 1},
                {"id": "molenbeek", "name": "Molenbeek-Saint-Jean", "wave": "R1", "priority": 2},
                {"id": "uccle", "name": "Uccle", "wave": "R3", "priority": 3},
            ]
        }

    def test_choose_explicit_zone(self) -> None:
        zones = MODULE.choose_zones(self.catalog, ["molenbeek"], None, False)
        self.assertEqual([zone["id"] for zone in zones], ["molenbeek"])

    def test_choose_wave_sorted_by_priority(self) -> None:
        zones = MODULE.choose_zones(self.catalog, [], "R1", False)
        self.assertEqual([zone["id"] for zone in zones], ["anderlecht", "molenbeek"])

    def test_all_zones_sorted_by_priority(self) -> None:
        zones = MODULE.choose_zones(self.catalog, [], None, True)
        self.assertEqual([zone["id"] for zone in zones], ["anderlecht", "molenbeek", "uccle"])

    def test_unknown_zone_rejected(self) -> None:
        with self.assertRaises(KeyError):
            MODULE.choose_zones(self.catalog, ["unknown"], None, False)

    def test_commands_chain_boundary_then_cells(self) -> None:
        zone = self.catalog["zones"][0]
        commands = MODULE.commands_for_zone(zone, Path("out"), 500.0)
        self.assertEqual(len(commands), 2)
        self.assertIn("fetch_urbis_municipality.py", commands[0][1])
        self.assertIn("make_zone_cells.py", commands[1][1])
        self.assertIn("Anderlecht", commands[0])
        self.assertIn("anderlecht", commands[1])


if __name__ == "__main__":
    unittest.main()
