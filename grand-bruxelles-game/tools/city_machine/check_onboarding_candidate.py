#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from collections import Counter
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
CANDIDATES = HERE / "onboarding_candidates.json"
CATALOG = PROJECT / "data/qa/playable_zone_catalog.json"
OSM_SOURCE = "OpenStreetMap contributors via Overpass API"
OSM_LICENSE = "ODbL-1.0"
OSM_KINDS = {"tree", "street_lamp", "bollard"}


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError(f"expected object: {path}")
    return value


def canonical_digest(value: dict[str, Any]) -> str:
    raw = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def project_path(raw: str) -> Path:
    path = (PROJECT / raw).resolve()
    if path != PROJECT.resolve() and PROJECT.resolve() not in path.parents:
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


def game_bounds(manifest: dict[str, Any]) -> tuple[float, float, float, float] | None:
    bbox = manifest.get("bbox")
    origin = manifest.get("game_origin")
    if not isinstance(bbox, list) or len(bbox) != 4 or not isinstance(origin, dict):
        return None
    if "e" not in origin or "n" not in origin:
        return None
    try:
        bbox_values = [float(v) for v in bbox]
        origin_e = float(origin["e"])
        origin_n = float(origin["n"])
    except (TypeError, ValueError):
        return None
    xs = (bbox_values[0] - origin_e, bbox_values[2] - origin_e)
    zs = (-(bbox_values[1] - origin_n), -(bbox_values[3] - origin_n))
    return min(xs), min(zs), max(xs), max(zs)


def validate_regional_osm(zone_id: str, candidate: dict[str, Any], cache_path: Path, runtime_path: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    if not cache_path.is_file() or not runtime_path.is_file():
        return rows

    cache = read_json(cache_path)
    runtime = read_json(runtime_path)
    execution_manifest = read_json(project_path(candidate["execution_manifest"]))

    cache_contract_ok = (
        cache.get("format") == "grand-bruxelles-osm-zone-environment-cache-v1"
        and cache.get("source") == OSM_SOURCE
        and cache.get("license") == OSM_LICENSE
        and isinstance(cache.get("elements"), list)
        and isinstance(cache.get("counts"), dict)
    )
    rows.append(check(
        "regional_osm_cache_contract",
        cache_contract_ok,
        f"format={cache.get('format')} source={cache.get('source')!r} license={cache.get('license')!r} elements={len(cache.get('elements') or [])}",
    ))

    bbox_ok = [float(v) for v in runtime.get("bbox_31370", [])] == [float(v) for v in execution_manifest.get("bbox", [])]
    runtime_contract_ok = (
        runtime.get("format") == "grand-bruxelles-osm-zone-environment-v1"
        and runtime.get("zone") == zone_id
        and runtime.get("source") == OSM_SOURCE
        and runtime.get("license") == OSM_LICENSE
        and runtime.get("source_crs") == "EPSG:4326"
        and runtime.get("projection_crs") == candidate["expected_crs"]
        and runtime.get("bbox_wgs84") == cache.get("bbox_wgs84")
        and bbox_ok
        and isinstance(runtime.get("environment_points"), list)
        and isinstance(runtime.get("stats"), dict)
    )
    rows.append(check(
        "regional_osm_runtime_contract",
        runtime_contract_ok,
        f"format={runtime.get('format')} zone={runtime.get('zone')} projection={runtime.get('projection_crs')} bbox_match={bbox_ok}",
    ))

    expected_digest = canonical_digest(cache)
    digest_ok = runtime.get("source_digest") == expected_digest
    rows.append(check(
        "regional_osm_digest",
        digest_ok,
        f"runtime={runtime.get('source_digest')} expected={expected_digest}",
    ))

    points = runtime.get("environment_points") if isinstance(runtime.get("environment_points"), list) else []
    stats = runtime.get("stats") if isinstance(runtime.get("stats"), dict) else {}
    cache_counts = cache.get("counts") if isinstance(cache.get("counts"), dict) else {}
    counts: Counter[str] = Counter()
    bounds = game_bounds(execution_manifest)
    point_contract_ok = bounds is not None
    tolerance = 2.0
    for point in points:
        if not isinstance(point, dict) or point.get("kind") not in OSM_KINDS:
            point_contract_ok = False
            continue
        pos = point.get("position")
        if not isinstance(pos, list) or len(pos) < 2:
            point_contract_ok = False
            continue
        try:
            x, z = map(float, pos[:2])
        except (TypeError, ValueError):
            point_contract_ok = False
            continue
        if bounds is not None:
            xmin, zmin, xmax, zmax = bounds
            if not (xmin - tolerance <= x <= xmax + tolerance and zmin - tolerance <= z <= zmax + tolerance):
                point_contract_ok = False
        counts[str(point["kind"])] += 1

    counts_ok = int(stats.get("total", -1)) == len(points) and len(points) > 0
    for kind in OSM_KINDS:
        counts_ok = counts_ok and int(stats.get(kind, -1)) == counts[kind] and int(cache_counts.get(kind, -1)) == counts[kind]
    counts_ok = counts_ok and counts["tree"] > 0
    bounds_detail = "missing_or_invalid"
    if bounds is not None:
        xmin, zmin, xmax, zmax = bounds
        bounds_detail = f"({xmin:.2f},{zmin:.2f})..({xmax:.2f},{zmax:.2f})"
    rows.append(check(
        "regional_osm_points_contract",
        point_contract_ok and counts_ok,
        f"total={len(points)} trees={counts['tree']} lamps={counts['street_lamp']} bollards={counts['bollard']} bounds={bounds_detail}",
    ))
    return rows


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

    execution_manifest_path = project_path(candidate["execution_manifest"])
    execution_manifest = read_json(execution_manifest_path) if execution_manifest_path.is_file() else {}
    execution_ok = (
        execution_manifest.get("source_crs") == candidate["expected_crs"]
        and isinstance(execution_manifest.get("bbox"), list)
        and len(execution_manifest.get("bbox", [])) == 4
        and (execution_manifest.get("game_origin") or {}).get("units") == "metres"
        and (execution_manifest.get("game_origin") or {}).get("axes") == "X=east, Y=up, Z=south"
        and bool(str(execution_manifest.get("source_license", "")).strip())
    )
    checks.append(check("execution_source_contract", execution_ok, f"manifest={candidate['execution_manifest']} crs={execution_manifest.get('source_crs')} bbox={execution_manifest.get('bbox')}"))

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
    checks.append(check("regional_osm_cache", cache_path.is_file(), f"required={osm['required_cache']}"))
    checks.append(check("regional_osm_runtime", regional_runtime_path.is_file(), f"required={osm['required_runtime']}"))
    checks.extend(validate_regional_osm(zone_id, candidate, cache_path, regional_runtime_path))

    partial_path = project_path(osm["forbidden_partial_substitute"])
    partial = read_json(partial_path) if partial_path.is_file() else {}
    source_stats = partial.get("source_stats") or {}
    selected_stats = partial.get("stats") or {}
    corridor = partial.get("corridor") or {}
    source_roads = int(source_stats.get("roads", 0))
    selected_roads = int(selected_stats.get("roads", 0))
    corridor_name = str(corridor.get("name", ""))
    proven_partial = partial_path.is_file() and source_roads > selected_roads > 0 and "Midi" in corridor_name
    checks.append(check(
        "partial_slice_rejected",
        proven_partial,
        f"corridor={corridor_name!r} roads={selected_roads}/{source_roads}; this artifact is evidence of partial selection only",
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
        "promotion_performed": False,
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