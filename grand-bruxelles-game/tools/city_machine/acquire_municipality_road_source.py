#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
TOOLS = HERE.parent
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))

from transform_osm_to_game import convert

SCHEMA = "grand-bruxelles-municipality-road-source-acquisition-v1"
RECEIPT_SCHEMA = "grand-bruxelles-municipality-road-source-receipt-v1"
USER_AGENT = "GrandBruxellesGame/0.2 municipality-road-acquisition"
CLOSED_KEYS = (
    "source_registration_authorized",
    "road_cell_mapping_authorized",
    "render_authorized",
    "collision_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
)


def canonical_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def read_manifest(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != SCHEMA:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: manifest schema drift")
    municipality = payload.get("municipality") or {}
    relation_id = municipality.get("osm_relation_id")
    if not isinstance(relation_id, int) or relation_id <= 0:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid OSM relation id")
    auth = payload.get("authorization") or {}
    if auth.get("source_acquisition_authorized") is not True:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: source acquisition not authorized")
    for key in CLOSED_KEYS:
        if auth.get(key) is not False:
            raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: manifest opened {key}")
    classes = (payload.get("source") or {}).get("highway_classes")
    if not isinstance(classes, list) or not classes or len(classes) != len(set(classes)):
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid highway class allowlist")
    return payload


def build_query(manifest: dict[str, Any]) -> str:
    relation_id = int(manifest["municipality"]["osm_relation_id"])
    classes = "|".join(str(value) for value in manifest["source"]["highway_classes"])
    return (
        "[out:json][timeout:120];\n"
        f"rel({relation_id});\n"
        "map_to_area->.municipality;\n"
        f"way(area.municipality)[\"highway\"~\"^({classes})$\"];\n"
        "out tags geom;"
    )


def fetch(endpoint: str, query: str, retries: int) -> dict[str, Any]:
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(
        endpoint,
        data=body,
        headers={
            "User-Agent": USER_AGENT,
            "Content-Type": "application/x-www-form-urlencoded",
            "Accept": "application/json",
        },
        method="POST",
    )
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=150) as response:
                payload = json.load(response)
            if not isinstance(payload, dict) or not isinstance(payload.get("elements"), list):
                raise ValueError("unexpected Overpass response")
            return payload
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError) as exc:
            if attempt >= retries:
                raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: Overpass failed: {exc}") from exc
            time.sleep(min(2 ** attempt, 12))
    raise AssertionError("unreachable")


def build_outputs(manifest: dict[str, Any], raw: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    frame = manifest["game_frame"]
    origin = (float(frame["origin_lat"]), float(frame["origin_lon"]))
    converted = convert(raw, origin)
    roads = converted.get("roads") or []
    if not roads or int(converted["stats"]["drivable_roads"]) <= 0:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: source produced no drivable roads")
    if int(converted["stats"]["drivable_roads"]) != len(roads):
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: non-drivable road escaped allowlist")

    raw_digest = sha256(canonical_bytes(raw))
    game_source = {
        **converted,
        "municipality": manifest["municipality"],
        "acquisition": {
            "schema": SCHEMA,
            "query": build_query(manifest),
            "raw_snapshot_sha256": raw_digest,
            "osm_base_timestamp": str((raw.get("osm3s") or {}).get("timestamp_osm_base") or ""),
        },
        "authorization": {
            "source_registration_authorized": False,
            "road_cell_mapping_authorized": False,
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        },
    }
    game_digest = sha256(canonical_bytes(game_source))
    receipt = {
        "schema": RECEIPT_SCHEMA,
        "municipality": manifest["municipality"],
        "source": manifest["source"],
        "raw_snapshot_sha256": raw_digest,
        "normalized_game_source_sha256": game_digest,
        "road_count": len(roads),
        "point_count": sum(len(row.get("points") or []) for row in roads),
        "osm_base_timestamp": game_source["acquisition"]["osm_base_timestamp"],
        "authorization": game_source["authorization"],
    }
    return game_source, receipt


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--raw-output", type=Path, required=True)
    parser.add_argument("--game-output", type=Path, required=True)
    parser.add_argument("--receipt-output", type=Path, required=True)
    parser.add_argument("--retries", type=int, default=4)
    args = parser.parse_args()

    manifest = read_manifest(args.manifest)
    query = build_query(manifest)
    raw = fetch(str(manifest["source"]["endpoint"]), query, max(1, args.retries))
    game_source, receipt = build_outputs(manifest, raw)

    for path in (args.raw_output, args.game_output, args.receipt_output):
        path.parent.mkdir(parents=True, exist_ok=True)
    args.raw_output.write_bytes(canonical_bytes(raw) + b"\n")
    args.game_output.write_bytes(canonical_bytes(game_source) + b"\n")
    args.receipt_output.write_bytes(canonical_bytes(receipt) + b"\n")
    print(
        "MUNICIPALITY_ROAD_ACQUISITION_GREEN: "
        f"nis={manifest['municipality']['niscode']} roads={receipt['road_count']} "
        f"points={receipt['point_count']} sha256={receipt['normalized_game_source_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
