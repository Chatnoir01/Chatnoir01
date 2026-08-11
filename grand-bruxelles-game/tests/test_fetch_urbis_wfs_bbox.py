from __future__ import annotations

import importlib.util
import unittest
import urllib.parse
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "fetch_urbis_wfs_bbox.py"
SPEC = importlib.util.spec_from_file_location("fetch_urbis_wfs_bbox", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class FetchUrbisWfsBboxTests(unittest.TestCase):
    def setUp(self) -> None:
        self.bbox = (147000.0, 169500.0, 147500.0, 170000.0)

    def test_tram_network_is_filtered_to_tw_at_source(self) -> None:
        params = MODULE.build_request_params("urbisvector:TramNetwork", self.bbox)
        self.assertEqual(params["CQL_FILTER"], "TYPE LIKE 'TW%'")

    def test_train_network_is_filtered_to_rw_at_source(self) -> None:
        params = MODULE.build_request_params("urbisvector:TrainNetwork", self.bbox)
        self.assertEqual(params["CQL_FILTER"], "TYPE LIKE 'RW%'")

    def test_non_rail_layers_do_not_receive_cql_filter(self) -> None:
        for layer in (
            "urbisvector:Buildings",
            "urbisvector:StreetSurfaces",
            "urbisvector:StreetAxes",
        ):
            self.assertNotIn("CQL_FILTER", MODULE.build_request_params(layer, self.bbox))

    def test_url_encodes_bbox_crs_and_filter(self) -> None:
        url = MODULE.build_request_url("urbisvector:TramNetwork", self.bbox)
        parsed = urllib.parse.urlparse(url)
        query = urllib.parse.parse_qs(parsed.query)
        self.assertEqual(query["srsName"], ["EPSG:31370"])
        self.assertEqual(query["CQL_FILTER"], ["TYPE LIKE 'TW%'"])
        self.assertEqual(
            query["bbox"],
            ["147000.0,169500.0,147500.0,170000.0,EPSG:31370"],
        )


if __name__ == "__main__":
    unittest.main()
