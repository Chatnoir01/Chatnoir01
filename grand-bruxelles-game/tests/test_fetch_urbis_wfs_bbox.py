from __future__ import annotations

import importlib.util
import io
import unittest
import urllib.error
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

    def test_all_requests_keep_bbox_and_never_combine_cql_filter(self) -> None:
        for layer in MODULE.DEFAULT_LAYERS.values():
            params = MODULE.build_request_params(layer, self.bbox)
            self.assertNotIn("CQL_FILTER", params)
            self.assertEqual(
                params["bbox"],
                "147000.0,169500.0,147500.0,170000.0,EPSG:31370",
            )

    def test_url_encodes_bbox_crs_without_cql(self) -> None:
        url = MODULE.build_request_url("urbisvector:TramNetwork", self.bbox)
        parsed = urllib.parse.urlparse(url)
        query = urllib.parse.parse_qs(parsed.query)
        self.assertEqual(query["srsName"], ["EPSG:31370"])
        self.assertNotIn("CQL_FILTER", query)
        self.assertEqual(
            query["bbox"],
            ["147000.0,169500.0,147500.0,170000.0,EPSG:31370"],
        )

    def test_tram_layer_is_pruned_to_tw_in_memory(self) -> None:
        document = {
            "type": "FeatureCollection",
            "features": [
                {"id": "tw", "properties": {"TYPE": "TW"}},
                {"id": "rw", "properties": {"TYPE": "RW"}},
                {"id": "other", "properties": {"TYPE": "XX"}},
            ],
        }
        pruned, removed = MODULE.prune_layer_features("urbisvector:TramNetwork", document)
        self.assertEqual([feature["id"] for feature in pruned["features"]], ["tw"])
        self.assertEqual(removed, 2)
        self.assertEqual(
            pruned["grand_bruxelles_filter"],
            {
                "mode": "post_bbox_in_memory",
                "property": "TYPE",
                "equals": "TW",
                "source_features": 3,
                "kept_features": 1,
                "removed_features": 2,
            },
        )
        self.assertEqual(len(document["features"]), 3, "source document must not be mutated")

    def test_train_layer_is_pruned_to_rw_in_memory(self) -> None:
        document = {
            "type": "FeatureCollection",
            "features": [
                {"id": "tw", "properties": {"TYPE": "TW"}},
                {"id": "rw", "properties": {"TYPE": "RW"}},
            ],
        }
        pruned, removed = MODULE.prune_layer_features("urbisvector:TrainNetwork", document)
        self.assertEqual([feature["id"] for feature in pruned["features"]], ["rw"])
        self.assertEqual(removed, 1)

    def test_non_rail_layer_is_returned_without_pruning(self) -> None:
        document = {"type": "FeatureCollection", "features": [{"id": "x"}]}
        result, removed = MODULE.prune_layer_features("urbisvector:Buildings", document)
        self.assertIs(result, document)
        self.assertEqual(removed, 0)

    def test_http_error_detail_includes_geoserver_body(self) -> None:
        body = b"<ows:ExceptionText>bbox and cql_filter both specified but are mutually exclusive</ows:ExceptionText>"
        error = urllib.error.HTTPError(
            "https://example.invalid/wfs",
            500,
            "Internal Server Error",
            {},
            io.BytesIO(body),
        )
        detail = MODULE._http_error_detail(error)
        self.assertIn("HTTP 500", detail)
        self.assertIn("mutually exclusive", detail)


if __name__ == "__main__":
    unittest.main()
