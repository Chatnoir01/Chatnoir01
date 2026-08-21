#!/usr/bin/env python3
"""Build a deterministic OSM road-source catalog for Grand Bruxelles.

This is a source lookup index only. Presence in this catalog MUST NOT be treated as
render, collision, streaming, safe-spawn, or JOUABLE authorization.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-road-destination-catalog-v1"
SOURCE_FORMAT = "grand-bruxelles-osm-v1"


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def normalized_points(raw_points: Any) -> list[list[float]]:
    if not isinstance(raw_points, list) or len(raw_points) < 2:
        return []
    points: list[list[float]] = []
    for pair in raw_points:
        if not isinstance(pair, list) or len(pair) < 2:
            return []
        try:
            x = float(pair[0])
            z = float(pair[1])
        except (TypeError, ValueError):
            return []
        if not (abs(x) < float("inf") and abs(z) < float("inf")):
            return []
        points.append([x, z])
    return points


def road_signature(road: dict[str, Any]) -> dict[str, Any] | None:
    try:
        osm_id = int(road.get("osm_id", 0))
    except (TypeError, ValueError):
        return None
    name = str(road.get("name", "")).strip()
    drivable = road.get("drivable") is True
    points = normalized_points(road.get("points"))
    if osm_id <= 0 or not name or not drivable or len(points) < 2:
        return None
    try:
        width = float(road.get("width", 0.0))
    except (TypeError, ValueError):
        width = 0.0
    return {
        "osm_id": osm_id,
        "name": name,
        "class": str(road.get("class", "")).strip(),
        "width": width,
        "drivable": True,
        "points": points,
    }


def discover_documents(source_root: Path) -> list[Path]:
    return sorted(path for path in source_root.rglob("*.game.json") if path.is_file())


def build_catalog(source_root: Path) -> dict[str, Any]:
    source_root = source_root.resolve()
    documents = discover_documents(source_root)
    entries: dict[int, dict[str, Any]] = {}
    document_digests: dict[str, str] = {}
    compatible_documents = 0
    road_record_count = 0
    drivable_record_count = 0
    eligible_record_count = 0
    rejected_drivable_record_count = 0
    duplicate_record_count = 0

    for path in documents:
        try:
            raw_text = path.read_text(encoding="utf-8")
            document = json.loads(raw_text)
        except (OSError, json.JSONDecodeError) as exc:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: invalid JSON {path}: {exc}") from exc
        if not isinstance(document, dict) or document.get("format") != SOURCE_FORMAT:
            continue
        roads = document.get("roads")
        if not isinstance(roads, list):
            continue
        compatible_documents += 1
        relative = path.relative_to(source_root.parent.parent).as_posix()
        document_digests[relative] = hashlib.sha256(raw_text.encode("utf-8")).hexdigest()
        for raw_road in roads:
            if not isinstance(raw_road, dict):
                continue
            road_record_count += 1
            is_drivable = raw_road.get("drivable") is True
            if is_drivable:
                drivable_record_count += 1
            signature = road_signature(raw_road)
            if signature is None:
                if is_drivable:
                    rejected_drivable_record_count += 1
                continue
            eligible_record_count += 1
            osm_id = int(signature["osm_id"])
            geometry_sha256 = sha256_text(canonical_json(signature["points"]))
            semantic = {
                "osm_id": osm_id,
                "name": signature["name"],
                "class": signature["class"],
                "width": signature["width"],
                "drivable": True,
                "point_count": len(signature["points"]),
                "geometry_sha256": geometry_sha256,
            }
            existing = entries.get(osm_id)
            if existing is None:
                entries[osm_id] = {**semantic, "source_paths": [relative]}
                continue
            existing_semantic = {key: existing[key] for key in semantic}
            if existing_semantic != semantic:
                raise SystemExit(
                    "ROAD_DESTINATION_CATALOG_FAIL: conflicting duplicate OSM road "
                    f"{osm_id}: {existing_semantic!r} != {semantic!r}"
                )
            duplicate_record_count += 1
            if relative not in existing["source_paths"]:
                existing["source_paths"].append(relative)
                existing["source_paths"].sort()

    ordered_entries: dict[str, Any] = {}
    for osm_id in sorted(entries):
        entry = dict(entries[osm_id])
        entry["source_file_count"] = len(entry["source_paths"])
        ordered_entries[str(osm_id)] = entry

    payload = {
        "format": FORMAT,
        "source_format": SOURCE_FORMAT,
        "source_root": "data/osm",
        "road_record_count": road_record_count,
        "drivable_record_count": drivable_record_count,
        "eligible_record_count": eligible_record_count,
        "rejected_drivable_record_count": rejected_drivable_record_count,
        "entry_count": len(ordered_entries),
        "duplicate_record_count": duplicate_record_count,
        "compatible_document_count": compatible_documents,
        "source_document_sha256": dict(sorted(document_digests.items())),
        "entries": ordered_entries,
        "authorization": {
            "source_lookup_only": True,
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        },
    }
    payload["catalog_sha256"] = sha256_text(canonical_json(payload))
    return payload


def validate_contract(catalog: dict[str, Any]) -> None:
    if catalog.get("format") != FORMAT:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: format drift")
    entries = catalog.get("entries")
    if not isinstance(entries, dict) or len(entries) < 1:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: no eligible source roads")
    eligible = int(catalog.get("eligible_record_count", -1))
    entry_count = int(catalog.get("entry_count", -2))
    duplicates = int(catalog.get("duplicate_record_count", -3))
    drivable = int(catalog.get("drivable_record_count", -4))
    rejected = int(catalog.get("rejected_drivable_record_count", -5))
    if eligible != entry_count + duplicates:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: unique/duplicate accounting drift")
    if drivable != eligible + rejected:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: drivable/rejected accounting drift")
    authorization = catalog.get("authorization", {})
    for forbidden in (
        "render_authorized",
        "collision_authorized",
        "runtime_mount_authorized",
        "safe_spawn_authorized",
        "jouable_authorized",
    ):
        if authorization.get(forbidden) is not False:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: {forbidden} must stay false")
    if authorization.get("source_lookup_only") is not True:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source_lookup_only missing")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("data/osm"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    catalog = build_catalog(args.source_root)
    validate_contract(catalog)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "ROAD_DESTINATION_CATALOG_OK: "
        f"entries={catalog['entry_count']} eligible_records={catalog['eligible_record_count']} "
        f"drivable_records={catalog['drivable_record_count']} rejected_drivable={catalog['rejected_drivable_record_count']} "
        f"duplicate_records={catalog['duplicate_record_count']} documents={catalog['compatible_document_count']} "
        f"sha256={catalog['catalog_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
