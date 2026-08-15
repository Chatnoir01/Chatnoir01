#!/usr/bin/env python3
"""Fetch exact Bourse/Beurs underground station entrances from City of Brussels Open Data.

This is a source unlocker for the same runtime lot. It prints compact authoritative
records; it does not invent station furniture, entrance geometry, signage dimensions,
or service semantics.
"""
from __future__ import annotations

import json
import urllib.parse
import urllib.request

DATASET = "entrees-stations-souterraines-metro-premetro-ingangen-ondergrondse-metro-premetro-stations"
BASE = f"https://opendata.brussels.be/api/explore/v2.1/catalog/datasets/{DATASET}/records"


def main() -> int:
    params = urllib.parse.urlencode({"where": "station_fr='Bourse'", "limit": "50"})
    req = urllib.request.Request(
        f"{BASE}?{params}",
        headers={"User-Agent": "Grand-Bruxelles-Game-source-audit/1.0"},
    )
    with urllib.request.urlopen(req, timeout=30) as response:
        payload = json.load(response)

    rows = payload.get("results", [])
    if not isinstance(rows, list) or not rows:
        raise RuntimeError("No Bourse metro-access records returned by official City dataset")

    records = []
    for row in rows:
        if str(row.get("station_fr", "")).strip().casefold() != "bourse":
            continue
        station_nl = str(row.get("station_nl", "")).strip()
        point = row.get("geo_point_2d")
        if station_nl.casefold() != "beurs":
            raise RuntimeError(f"Unexpected Dutch station name: {station_nl!r}")
        if not isinstance(point, dict) or "lon" not in point or "lat" not in point:
            raise RuntimeError("Bourse access record lacks usable geo_point_2d")
        records.append({
            "stop_id": str(row.get("stop_id", "")),
            "station_fr": "Bourse",
            "station_nl": "Beurs",
            "stop_name": str(row.get("stop_name", "")),
            "ifu_type": str(row.get("ifu_type", "")),
            "lon": float(point["lon"]),
            "lat": float(point["lat"]),
        })

    if len(records) < 2:
        raise RuntimeError(f"Need a naturally broader entrance set; got only {len(records)} record(s)")

    records.sort(key=lambda r: (r["lat"], r["lon"], r["stop_id"]))
    out = {
        "schema": "grand-bruxelles-bourse-metro-access-source-v1",
        "authority": "City of Brussels Open Data / STIB-MIVB",
        "dataset": DATASET,
        "license": "CC BY 4.0",
        "station_fr": "Bourse",
        "station_nl": "Beurs",
        "entrance_count": len(records),
        "records": records,
    }
    print("BOURSE_METRO_ACCESS_SOURCE_OK=" + json.dumps(out, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
