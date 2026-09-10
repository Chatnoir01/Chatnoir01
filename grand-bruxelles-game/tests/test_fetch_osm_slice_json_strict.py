#!/usr/bin/env python3
from __future__ import annotations

import io
import json
import math
import sys
from pathlib import Path
from unittest.mock import patch

PROJECT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT))

from tools import fetch_osm_slice


class FakeResponse(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        self.close()
        return False


def require_request_rejected(raw: bytes, label: str) -> None:
    with patch.object(fetch_osm_slice.urllib.request, "urlopen", return_value=FakeResponse(raw)):
        try:
            fetch_osm_slice._request("[out:json];node(0,0,0,0);out;")
        except (ValueError, json.JSONDecodeError, UnicodeDecodeError):
            return
    raise AssertionError(f"Overpass acquisition accepted ambiguous/non-finite JSON: {label}")


def require_malformed_response_not_retried() -> None:
    calls = 0

    def malformed_response(*args, **kwargs):
        nonlocal calls
        calls += 1
        return FakeResponse(b'{"version":0.6,"elements":[')

    with (
        patch.object(fetch_osm_slice.urllib.request, "urlopen", side_effect=malformed_response),
        patch.object(fetch_osm_slice.time, "sleep") as sleep_mock,
    ):
        try:
            fetch_osm_slice.fetch("[out:json];node(0,0,0,0);out;", retries=4)
        except json.JSONDecodeError:
            pass
        else:
            raise AssertionError("malformed Overpass JSON unexpectedly accepted")

    assert calls == 1, f"malformed source response was re-fetched {calls} times"
    sleep_mock.assert_not_called()


def main() -> int:
    require_request_rejected(
        b'{"version":0.6,"elements":[{"type":"node","id":999}],"elements":[]}',
        "duplicate root elements with canonical final value",
    )
    require_request_rejected(
        b'{"version":0.6,"elements":[{"type":"node","id":1,"lat":NaN,"lon":4.34}]}',
        "non-standard NaN constant",
    )
    require_request_rejected(
        b'{"version":0.6,"elements":[{"type":"node","id":1,"lat":Infinity,"lon":4.34}]}',
        "non-standard Infinity constant",
    )
    require_request_rejected(
        b'{"version":0.6,"elements":[{"type":"node","id":1,"lat":1e309,"lon":4.34}]}',
        "finite-syntax float overflow",
    )
    require_malformed_response_not_retried()

    with patch.object(
        fetch_osm_slice.urllib.request,
        "urlopen",
        return_value=FakeResponse(b'{"version":0.6,"elements":[]}'),
    ):
        payload = fetch_osm_slice._request("[out:json];node(0,0,0,0);out;")
    assert payload == {"version": 0.6, "elements": []}
    assert math.isfinite(payload["version"])

    print(
        "FETCH_OSM_SLICE_JSON_STRICT_OK "
        "duplicate_keys_rejected=true constants_rejected=true float_overflow_rejected=true "
        "malformed_json_retry=false network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
