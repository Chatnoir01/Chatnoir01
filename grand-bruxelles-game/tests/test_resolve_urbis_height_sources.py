from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "resolve_urbis_height_sources.py"
SPEC = importlib.util.spec_from_file_location("resolve_urbis_height_sources", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ResolveUrbisHeightSourcesTests(unittest.TestCase):
    def test_resolves_exact_zip_per_tile(self) -> None:
        links = {
            "https://example.test/UrbISDSM_31370_TIFF_149168_20211009_50.zip",
            "https://example.test/UrbISDSM_31370_TIFF_149169_20211009_50.zip",
            "https://example.test/readme.xml",
        }
        self.assertEqual(MODULE.resolve_links(links, ["149168", "149169"]), {
            "149168": "https://example.test/UrbISDSM_31370_TIFF_149168_20211009_50.zip",
            "149169": "https://example.test/UrbISDSM_31370_TIFF_149169_20211009_50.zip",
        })

    def test_rejects_missing_tile(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.resolve_links({"https://example.test/149168.zip"}, ["149168", "149169"])

    def test_rejects_ambiguous_duplicate_tile(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.resolve_links({"https://example.test/a_149168.zip", "https://example.test/b_149168.zip"}, ["149168"])

    def test_non_zip_links_do_not_count_as_archives(self) -> None:
        with self.assertRaises(ValueError):
            MODULE.resolve_links({"https://example.test/UrbISDSM_149168.tif"}, ["149168"])

    def test_resolution_manifest_is_deterministic(self) -> None:
        plan = {
            "source_crs": "EPSG:31370",
            "bbox_epsg31370": [149000, 168500, 150000, 170000],
            "expected_1km_tile_codes": ["149168"],
            "official_sources": {"dsm": {
                "name": "Paradigm UrbIS Digital Surface Model 2021",
                "dataset_id": "dataset",
                "atom_feed": "https://urbisdownload.datastore.brussels/atomfeed/dataset-en.xml",
            }},
        }
        feeds = [{"url": plan["official_sources"]["dsm"]["atom_feed"], "depth": 0, "bytes": 123, "links": 1}]
        links = {"https://urbisdownload.datastore.brussels/UrbISDSM_31370_TIFF_149168_20211009_50.zip"}
        first = MODULE.build_resolution(plan, "dsm", feeds, links)
        second = MODULE.build_resolution(plan, "dsm", feeds, links)
        self.assertEqual(first, second)
        self.assertNotIn("fetched_at_utc", first)


if __name__ == "__main__":
    unittest.main()
