#!/usr/bin/env python3
"""Fail-closed regression for truncated UrbIS WFS responses."""
from __future__ import annotations

import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("materialize_urbis_source_cell", HERE / "materialize_urbis_source_cell.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)

LAYER = "urbisvector:StreetSurfaces"
BBOX = (147500.0, 170500.0, 148000.0, 171000.0)
QUADRANTS = mod._quarter_bboxes(BBOX)


def feature(fid: str) -> dict:
    return {
        "type": "Feature",
        "id": fid,
        "properties": {"INSPIRE_ID": fid},
        "geometry": {
            "type": "Polygon",
            "coordinates": [[[147500, 170500], [147510, 170500], [147510, 170510], [147500, 170510], [147500, 170500]]],
        },
    }


original = mod._request_layer_once
calls: list[tuple[tuple[float, float, float, float], int]] = []


def fake_once(layer_name, bbox, retries):
    assert layer_name == LAYER
    calls.append((bbox, retries))
    if bbox == BBOX:
        raise RuntimeError("Expecting ',' delimiter: simulated truncated HTTP 200 payload")
    index = QUADRANTS.index(bbox)
    # The same official feature can be returned by adjacent bbox-intersection
    # requests. The fallback must deduplicate deterministically.
    features = [feature(f"surface-{index}"), feature("shared-surface")]
    return {"type": "FeatureCollection", "features": features, "numberReturned": len(features)}


mod._request_layer_once = fake_once
try:
    payload = mod.request_layer(LAYER, BBOX, retries=6)
finally:
    mod._request_layer_once = original

assert calls[0] == (BBOX, 6), calls
assert [bbox for bbox, _ in calls[1:]] == list(QUADRANTS), calls
assert all(retries == 3 for _, retries in calls[1:]), calls
assert payload["type"] == "FeatureCollection"
assert [item["properties"]["INSPIRE_ID"] for item in payload["features"]] == [
    "shared-surface",
    "surface-0",
    "surface-1",
    "surface-2",
    "surface-3",
]
assert payload["numberReturned"] == 5

# If even one official quadrant stays invalid, the source must remain pending.
def failing_quadrant(layer_name, bbox, retries):
    if bbox == BBOX or bbox == QUADRANTS[2]:
        raise RuntimeError("still truncated")
    return {"type": "FeatureCollection", "features": []}

mod._request_layer_once = failing_quadrant
try:
    try:
        mod.request_layer(LAYER, BBOX, retries=6)
    except RuntimeError as exc:
        assert "quadrant" in str(exc)
    else:
        raise AssertionError("incomplete official quadrant evidence must fail closed")
finally:
    mod._request_layer_once = original

print(
    "URBIS_WFS_RETRY_RESILIENCE_OK "
    "full_bbox_retry=true quadrant_fallback=true dedupe=true fail_closed=true promotion_bypass=false"
)
