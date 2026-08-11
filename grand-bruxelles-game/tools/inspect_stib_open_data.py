#!/usr/bin/env python3
"""Inspect official STIB-MIVB Open Data schemas used by Grand Bruxelles.

This tool is intentionally read-only. It verifies that the official Open Data
endpoints are reachable and reports their actual fields/geometry before any
runtime conversion is committed.
"""

from __future__ import annotations

import json
import sys
import urllib.request
from typing import Any

BASE = "https://data.stib-mivb.be/api/explore/v2.1/catalog/datasets"
DATASETS = {
    "spatial": f"{BASE}/shapefiles-production/exports/geojson?lang=fr&timezone=Europe%2FBrussels",
    "routes": f"{BASE}/gtfs-routes-production/records?limit=20",
    "stops": f"{BASE}/gtfs-stops-production/records?limit=5",
    "files": f"{BASE}/gtfs-files-production/records?limit=20",
}


def fetch_json(url: str) -> Any:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Grand-Bruxelles-Game/1.0 (+GitHub CI; STIB Open Data preview)",
            "Accept": "application/json, application/geo+json;q=0.9, */*;q=0.1",
        },
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        payload = response.read()
        print(f"FETCH_OK status={response.status} bytes={len(payload)} url={url}")
    return json.loads(payload.decode("utf-8"))


def summarize(label: str, data: Any) -> None:
    print(f"\n=== {label.upper()} ===")
    if isinstance(data, dict):
        print("top-level keys:", sorted(data.keys()))
        if data.get("type") == "FeatureCollection":
            features = data.get("features") or []
            print("feature_count:", len(features))
            for index, feature in enumerate(features[:3]):
                props = feature.get("properties") or {}
                geom = feature.get("geometry") or {}
                print(
                    f"feature[{index}] geometry={geom.get('type')} "
                    f"property_keys={sorted(props.keys())}"
                )
                print("sample_properties:", json.dumps(props, ensure_ascii=False)[:1500])
            return
        results = data.get("results")
        if isinstance(results, list):
            print("result_count:", len(results))
            for index, result in enumerate(results[:3]):
                if isinstance(result, dict):
                    print(f"result[{index}] keys={sorted(result.keys())}")
                    print("sample:", json.dumps(result, ensure_ascii=False)[:1500])
            return
    print("sample:", json.dumps(data, ensure_ascii=False)[:3000])


def main() -> int:
    failures: list[str] = []
    for label, url in DATASETS.items():
        try:
            data = fetch_json(url)
            summarize(label, data)
        except Exception as exc:  # noqa: BLE001 - diagnostic tool
            failures.append(f"{label}: {exc}")
            print(f"FETCH_FAIL {label}: {exc}", file=sys.stderr)

    if failures:
        print("STIB_SCHEMA_INSPECTION_FAIL:", " | ".join(failures), file=sys.stderr)
        return 1
    print("STIB_SCHEMA_INSPECTION_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
