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
REGISTRY_SCHEMA = "grand-bruxelles-missing-road-source-registry-v1"
RECEIPT_SCHEMA = "grand-bruxelles-municipality-road-source-receipt-v1"
USER_AGENT = "GrandBruxellesGame/0.2 municipality-road-acquisition"
HIGHWAY_CLASSES = (
    "motorway",
    "trunk",
    "primary",
    "secondary",
    "tertiary",
    "unclassified",
    "residential",
    "living_street",
    "service",
)
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


def reject_duplicate_object_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    result: dict[str, Any] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key {key}")
        result[key] = value
    return result


def strict_json_loads(text: str) -> Any:
    return json.loads(text, object_pairs_hook=reject_duplicate_object_keys)


def read_json_object(path: Path, label: str) -> dict[str, Any]:
    try:
        payload = strict_json_loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError, ValueError) as exc:
        raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: {label}: {exc}") from exc
    if not isinstance(payload, dict):
        raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: {label} must be a JSON object")
    return payload


def validate_authorization(auth: Any, label: str) -> dict[str, Any]:
    if not isinstance(auth, dict):
        raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid {label} authorization")
    if auth.get("source_acquisition_authorized") is not True:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: source acquisition not authorized")
    for key in CLOSED_KEYS:
        if auth.get(key) is not False:
            raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: {label} opened {key}")
    return auth


def read_registry(path: Path) -> dict[str, Any]:
    payload = read_json_object(path, "registry")
    if payload.get("schema") != REGISTRY_SCHEMA:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: registry schema drift")
    source = payload.get("source")
    if not isinstance(source, dict):
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid registry source")
    for key in ("provider", "license", "endpoint"):
        if not isinstance(source.get(key), str) or not source[key].strip():
            raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid registry source {key}")
    frame = payload.get("game_frame")
    if not isinstance(frame, dict):
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid registry game frame")
    for key in ("origin_lat", "origin_lon"):
        if not isinstance(frame.get(key), (int, float)):
            raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid registry game frame {key}")
    municipalities = payload.get("municipalities")
    if not isinstance(municipalities, list) or not municipalities:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid registry municipalities")
    seen_nis: set[str] = set()
    seen_ids: set[str] = set()
    seen_relations: set[int] = set()
    for row in municipalities:
        if not isinstance(row, dict):
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid registry municipality row")
        nis = row.get("niscode")
        municipality_id = row.get("id")
        relation_id = row.get("osm_relation_id")
        if not isinstance(nis, str) or not nis or not isinstance(municipality_id, str) or not municipality_id:
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid registry municipality identity")
        if not isinstance(relation_id, int) or relation_id <= 0:
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid registry OSM relation id")
        if nis in seen_nis or municipality_id in seen_ids or relation_id in seen_relations:
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: duplicate registry municipality identity")
        seen_nis.add(nis)
        seen_ids.add(municipality_id)
        seen_relations.add(relation_id)
    validate_authorization(payload.get("authorization"), "registry")
    return payload


def build_manifest_from_registry(registry: dict[str, Any], niscode: str, municipality_id: str) -> dict[str, Any]:
    matches = [
        row
        for row in registry["municipalities"]
        if row.get("niscode") == niscode and row.get("id") == municipality_id
    ]
    if len(matches) != 1:
        raise SystemExit(
            "MUNICIPALITY_ROAD_ACQUISITION_FAIL: municipality selection must match exactly one locked registry row"
        )
    source = registry["source"]
    return {
        "schema": SCHEMA,
        "municipality": matches[0],
        "source": {
            "provider": source["provider"],
            "license": source["license"],
            "endpoint": source["endpoint"],
            "query_scope": "administrative_relation",
            "highway_classes": list(HIGHWAY_CLASSES),
        },
        "game_frame": registry["game_frame"],
        "authorization": registry["authorization"],
    }


def read_manifest(path: Path) -> dict[str, Any]:
    payload = read_json_object(path, "manifest")
    if payload.get("schema") != SCHEMA:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: manifest schema drift")
    municipality = payload.get("municipality") or {}
    relation_id = municipality.get("osm_relation_id")
    if not isinstance(relation_id, int) or relation_id <= 0:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid OSM relation id")
    validate_authorization(payload.get("authorization"), "manifest")
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
                payload = json.load(response, object_pairs_hook=reject_duplicate_object_keys)
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


def write_manifest_from_registry(registry_path: Path, niscode: str, municipality_id: str, output: Path) -> None:
    registry = read_registry(registry_path)
    manifest = build_manifest_from_registry(registry, niscode, municipality_id)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(canonical_bytes(manifest) + b"\n")
    print(
        "MUNICIPALITY_ROAD_MANIFEST_GREEN: "
        f"nis={niscode} id={municipality_id} relation={manifest['municipality']['osm_relation_id']}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--municipality-nis")
    parser.add_argument("--municipality-id")
    parser.add_argument("--manifest-output", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--raw-output", type=Path)
    parser.add_argument("--game-output", type=Path)
    parser.add_argument("--receipt-output", type=Path)
    parser.add_argument("--retries", type=int, default=4)
    args = parser.parse_args()

    if args.registry is not None:
        if not args.municipality_nis or not args.municipality_id or args.manifest_output is None:
            parser.error("--registry requires --municipality-nis, --municipality-id and --manifest-output")
        write_manifest_from_registry(args.registry, args.municipality_nis, args.municipality_id, args.manifest_output)
        return 0

    if args.manifest is None or args.raw_output is None or args.game_output is None or args.receipt_output is None:
        parser.error("acquisition requires --manifest, --raw-output, --game-output and --receipt-output")

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
