#!/usr/bin/env python3
"""Build the deterministic runtime discovery index for City Machine environment layers."""
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
REGISTRY = HERE / "registry.json"
DEFAULT_OUTPUT = PROJECT / "data/runtime/runtime_environment_index.json"
INDEX_FORMAT = "grand-bruxelles-runtime-environment-index-v1"
ARTIFACT_FORMAT = "grand-bruxelles-osm-zone-environment-v1"
OSM_SOURCE = "OpenStreetMap contributors via Overpass API"
OSM_LICENSE = "ODbL-1.0"
SUPPORTED_KINDS = ("tree", "street_lamp", "bollard")


class EnvironmentIndexError(RuntimeError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise EnvironmentIndexError(f"cannot read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise EnvironmentIndexError(f"expected JSON object: {path}")
    return value


def project_path(raw: str) -> Path:
    path = (PROJECT / raw).resolve()
    root = PROJECT.resolve()
    if path != root and root not in path.parents:
        raise EnvironmentIndexError(f"path escapes project: {raw}")
    return path


def validate_artifact(zone_id: str, artifact: dict[str, Any]) -> dict[str, Any]:
    if artifact.get("format") != ARTIFACT_FORMAT:
        raise EnvironmentIndexError(f"{zone_id}: unsupported environment artifact format")
    if artifact.get("zone") != zone_id:
        raise EnvironmentIndexError(f"{zone_id}: environment artifact zone mismatch")
    if artifact.get("source") != OSM_SOURCE or artifact.get("license") != OSM_LICENSE:
        raise EnvironmentIndexError(f"{zone_id}: OSM source/license contract mismatch")
    if artifact.get("projection_crs") != "EPSG:31370":
        raise EnvironmentIndexError(f"{zone_id}: environment artifact is not EPSG:31370 projected")

    bounds = artifact.get("bounds_m")
    if not isinstance(bounds, list) or len(bounds) != 4:
        raise EnvironmentIndexError(f"{zone_id}: environment bounds missing")
    bounds_m = [float(value) for value in bounds]
    if bounds_m[0] > bounds_m[2] or bounds_m[1] > bounds_m[3]:
        raise EnvironmentIndexError(f"{zone_id}: invalid environment bounds")

    stats = artifact.get("stats")
    if not isinstance(stats, dict):
        raise EnvironmentIndexError(f"{zone_id}: environment stats missing")
    normalized_stats = {kind: int(stats.get(kind, -1)) for kind in SUPPORTED_KINDS}
    normalized_stats["total"] = int(stats.get("total", -1))
    if any(normalized_stats[kind] < 0 for kind in (*SUPPORTED_KINDS, "total")):
        raise EnvironmentIndexError(f"{zone_id}: negative environment stats")
    if sum(normalized_stats[kind] for kind in SUPPORTED_KINDS) != normalized_stats["total"]:
        raise EnvironmentIndexError(f"{zone_id}: environment stats do not sum to total")
    if normalized_stats["tree"] <= 0:
        raise EnvironmentIndexError(f"{zone_id}: environment artifact has no trees")

    return {
        "artifact_format": ARTIFACT_FORMAT,
        "bounds_m": bounds_m,
        "stats": normalized_stats,
    }


def build_index(registry_path: Path = REGISTRY) -> dict[str, Any]:
    registry = read_json(registry_path)
    if registry.get("schema") != "grand-bruxelles-city-machine-registry-v1":
        raise EnvironmentIndexError("unsupported City Machine registry")
    profiles = registry.get("zone_profiles")
    if not isinstance(profiles, dict):
        raise EnvironmentIndexError("City Machine zone_profiles missing")

    entries: list[dict[str, Any]] = []
    seen_paths: set[str] = set()
    for zone_id in sorted(str(value) for value in profiles):
        profile = profiles.get(zone_id)
        if not isinstance(profile, dict):
            raise EnvironmentIndexError(f"{zone_id}: invalid zone profile")
        environment = profile.get("osm_environment")
        if environment is None:
            continue
        if not isinstance(environment, dict):
            raise EnvironmentIndexError(f"{zone_id}: invalid osm_environment profile")
        runtime_raw = str(environment.get("runtime", "")).strip()
        if not runtime_raw:
            raise EnvironmentIndexError(f"{zone_id}: environment runtime path missing")
        if runtime_raw in seen_paths:
            raise EnvironmentIndexError(f"duplicate environment runtime path: {runtime_raw}")
        seen_paths.add(runtime_raw)
        artifact_path = project_path(runtime_raw)
        artifact = read_json(artifact_path)
        contract = validate_artifact(zone_id, artifact)
        entries.append({
            "zone": zone_id,
            "data_path": "res://" + runtime_raw,
            **contract,
        })

    if not entries:
        raise EnvironmentIndexError("no runtime environment layers available")
    return {
        "format": INDEX_FORMAT,
        "visual_only": True,
        "promotion_authorized_by_index": False,
        "source_registry": "tools/city_machine/registry.json",
        "entries": entries,
    }


def write_index(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build deterministic City Machine environment runtime index")
    parser.add_argument("--registry", type=Path, default=REGISTRY)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()
    value = build_index(args.registry)
    write_index(args.output, value)
    print(f"RUNTIME_ENVIRONMENT_INDEX_OK zones={len(value['entries'])} output={args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
