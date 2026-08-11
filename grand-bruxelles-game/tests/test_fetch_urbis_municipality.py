from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "fetch_urbis_municipality.py"
SPEC = importlib.util.spec_from_file_location("fetch_urbis_municipality", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FetchUrbisMunicipalityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.data = {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "id": "Municipalities.1",
                    "properties": {
                        "NAME_FRE": "Anderlecht",
                        "NAME_DUT": "Anderlecht",
                        "CODE": "21001",
                    },
                    "geometry": {"type": "Polygon", "coordinates": []},
                },
                {
                    "type": "Feature",
                    "id": "Municipalities.2",
                    "properties": {
                        "NAME_FRE": "Molenbeek-Saint-Jean",
                        "NAME_DUT": "Sint-Jans-Molenbeek",
                        "CODE": "21012",
                    },
                    "geometry": {"type": "Polygon", "coordinates": []},
                },
            ],
        }

    def test_normalize_is_accent_and_hyphen_insensitive(self) -> None:
        self.assertEqual(MODULE.normalize("Saint-Josse-ten-Noode"), "saint josse ten noode")
        self.assertEqual(MODULE.normalize("Forêt"), "foret")

    def test_selects_french_name(self) -> None:
        feature = MODULE.select_municipality(self.data, "Molenbeek-Saint-Jean")
        self.assertEqual(feature["properties"]["CODE"], "21012")

    def test_selects_dutch_name(self) -> None:
        feature = MODULE.select_municipality(self.data, "Sint-Jans-Molenbeek")
        self.assertEqual(feature["properties"]["CODE"], "21012")

    def test_unknown_name_is_rejected(self) -> None:
        with self.assertRaises(LookupError):
            MODULE.select_municipality(self.data, "Atlantis")


if __name__ == "__main__":
    unittest.main()
