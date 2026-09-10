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
        "network_used=false"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
