from __future__ import annotations

import io
import json
import urllib.parse
import unittest
from unittest.mock import patch

from grand_bruxelles_game_test_support import import_tool

FETCH = import_tool("fetch_urbis_wfs_bbox")


class FakeResponse:
    def __init__(self, payload: dict) -> None:
        self._payload = json.dumps(payload).encode("utf-8")

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, exc_type, exc, tb) -> None:
        return None

    def read(self) -> bytes:
        return self._payload


class FetchUrbisWfsBboxTests(unittest.TestCase):
    def test_subdivide_bbox_preserves_exact_extent(self) -> None:
        bbox = (150500.0, 172500.0, 151000.0, 173000.0)
        self.assertEqual(
            FETCH._subdivide_bbox(bbox),
            (
                (150500.0, 172500.0, 150750.0, 172750.0),
                (150750.0, 172500.0, 151000.0, 172750.0),
                (150500.0, 172750.0, 150750.0, 173000.0),
                (150750.0, 172750.0, 151000.0, 173000.0),
            ),
        )

    def test_merge_subdivided_collections_deduplicates_crossing_features(self) -> None:
        bbox = (0.0, 0.0, 500.0, 500.0)
        documents = [
            {"type": "FeatureCollection", "features": [{"id": "building.1", "properties": {"a": 1}, "geometry": None}]},
            {"type": "FeatureCollection", "features": [{"id": "building.1", "properties": {"a": 1}, "geometry": None}, {"id": "building.2", "properties": {"a": 2}, "geometry": None}]},
            {"type": "FeatureCollection", "features": []},
            {"type": "FeatureCollection", "features": [{"properties": {"a": 3}, "geometry": {"type": "Point", "coordinates": [1, 2]}}]},
        ]
        merged = FETCH._merge_feature_collections("urbisvector:Buildings", bbox, documents)
        self.assertEqual([feature.get("id") for feature in merged["features"][:2]], ["building.1", "building.2"])
        self.assertEqual(len(merged["features"]), 3)
        self.assertEqual(merged["numberReturned"], 3)
        self.assertEqual(merged["grand_bruxelles_fetch"]["deduplicated_features"], 1)
        self.assertEqual(merged["grand_bruxelles_fetch"]["bbox"], list(bbox))

    def test_request_layer_falls_back_to_exact_quadrants_after_direct_timeout(self) -> None:
        bbox = (150500.0, 172500.0, 151000.0, 173000.0)
        calls: list[tuple[float, float, float, float]] = []

        def fake_urlopen(request, timeout):
            query = urllib.parse.parse_qs(urllib.parse.urlparse(request.full_url).query)
            raw_bbox = query["bbox"][0].split(",")[:4]
            current = tuple(float(value) for value in raw_bbox)
            calls.append(current)
            if current == bbox:
                raise TimeoutError("synthetic direct timeout")
            feature_id = f"f-{int(current[0])}-{int(current[1])}"
            return FakeResponse({"type": "FeatureCollection", "features": [{"id": feature_id, "properties": {}, "geometry": None}]})

        with patch.object(FETCH.time, "sleep", return_value=None), patch.object(FETCH.urllib.request, "urlopen", side_effect=fake_urlopen):
            result = FETCH.request_layer("urbisvector:Buildings", bbox, retries=4)

        self.assertEqual(calls[:2], [bbox, bbox])
        self.assertEqual(set(calls[2:]), set(FETCH._subdivide_bbox(bbox)))
        self.assertEqual(len(result["features"]), 4)
        self.assertEqual(result["grand_bruxelles_fetch"]["strategy"], "adaptive_quadrant_subdivision")
        self.assertEqual(result["grand_bruxelles_fetch"]["bbox"], list(bbox))

    def test_request_layer_keeps_direct_response_when_service_is_healthy(self) -> None:
        bbox = (150500.0, 172500.0, 151000.0, 173000.0)
        payload = {"type": "FeatureCollection", "features": [{"id": "ok", "properties": {}, "geometry": None}]}
        with patch.object(FETCH.urllib.request, "urlopen", return_value=FakeResponse(payload)) as mocked:
            result = FETCH.request_layer("urbisvector:Buildings", bbox, retries=4)
        self.assertEqual(mocked.call_count, 1)
        self.assertEqual(result["grand_bruxelles_fetch"]["strategy"], "direct_bbox")
        self.assertEqual(result["features"][0]["id"], "ok")


if __name__ == "__main__":
    unittest.main()
