from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path


TOOLS_DIR = Path(__file__).resolve().parents[1] / "tools"
sys.path.insert(0, str(TOOLS_DIR))

from validate_hero_building_evidence import validate_document  # noqa: E402


def valid_document() -> dict:
    return {
        "required_buildings": [
            {
                "osm_id": 13494623,
                "anchor_id": "bourse",
                "role": "hero_landmark_fallback",
                "name": "Bourse - Beurs",
                "runtime_approval": {
                    "footprint": True,
                    "height": False,
                    "roof": False,
                    "frontage": False,
                },
                "evidence": {
                    "footprint": {
                        "source": "official_urbis_plan",
                        "inspire_id": "https://databrussels.be/id/building/1751663",
                        "reference": "8186511",
                        "crs": "EPSG:31370",
                        "area_m2": 3368,
                        "accessed_at": "2026-08-12",
                    },
                    "height": None,
                    "roof": None,
                    "frontage": None,
                },
            }
        ]
    }


class HeroBuildingEvidenceContractTest(unittest.TestCase):
    def test_source_backed_footprint_with_unapproved_3d_components_passes(self) -> None:
        self.assertEqual(validate_document(valid_document()), [])

    def test_height_cannot_be_runtime_approved_without_evidence(self) -> None:
        document = valid_document()
        document["required_buildings"][0]["runtime_approval"]["height"] = True
        errors = validate_document(document)
        self.assertTrue(
            any("runtime-approved height requires structured evidence" in error for error in errors),
            errors,
        )

    def test_official_footprint_requires_lambert72(self) -> None:
        document = valid_document()
        document["required_buildings"][0]["evidence"]["footprint"]["crs"] = "EPSG:4326"
        errors = validate_document(document)
        self.assertTrue(any("EPSG:31370" in error for error in errors), errors)

    def test_candidate_evidence_does_not_imply_runtime_approval(self) -> None:
        document = copy.deepcopy(valid_document())
        document["required_buildings"][0]["evidence"]["height"] = {
            "source": "candidate_only",
            "value_m": 30.0,
        }
        self.assertEqual(validate_document(document), [])


if __name__ == "__main__":
    unittest.main()
