from __future__ import annotations

import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS_DIR))

from make_runtime_slice import select_buildings  # noqa: E402


def building(osm_id: int, x: float, z: float, area: float = 100.0) -> dict:
    return {
        "osm_id": osm_id,
        "area": area,
        "footprint": [
            [x - 1.0, z - 1.0],
            [x + 1.0, z - 1.0],
            [x + 1.0, z + 1.0],
            [x - 1.0, z + 1.0],
        ],
    }


class RuntimeBuildingSelectionTest(unittest.TestCase):
    def test_required_hero_survives_global_building_budget(self) -> None:
        anchors = [(0.0, 0.0), (100.0, 0.0)]
        full = [building(index, float(index), 1.0) for index in range(1, 8)]
        hero = building(13494623, 95.0, 12.0, area=3_363.76)
        full.append(hero)

        selected = select_buildings(
            full,
            anchors,
            building_radius=30.0,
            max_buildings=4,
            required_osm_ids=[13494623],
        )

        self.assertEqual(len(selected), 4)
        self.assertIn(13494623, [item["osm_id"] for item in selected])
        self.assertEqual(
            [item["osm_id"] for item in selected],
            [item["osm_id"] for item in select_buildings(
                list(reversed(full)),
                anchors,
                building_radius=30.0,
                max_buildings=4,
                required_osm_ids=[13494623],
            )],
        )

    def test_missing_required_hero_fails_instead_of_silently_degrading(self) -> None:
        with self.assertRaisesRegex(ValueError, "13494623"):
            select_buildings(
                [building(1, 0.0, 0.0)],
                [(0.0, 0.0), (100.0, 0.0)],
                building_radius=30.0,
                max_buildings=4,
                required_osm_ids=[13494623],
            )


if __name__ == "__main__":
    unittest.main()
