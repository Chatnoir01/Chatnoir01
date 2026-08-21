#!/usr/bin/env python3
"""Report whether a catalogue zone is ready for City Machine onboarding.

This audit is deliberately fail-closed. It never promotes a zone and never
fills missing source facts. A zone is READY only when the same contracts used
by City Machine v4 are already explicit and complete.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
REGISTRY = HERE / "registry.json"
CATALOG = PROJECT / "data/qa/playable_zone_catalog.json"
REQUIRED_SLUGS = ("buildings", "street_surfaces", "street_axes", "train_network")
OSM_CACHE_FORMAT = "grand-bruxelles-osm-zone-environment-cache-v1"
OSM_RUNTIME_FORMAT = "grand-bruxelles-osm-zone-environment-v1"


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    return value if isinstance(value, dict) else {}


def zone_from_catalog(zone_id: str) -> dict[str, Any]:
    catalog = read_json(CATALOG)
    for row in catalog.get("zones", []):
        if isinstance(row, dict) and row.get("id") == zone_id:
            return row
    return {}


def source_root_for(zone_id: str, profile: dict[str, Any]) -> Path | None:
    raw = str(profile.get("source_root", "")).strip()
    if raw:
        path = PROJECT / raw
        return path if path.is_dir() else None
    candidates = [PROJECT / "data/urbis" / zone_id]
    for path in candidates:
        if path.is_dir():
            return path
    return None


def add(blockers: list[str], item: str) -> None:
    if item not in blockers:
        blockers.append(item)


def audit(zone_id: str) -> dict[str, Any]:
    zone = zone_from_catalog(zone_id)
    if not zone:
        return {"format": "grand-bruxelles-city-machine-readiness-v1", "zone": zone_id, "status": "BLOCKED", "blockers": ["catalog_zone_missing"], "evidence": {}}

    registry = read_json(REGISTRY)
    profiles = registry.get("zone_profiles", {}) if isinstance(registry.get("zone_profiles"), dict) else {}
    profile = profiles.get(zone_id, {}) if isinstance(profiles.get(zone_id, {}), dict) else {}
    blockers: list[str] = []
    evidence: dict[str, Any] = {
        "catalog_quality": zone.get("quality"),
        "catalog_mode": zone.get("mode"),
        "profile_registered": bool(profile),
    }

    if not profile:
        add(blockers, "city_machine_profile_missing")

    root = source_root_for(zone_id, profile)
    evidence["source_root"] = str(root.relative_to(PROJECT)) if root else None
    if root is None:
        add(blockers, "authoritative_source_root_missing")
        manifest: dict[str, Any] = {}
    else:
        manifest = read_json(root / "manifest.json")
        if not manifest:
            add(blockers, "source_manifest_missing_or_invalid")
        for slug in REQUIRED_SLUGS:
            if not (root / f"{slug}.geojson").is_file():
                add(blockers, f"source_{slug}_missing")
            if not (root / f"{slug}.game.json").is_file():
                add(blockers, f"runtime_{slug}_missing")

    if manifest:
        explicit_crs = str(manifest.get("source_crs", ""))
        legacy_crs = str(manifest.get("crs", ""))
        evidence["manifest_source_crs"] = explicit_crs or None
        evidence["legacy_crs_evidence"] = legacy_crs or None
        if explicit_crs != "EPSG:31370":
            add(blockers, "source_crs_contract_missing_or_invalid")
        license_text = str(manifest.get("source_license", "")).strip()
        evidence["source_license"] = license_text or None
        if not license_text:
            add(blockers, "source_license_contract_missing")
        origin = manifest.get("game_origin", {})
        valid_origin = (
            isinstance(origin, dict)
            and all(k in origin for k in ("e", "n", "altitude"))
            and origin.get("units") == "metres"
            and origin.get("axes") == "X=east, Y=up, Z=south"
        )
        evidence["game_origin_contract"] = origin if isinstance(origin, dict) and origin else None
        if not valid_origin:
            add(blockers, "game_origin_contract_missing_or_invalid")

    mode = str(zone.get("mode", ""))
    spawn = zone.get("spawn")
    if isinstance(spawn, list) and len(spawn) >= 3:
        evidence["arrival_contract"] = {"mode": "catalog_spawn", "position": spawn[:3]}
    else:
        evidence["arrival_contract"] = {"mode": mode or None, "destination": zone.get("destination"), "method": zone.get("method")}
        add(blockers, "source_bounded_arrival_position_unresolved")

    validator = str(profile.get("validator_script", "")).strip()
    runtime_script = str(profile.get("runtime_script", "")).strip()
    if not validator or not (PROJECT / validator).is_file():
        add(blockers, "validator_contract_missing")
    if not runtime_script or not (PROJECT / runtime_script).is_file():
        add(blockers, "runtime_finish_contract_missing")

    env = profile.get("osm_environment", {}) if isinstance(profile.get("osm_environment"), dict) else {}
    cache_path = PROJECT / str(env.get("cache", f"data/osm/zones/{zone_id}/environment.raw.json"))
    runtime_path = PROJECT / str(env.get("runtime", f"data/osm/zones/{zone_id}/environment.game.json"))
    evidence["osm_cache_path"] = str(cache_path.relative_to(PROJECT))
    evidence["osm_runtime_path"] = str(runtime_path.relative_to(PROJECT))

    cache = read_json(cache_path)
    runtime = read_json(runtime_path)
    if not cache:
        add(blockers, "full_zone_osm_cache_missing")
    elif cache.get("format") != OSM_CACHE_FORMAT:
        add(blockers, "full_zone_osm_cache_contract_invalid")

    if not runtime:
        add(blockers, "full_zone_osm_runtime_missing")
    else:
        if runtime.get("coverage_complete") is False:
            add(blockers, "partial_osm_environment_not_eligible")
        if runtime.get("format") != OSM_RUNTIME_FORMAT:
            add(blockers, "full_zone_osm_runtime_contract_invalid")
        if runtime.get("projection_crs") != "EPSG:31370":
            add(blockers, "osm_projection_contract_missing_or_invalid")
        bbox = runtime.get("bbox_31370")
        if not isinstance(bbox, list) or len(bbox) != 4:
            add(blockers, "osm_bbox_contract_missing_or_invalid")
        if not str(runtime.get("source_digest", "")).strip():
            add(blockers, "osm_source_digest_missing")
        if not str(runtime.get("license", "")).strip():
            add(blockers, "osm_license_missing")

    blockers.sort()
    return {
        "format": "grand-bruxelles-city-machine-readiness-v1",
        "zone": zone_id,
        "status": "READY" if not blockers else "BLOCKED",
        "blockers": blockers,
        "evidence": evidence,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zone", required=True)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    result = audit(args.zone)
    if args.json:
        print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    else:
        print(f"CITY_MACHINE_READINESS zone={result['zone']} status={result['status']} blockers={len(result['blockers'])}")
        for blocker in result["blockers"]:
            print(f"BLOCKER {blocker}")
    return 0 if result["status"] == "READY" else 4


if __name__ == "__main__":
    raise SystemExit(main())
