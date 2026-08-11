from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "discover_brussels_opendata_boundaries.py"
SPEC = importlib.util.spec_from_file_location("discover_brussels_opendata_boundaries", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class DiscoverBrusselsOpenDataBoundariesTests(unittest.TestCase):
    def test_search_url_targets_official_domain_and_encodes_term(self) -> None:
        url = MODULE.search_url("quartier européen", 20)
        self.assertTrue(url.startswith("https://opendata.brussels.be/api/explore/v2.1/catalog/datasets?"))
        self.assertIn("limit=20", url)
        self.assertIn("where=", url)

    def test_discovery_deduplicates_dataset_and_merges_terms(self) -> None:
        payloads = {
            "quartier": {
                "total_count": 1,
                "results": [{
                    "dataset_id": "boundaries",
                    "has_records": True,
                    "visibility": "domain",
                    "metas": {"default": {"title": "Quartiers", "description": "Official areas"}},
                }],
            },
            "district": {
                "total_count": 1,
                "results": [{
                    "dataset_id": "boundaries",
                    "has_records": True,
                    "visibility": "domain",
                    "metas": {"default": {"title": "Quartiers", "description": "Official areas"}},
                }],
            },
        }

        def fake_request(url: str):
            term = "quartier" if "quartier" in url else "district"
            return payloads[term]

        with patch.object(MODULE, "request_json", side_effect=fake_request):
            result = MODULE.discover(["quartier", "district"], 10)
        self.assertEqual(result["candidate_count"], 1)
        self.assertEqual(result["candidates"][0]["dataset_id"], "boundaries")
        self.assertEqual(result["candidates"][0]["matched_terms"], ["district", "quartier"])
        self.assertIn("no candidate is production-approved", result["purpose"])

    def test_meta_text_tolerates_missing_metadata(self) -> None:
        self.assertEqual(MODULE.meta_text({}, "title"), "")
        self.assertEqual(MODULE.meta_text({"metas": {"default": {"title": "X"}}}, "title"), "X")


if __name__ == "__main__":
    unittest.main()
