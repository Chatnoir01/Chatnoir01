#!/usr/bin/env python3
"""Inspect official STIB-MIVB Open Data schemas used by Grand Bruxelles.

Read-only diagnostic: probe both supported Opendatasoft API styles and expose
response details before the game commits any STIB runtime geometry.
"""

from __future__ import annotations

import json
import sys
import urllib.request
from typing import Any

V2 = "https://data.stib-mivb.be/api/explore/v2.1/catalog/datasets"
V1 = "https://data.stib-mivb.be/api/records/1.0/search/"

PROBES = {
    "spatial_v1": f"{V1}?dataset=shapefiles-production&rows=3",
    "routes_v1": f"{V1}?dataset=gtfs-routes-production&rows=3",
    "stops_v1": f"{V1}?dataset=gtfs-stops-production&rows=3",
    "files_v1": f"{V1}?dataset=gtfs-files-production&rows=10",
    "spatial_v2": f"{V2}/shapefiles-production/records?limit=3",
    "routes_v2": f"{V2}/gtfs-routes-production/records?limit=3",
}


def fetch(url: str) -> tuple[Any | None, str, bytes]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Grand-Bruxelles-Game/1.0 (STIB Open Data validation)",
            "Accept": "application/json, application/geo+json;q=0.9, text/plain;q=0.5, */*;q=0.1",
        },
    )
    with urllib.request.urlopen(request, timeout=45) as response:
        payload = response.read()
        content_type = response.headers.get("Content-Type", "")
        print(
            f"FETCH_OK status={response.status} bytes={len(payload)} "
            f"content_type={content_type!r} url={url}"
        )
    try:
        return json.loads(payload.decode("utf-8")), content_type, payload
    except (UnicodeDecodeError, json.JSONDecodeError):
        return None, content_type, payload


def summarize(label: str, data: Any | None, content_type: str, payload: bytes) -> bool:
    print(f"\n=== {label.upper()} ===")
    if data is None:
        preview = payload[:1200].decode("utf-8", errors="replace").replace("\n", " ")
        print("NON_JSON_RESPONSE content_type=", repr(content_type))
        print("body_preview:", preview)
        return False

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
            return True

        records = data.get("records")
        if isinstance(records, list):
            print("record_count:", len(records), "nhits:", data.get("nhits"))
            for index, record in enumerate(records[:3]):
                fields = record.get("fields", {}) if isinstance(record, dict) else {}
                geom = record.get("geometry") if isinstance(record, dict) else None
                print(
                    f"record[{index}] field_keys={sorted(fields.keys())} "
                    f"geometry_type={(geom or {}).get('type') if isinstance(geom, dict) else None}"
                )
                print("sample_fields:", json.dumps(fields, ensure_ascii=False)[:1800])
            return True

        results = data.get("results")
        if isinstance(results, list):
            print("result_count:", len(results), "total_count:", data.get("total_count"))
            for index, result in enumerate(results[:3]):
                if isinstance(result, dict):
                    print(f"result[{index}] keys={sorted(result.keys())}")
                    print("sample:", json.dumps(result, ensure_ascii=False)[:1800])
            return True

    print("JSON sample:", json.dumps(data, ensure_ascii=False)[:3000])
    return True


def main() -> int:
    successes: list[str] = []
    for label, url in PROBES.items():
        try:
            data, content_type, payload = fetch(url)
            if summarize(label, data, content_type, payload):
                successes.append(label)
        except Exception as exc:  # noqa: BLE001 - diagnostic tool
            print(f"FETCH_FAIL {label}: {exc}", file=sys.stderr)

    required_groups = [
        ("spatial", ["spatial_v1", "spatial_v2"]),
        ("routes", ["routes_v1", "routes_v2"]),
        ("stops", ["stops_v1"]),
        ("files", ["files_v1"]),
    ]
    missing = [name for name, probes in required_groups if not any(p in successes for p in probes)]
    if missing:
        print("STIB_SCHEMA_INSPECTION_FAIL missing JSON groups:", ", ".join(missing), file=sys.stderr)
        return 1

    print("STIB_SCHEMA_INSPECTION_OK successful_probes=", ",".join(successes))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
