#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
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
    "motorway", "trunk", "primary", "secondary", "tertiary", "unclassified",
    "residential", "living_street", "service",
)
CLOSED_KEYS = (
    "source_registration_authorized", "road_cell_mapping_authorized", "render_authorized",
    "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized",
)
AUTHORIZATION_KEYS = frozenset(("source_acquisition_authorized",) + CLOSED_KEYS)
LOCKED_REGISTRY_SCOPE = "Brussels-Capital Region"
LOCKED_EVIDENCE_BASELINE = {
    "registered_niscodes": ["21001", "21004", "21013"],
    "missing_niscodes": [
        "21002", "21003", "21005", "21006", "21007", "21008", "21009", "21010",
        "21011", "21012", "21014", "21015", "21016", "21017", "21018", "21019",
    ],
}
LOCKED_MUNICIPALITIES = [
    {"niscode":"21002","id":"auderghem","name":"Auderghem / Oudergem","osm_relation_id":58263},
    {"niscode":"21003","id":"berchem_sainte_agathe","name":"Berchem-Sainte-Agathe / Sint-Agatha-Berchem","osm_relation_id":60140},
    {"niscode":"21005","id":"etterbeek","name":"Etterbeek","osm_relation_id":58252},
    {"niscode":"21006","id":"evere","name":"Evere","osm_relation_id":60144},
    {"niscode":"21007","id":"forest","name":"Forest / Vorst","osm_relation_id":58249},
    {"niscode":"21008","id":"ganshoren","name":"Ganshoren","osm_relation_id":58257},
    {"niscode":"21009","id":"ixelles","name":"Ixelles / Elsene","osm_relation_id":58250},
    {"niscode":"21010","id":"jette","name":"Jette","osm_relation_id":58258},
    {"niscode":"21011","id":"koekelberg","name":"Koekelberg","osm_relation_id":58256},
    {"niscode":"21012","id":"molenbeek_saint_jean","name":"Molenbeek-Saint-Jean / Sint-Jans-Molenbeek","osm_relation_id":58255},
    {"niscode":"21014","id":"saint_josse_ten_noode","name":"Saint-Josse-ten-Noode / Sint-Joost-ten-Node","osm_relation_id":58262},
    {"niscode":"21015","id":"schaerbeek","name":"Schaerbeek / Schaarbeek","osm_relation_id":58260},
    {"niscode":"21016","id":"uccle","name":"Uccle / Ukkel","osm_relation_id":58253},
    {"niscode":"21017","id":"watermael_boitsfort","name":"Watermael-Boitsfort / Watermaal-Bosvoorde","osm_relation_id":58264},
    {"niscode":"21018","id":"woluwe_saint_lambert","name":"Woluwe-Saint-Lambert / Sint-Lambrechts-Woluwe","osm_relation_id":60167},
    {"niscode":"21019","id":"woluwe_saint_pierre","name":"Woluwe-Saint-Pierre / Sint-Pieters-Woluwe","osm_relation_id":60168},
]
LOCKED_REGISTRY_SOURCE = {
    "provider": "OpenStreetMap contributors via Overpass API",
    "license": "ODbL-1.0",
    "endpoint": "https://overpass-api.de/api/interpreter",
    "relation_reference": "OpenStreetMap WikiProject Belgium/Boundaries Brussels-Capital Region",
}
LOCKED_MANIFEST_SOURCE = {
    "provider": "OpenStreetMap contributors via Overpass API",
    "license": "ODbL-1.0",
    "endpoint": "https://overpass-api.de/api/interpreter",
    "query_scope": "administrative_relation",
    "highway_classes": list(HIGHWAY_CLASSES),
    "query_timeout_seconds": 120,
    "transport_timeout_seconds": 150,
}
LOCKED_GAME_FRAME = {"origin_lat": 50.8419,"origin_lon": 4.348,"axes": "X=east, Y=up, Z=south","units": "metres"}


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
    actual_keys = set(auth)
    if actual_keys != AUTHORIZATION_KEYS:
        unexpected = sorted(actual_keys - AUTHORIZATION_KEYS)
        missing = sorted(AUTHORIZATION_KEYS - actual_keys)
        details: list[str] = []
        if unexpected:
            details.append(f"unexpected {label} authorization keys: {','.join(unexpected)}")
        if missing:
            details.append(f"missing {label} authorization keys: {','.join(missing)}")
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: " + "; ".join(details))
    if auth.get("source_acquisition_authorized") is not True:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: source acquisition not authorized")
    for key in CLOSED_KEYS:
        if auth.get(key) is not False:
            raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: {label} opened {key}")
    return auth


def validate_exact_mapping(value: Any, expected: dict[str, Any], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or value != expected:
        raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: {label} drift")
    return value


def read_registry(path: Path) -> dict[str, Any]:
    payload = read_json_object(path, "registry")
    if payload.get("schema") != REGISTRY_SCHEMA:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: registry schema drift")
    if payload.get("scope") != LOCKED_REGISTRY_SCOPE:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: registry scope drift")
    validate_exact_mapping(payload.get("evidence_baseline"), LOCKED_EVIDENCE_BASELINE, "registry evidence baseline")
    validate_exact_mapping(payload.get("source"), LOCKED_REGISTRY_SOURCE, "registry source identity")
    validate_exact_mapping(payload.get("game_frame"), LOCKED_GAME_FRAME, "registry game frame")
    municipalities = payload.get("municipalities")
    if not isinstance(municipalities, list) or not municipalities:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid registry municipalities")
    if municipalities != LOCKED_MUNICIPALITIES:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: registry municipality identity drift")
    seen_nis: set[str] = set()
    seen_ids: set[str] = set()
    seen_relations: set[int] = set()
    for row in municipalities:
        nis = row.get("niscode")
        municipality_id = row.get("id")
        relation_id = row.get("osm_relation_id")
        if nis in seen_nis or municipality_id in seen_ids or relation_id in seen_relations:
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: duplicate registry municipality identity")
        seen_nis.add(nis)
        seen_ids.add(municipality_id)
        seen_relations.add(relation_id)
    if sorted(seen_nis) != sorted(LOCKED_EVIDENCE_BASELINE["missing_niscodes"]):
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: registry municipality accounting drift")
    validate_authorization(payload.get("authorization"), "registry")
    return payload


def build_manifest_from_registry(registry: dict[str, Any], niscode: str, municipality_id: str) -> dict[str, Any]:
    matches = [row for row in registry["municipalities"] if row.get("niscode") == niscode and row.get("id") == municipality_id]
    if len(matches) != 1:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: municipality selection must match exactly one locked registry row")
    return {"schema": SCHEMA,"municipality": matches[0],"source": dict(LOCKED_MANIFEST_SOURCE),"game_frame": dict(LOCKED_GAME_FRAME),"authorization": registry["authorization"]}


def read_manifest(path: Path) -> dict[str, Any]:
    payload = read_json_object(path, "manifest")
    if payload.get("schema") != SCHEMA:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: manifest schema drift")
    municipality = payload.get("municipality")
    if municipality not in LOCKED_MUNICIPALITIES:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: manifest municipality identity drift")
    validate_exact_mapping(payload.get("source"), LOCKED_MANIFEST_SOURCE, "manifest source identity")
    validate_exact_mapping(payload.get("game_frame"), LOCKED_GAME_FRAME, "manifest game frame")
    validate_authorization(payload.get("authorization"), "manifest")
    return payload


def build_query(manifest: dict[str, Any]) -> str:
    relation_id = int(manifest["municipality"]["osm_relation_id"])
    classes = "|".join(str(value) for value in manifest["source"]["highway_classes"])
    query_timeout_seconds = int(manifest["source"]["query_timeout_seconds"])
    return f"[out:json][timeout:{query_timeout_seconds}];\n" + f"rel({relation_id});\n" + "map_to_area->.municipality;\n" + f"way(area.municipality)[\"highway\"~\"^({classes})$\"];\n" + "out tags geom;"


def fetch(endpoint: str, query: str, retries: int, transport_timeout_seconds: int) -> dict[str, Any]:
    body = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(endpoint, data=body, headers={"User-Agent": USER_AGENT,"Content-Type": "application/x-www-form-urlencoded","Accept": "application/json"}, method="POST")
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=transport_timeout_seconds) as response:
                payload = json.load(response, object_pairs_hook=reject_duplicate_object_keys)
            if not isinstance(payload, dict) or not isinstance(payload.get("elements"), list):
                raise ValueError("unexpected Overpass response")
            return payload
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, json.JSONDecodeError, ValueError) as exc:
            if attempt >= retries:
                raise SystemExit(f"MUNICIPALITY_ROAD_ACQUISITION_FAIL: Overpass failed: {exc}") from exc
            time.sleep(min(2 ** attempt, 12))
    raise AssertionError("unreachable")


def validate_osm_base_timestamp(raw: dict[str, Any]) -> str:
    osm3s = raw.get("osm3s")
    timestamp = osm3s.get("timestamp_osm_base") if isinstance(osm3s, dict) else None
    if not isinstance(timestamp, str) or not timestamp.strip():
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: missing OSM base timestamp")
    timestamp = timestamp.strip()
    try:
        parsed = datetime.fromisoformat(timestamp.replace("Z", "+00:00"))
    except ValueError as exc:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid OSM base timestamp") from exc
    if not timestamp.endswith("Z") or parsed.tzinfo is None or parsed.utcoffset() != timezone.utc.utcoffset(parsed):
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid OSM base timestamp")
    return timestamp


def validate_overpass_road_elements(raw: dict[str, Any]) -> None:
    elements = raw.get("elements")
    if not isinstance(elements, list) or not elements:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid Overpass elements")
    seen_way_ids: set[int] = set()
    for element in elements:
        if not isinstance(element, dict) or element.get("type") != "way":
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid Overpass road element")
        way_id = element.get("id")
        if isinstance(way_id, bool) or not isinstance(way_id, int) or way_id <= 0:
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid OSM way id")
        if way_id in seen_way_ids:
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: duplicate OSM way id")
        seen_way_ids.add(way_id)
        tags = element.get("tags")
        highway = tags.get("highway") if isinstance(tags, dict) else None
        if highway not in HIGHWAY_CLASSES:
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid highway class")


def validate_wgs84_geometry(raw: dict[str, Any]) -> None:
    elements = raw.get("elements")
    if not isinstance(elements, list):
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid Overpass elements")
    for element in elements:
        if not isinstance(element, dict) or element.get("type") != "way":
            continue
        geometry = element.get("geometry")
        if not isinstance(geometry, list) or not geometry:
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid WGS84 geometry")
        distinct_positions: set[tuple[float, float]] = set()
        for point in geometry:
            if not isinstance(point, dict):
                raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid WGS84 coordinate")
            lat = point.get("lat")
            lon = point.get("lon")
            if (
                isinstance(lat, bool)
                or isinstance(lon, bool)
                or not isinstance(lat, (int, float))
                or not isinstance(lon, (int, float))
                or not math.isfinite(float(lat))
                or not math.isfinite(float(lon))
                or not -90.0 <= float(lat) <= 90.0
                or not -180.0 <= float(lon) <= 180.0
            ):
                raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: invalid WGS84 coordinate")
            distinct_positions.add((float(lat), float(lon)))
        if len(distinct_positions) < 2:
            raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: degenerate WGS84 geometry")


def build_outputs(manifest: dict[str, Any], raw: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    osm_base_timestamp = validate_osm_base_timestamp(raw)
    validate_overpass_road_elements(raw)
    validate_wgs84_geometry(raw)
    frame = manifest["game_frame"]
    origin = (float(frame["origin_lat"]), float(frame["origin_lon"]))
    converted = convert(raw, origin)
    roads = converted.get("roads") or []
    if not roads or int(converted["stats"]["drivable_roads"]) <= 0:
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: source produced no drivable roads")
    if int(converted["stats"]["drivable_roads"]) != len(roads):
        raise SystemExit("MUNICIPALITY_ROAD_ACQUISITION_FAIL: non-drivable road escaped allowlist")
    raw_digest = sha256(canonical_bytes(raw))
    game_source = {**converted,"municipality": manifest["municipality"],"acquisition": {"schema": SCHEMA,"query": build_query(manifest),"raw_snapshot_sha256": raw_digest,"osm_base_timestamp": osm_base_timestamp},"authorization": {"source_registration_authorized": False,"road_cell_mapping_authorized": False,"render_authorized": False,"collision_authorized": False,"runtime_mount_authorized": False,"safe_spawn_authorized": False,"jouable_authorized": False}}
    game_digest = sha256(canonical_bytes(game_source))
    receipt = {"schema": RECEIPT_SCHEMA,"municipality": manifest["municipality"],"source": manifest["source"],"raw_snapshot_sha256": raw_digest,"normalized_game_source_sha256": game_digest,"road_count": len(roads),"point_count": sum(len(row.get("points") or []) for row in roads),"osm_base_timestamp": game_source["acquisition"]["osm_base_timestamp"],"authorization": game_source["authorization"]}
    return game_source, receipt


def write_manifest_from_registry(registry_path: Path, niscode: str, municipality_id: str, output: Path) -> None:
    registry = read_registry(registry_path)
    manifest = build_manifest_from_registry(registry, niscode, municipality_id)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(canonical_bytes(manifest) + b"\n")
    print("MUNICIPALITY_ROAD_MANIFEST_GREEN: " f"nis={niscode} id={municipality_id} relation={manifest['municipality']['osm_relation_id']}")


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
    raw = fetch(
        str(manifest["source"]["endpoint"]),
        query,
        max(1, args.retries),
        int(manifest["source"]["transport_timeout_seconds"]),
    )
    game_source, receipt = build_outputs(manifest, raw)
    for path in (args.raw_output, args.game_output, args.receipt_output):
        path.parent.mkdir(parents=True, exist_ok=True)
    args.raw_output.write_bytes(canonical_bytes(raw) + b"\n")
    args.game_output.write_bytes(canonical_bytes(game_source) + b"\n")
    args.receipt_output.write_bytes(canonical_bytes(receipt) + b"\n")
    print("MUNICIPALITY_ROAD_ACQUISITION_GREEN: " f"nis={manifest['municipality']['niscode']} roads={receipt['road_count']} points={receipt['point_count']} sha256={receipt['normalized_game_source_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())