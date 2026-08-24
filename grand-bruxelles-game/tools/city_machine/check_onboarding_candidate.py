#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
CANDIDATES = HERE / "onboarding_candidates.json"
CATALOG = PROJECT / "data/qa/playable_zone_catalog.json"
OSM_SOURCE = "OpenStreetMap contributors via Overpass API"
OSM_LICENSE = "ODbL-1.0"


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"expected object: {path}")
    return value


def canonical_digest(value: dict[str, Any]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
    return hashlib.sha256(raw).hexdigest()


def project_path(raw: str) -> Path:
    path = (PROJECT / raw).resolve()
    if PROJECT.resolve() not in path.parents:
        raise RuntimeError(f"path escapes project: {raw}")
    return path


def check(name: str, passed: bool, detail: str) -> dict[str, Any]:
    return {"id": name, "status": "PASS" if passed else "FAIL", "detail": detail}


def parse_vector3(text: str, symbol: str) -> list[float] | None:
    match = re.search(rf"const\s+{re.escape(symbol)}\s*:=\s*Vector3\(([^)]+)\)", text)
    if not match:
        return None
    try:
        values = [float(v.strip()) for v in match.group(1).split(",")]
    except ValueError:
        return None
    return values if len(values) == 3 else None


def parse_float_const(text: str, symbol: str) -> float | None:
    match = re.search(rf"const\s+{re.escape(symbol)}\s*:=\s*(-?\d+(?:\.\d+)?)", text)
    return float(match.group(1)) if match else None


def zone_from_catalog(zone_id: str) -> dict[str, Any] | None:
    for zone in read_json(CATALOG).get("zones", []):
        if isinstance(zone, dict) and zone.get("id") == zone_id:
            return zone
    return None


def run(zone_id: str) -> dict[str, Any]:
    registry = read_json(CANDIDATES)
    candidate = (registry.get("candidates") or {}).get(zone_id)
    if not isinstance(candidate, dict):
        raise RuntimeError(f"unknown onboarding candidate: {zone_id}")

    checks: list[dict[str, Any]] = []

    manifest_path = project_path(candidate["source_manifest"])
    manifest = read_json(manifest_path) if manifest_path.is_file() else {}
    crs = (manifest.get("coordinate_policy") or {}).get("authoritative_crs")
    checks.append(check("source_crs", crs == candidate["expected_crs"], f"manifest={candidate['source_manifest']} crs={crs}"))

    city_manifest_path = project_path(candidate["city_machine_source_manifest"])
    city_manifest = read_json(city_manifest_path) if city_manifest_path.is_file() else {}
    origin = city_manifest.get("game_origin") or {}
    city_contract_ok = (
        city_manifest.get("source_crs") == candidate["expected_crs"]
        and [float(v) for v in city_manifest.get("bbox", [])] == [float(v) for v in candidate["expected_bbox"]]
        and float(origin.get("e", 0.0)) == float(candidate["expected_game_origin"]["e"])
        and float(origin.get("n", 0.0)) == float(candidate["expected_game_origin"]["n"])
        and bool(str(city_manifest.get("source_license", "")).strip())
    )
    checks.append(check("city_machine_source_contract", city_contract_ok, f"bbox={city_manifest.get('bbox')} origin={origin}"))

    zone = zone_from_catalog(zone_id)
    expected_mode = candidate["catalog_mode"]
    expected_destination = candidate["catalog_destination"]
    catalog_ok = bool(zone) and zone.get("mode") == expected_mode and zone.get("destination") == expected_destination
    checks.append(check("catalog_arrival_contract", catalog_ok, f"mode={zone.get('mode') if zone else None} destination={zone.get('destination') if zone else None}"))

    runtime_path = project_path(candidate["runtime_script"])
    runtime_text = runtime_path.read_text(encoding="utf-8") if runtime_path.is_file() else ""
    arrival = candidate["arrival"]
    position = parse_vector3(runtime_text, arrival["position_symbol"])
    yaw = parse_float_const(runtime_text, arrival["yaw_symbol"])
    position_ok = position is not None and all(abs(a - b) <= 1e-6 for a, b in zip(position, arrival["position"]))
    yaw_ok = yaw is not None and abs(yaw - float(arrival["yaw_deg"])) <= 1e-6
    checks.append(check("runtime_arrival_pose", position_ok and yaw_ok, f"position={position} yaw_deg={yaw}"))

    osm = candidate["regional_osm"]
    cache_path = project_path(osm["required_cache"])
    regional_runtime_path = project_path(osm["required_runtime"])
    cache = read_json(cache_path) if cache_path.is_file() else {}
    regional_runtime = read_json(regional_runtime_path) if regional_runtime_path.is_file() else {}
    bbox = [float(v) for v in candidate["expected_bbox"]]
    cache_ok = (
        cache_path.is_file()
        and cache.get("format") == "grand-bruxelles-osm-zone-environment-cache-v1"
        and cache.get("source") == OSM_SOURCE
        and cache.get("license") == OSM_LICENSE
    )
    checks.append(check("regional_osm_cache", cache_ok, f"required={osm['required_cache']} format={cache.get('format')} license={cache.get('license')}"))
    runtime_ok = (
        regional_runtime_path.is_file()
        and regional_runtime.get("format") == "grand-bruxelles-osm-zone-environment-v1"
        and regional_runtime.get("source") == OSM_SOURCE
        and regional_runtime.get("license") == OSM_LICENSE
        and regional_runtime.get("zone") == zone_id
        and [float(v) for v in regional_runtime.get("bbox_31370", [])] == bbox
        and regional_runtime.get("source_digest") == canonical_digest(cache)
        and int((regional_runtime.get("stats") or {}).get("total", -1)) == len(regional_runtime.get("environment_points") or [])
    )
    checks.append(check("regional_osm_runtime", runtime_ok, f"required={osm['required_runtime']} bbox={regional_runtime.get('bbox_31370')} total={(regional_runtime.get('stats') or {}).get('total')}"))

    partial_path = project_path(osm["forbidden_partial_substitute"])
    partial = read_json(partial_path) if partial_path.is_file() else {}
    source_stats = partial.get("source_stats") or {}
    selected_stats = partial.get("stats") or {}
    corridor = partial.get("corridor") or {}
    source_roads = int(source_stats.get("roads", 0))
    selected_roads = int(selected_stats.get("roads", 0))
    corridor_name = str(corridor.get("name", ""))
    proven_partial = partial_path.is_file() and source_roads > selected_roads > 0 and "Midi" in corridor_name
    checks.append(check("partial_slice_rejected", proven_partial, f"corridor={corridor_name!r} roads={selected_roads}/{source_roads}; partial selection is never regional coverage"))

    runtime_contract = candidate["runtime_data_contract"]
    builder_path = project_path(runtime_contract["builder_script"])
    builder_text = builder_path.read_text(encoding="utf-8") if builder_path.is_file() else ""
    missing_inputs = [token for token in runtime_contract["required_normalized_inputs"] if token not in builder_text]
    checks.append(check(
        "runtime_consumes_city_machine_outputs",
        not missing_inputs,
        f"builder={runtime_contract['builder_script']} missing_inputs={missing_inputs}"
    ))

    eligible = all(row["status"] == "PASS" for row in checks)
    failed = [row["id"] for row in checks if row["status"] == "FAIL"]
    return {
        "format": "grand-bruxelles-city-machine-onboarding-preflight-v1",
        "zone": zone_id,
        "eligible": eligible,
        "result": "READY_FOR_PROFILE" if eligible else "BLOCKED_FAIL_CLOSED",
        "failed_checks": failed,
        "checks": checks,
        "promotion_performed": False
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zone", required=True)
    parser.add_argument("--output")
    parser.add_argument("--allow-blocked", action="store_true")
    args = parser.parse_args()
    result = run(args.zone)
    raw = json.dumps(result, indent=2, sort_keys=True, ensure_ascii=False) + "\n"
    if args.output:
        Path(args.output).write_text(raw, encoding="utf-8")
    print(raw, end="")
    return 0 if result["eligible"] or args.allow_blocked else 2


if __name__ == "__main__":
    raise SystemExit(main())
