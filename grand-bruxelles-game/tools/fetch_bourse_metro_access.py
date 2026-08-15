#!/usr/bin/env python3
"""Fetch exact Bourse/Beurs underground station entrances from City of Brussels Open Data.

Tiny source unlocker for the same runtime lot. It filters locally rather than relying
on API query syntax, and only carries factual bilingual identity + published points.
It does not claim surveyed furniture, entrance geometry, signage dimensions, yaw,
or service semantics.
"""
from __future__ import annotations

import json
import re
import sys
import urllib.parse
import urllib.request

DATASET = "entrees-stations-souterraines-metro-premetro-ingangen-ondergrondse-metro-premetro-stations"
BASE = f"https://opendata.brussels.be/api/explore/v2.1/catalog/datasets/{DATASET}/records"


def _normalized_station(value: object) -> str:
    text = re.sub(r"\s+", " ", str(value or "").strip()).casefold()
    if text.startswith("station "):
        text = text[len("station "):]
    return text


def _point(row: dict) -> tuple[float, float] | None:
    for key in ("geo_point_2d", "geopoint", "coordinates"):
        value = row.get(key)
        if isinstance(value, dict) and "lon" in value and "lat" in value:
            return float(value["lon"]), float(value["lat"])
        if isinstance(value, (list, tuple)) and len(value) >= 2:
            return float(value[1]), float(value[0])
    shape = row.get("geo_shape")
    if isinstance(shape, dict):
        geometry = shape.get("geometry", shape)
        coords = geometry.get("coordinates") if isinstance(geometry, dict) else None
        if isinstance(coords, (list, tuple)) and len(coords) >= 2:
            return float(coords[0]), float(coords[1])
    return None


def main() -> int:
    try:
        params = urllib.parse.urlencode({"limit": "100"})
        req = urllib.request.Request(
            f"{BASE}?{params}",
            headers={"User-Agent": "Grand-Bruxelles-Game-source-audit/1.0"},
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            payload = json.load(response)

        rows = payload.get("results", [])
        if not isinstance(rows, list) or not rows:
            raise RuntimeError("Official City dataset returned no records")

        records = []
        for row in rows:
            if _normalized_station(row.get("station_fr")) != "bourse":
                continue
            station_nl_raw = row.get("station_nl", "")
            if _normalized_station(station_nl_raw) != "beurs":
                raise RuntimeError(f"Unexpected Dutch station name: {station_nl_raw!r}")
            point = _point(row)
            if point is None:
                raise RuntimeError(
                    "Bourse access record lacks usable published point; keys="
                    + ",".join(sorted(str(k) for k in row.keys()))
                )
            lon, lat = point
            records.append({
                "stop_id": str(row.get("stop_id", "")),
                "station_fr": "Bourse",
                "station_nl": "Beurs",
                "stop_name": str(row.get("stop_name", "")),
                "ifu_type": str(row.get("ifu_type", "")),
                "lon": lon,
                "lat": lat,
            })

        if len(records) < 2:
            sample_names = sorted({str(r.get("station_fr", "")) for r in rows})
            raise RuntimeError(
                f"Need naturally broader Bourse entrance set; got {len(records)}; "
                f"station_fr samples={sample_names[:30]}"
            )

        records.sort(key=lambda r: (r["lat"], r["lon"], r["stop_id"]))
        out = {
            "schema": "grand-bruxelles-bourse-metro-access-source-v1",
            "authority": "City of Brussels Open Data / STIB-MIVB",
            "dataset": DATASET,
            "license": "CC BY 4.0",
            "coordinate_precision_note": "Publisher warns entrance locations may sometimes lack precision; published points are used as source anchors, not centimetre surveys.",
            "station_fr": "Bourse",
            "station_nl": "Beurs",
            "entrance_count": len(records),
            "records": records,
        }
        print("BOURSE_METRO_ACCESS_SOURCE_OK=" + json.dumps(out, ensure_ascii=False, sort_keys=True))
        return 0
    except Exception as exc:
        print(f"BOURSE_METRO_ACCESS_SOURCE_FAIL={type(exc).__name__}: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
