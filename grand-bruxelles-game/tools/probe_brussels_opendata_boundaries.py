#!/usr/bin/env python3
"""Probe official Brussels open-data datasets for named polygon areas.

Discovery candidates come from opendata.brussels.be. This probe downloads only
bounded-size datasets, scans scalar record fields for requested place names, and
accepts evidence only when the same record contains a GeoJSON Polygon or
MultiPolygon somewhere in its structured values. This prevents points, labels,
or prose-only matches from being promoted to boundary evidence.
"""

from __future__ import annotations

import argparse
import json
import re
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any, Iterable

API_ROOT = "https://opendata.brussels.be/api/explore/v2.1/catalog/datasets"
DISCOVERY_FORMAT = "grand-bruxelles-opendata-boundary-discovery-v1"
FORMAT = "grand-bruxelles-opendata-boundary-probe-v1"
ALLOWED_GEOMETRIES = {"Polygon", "MultiPolygon"}
DEFAULT_TARGETS = (
    "quartier européen",
    "european quarter",
    "léopold",
    "louise",
    "roosevelt",
    "bois de la cambre",
    "ter kamerenbos",
)


def request_json(url: str, timeout: int = 60) -> dict[str, Any]:
    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)",
            "Accept": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return json.loads(response.read().decode("utf-8"))


def normalized(value: object) -> str:
    text = str(value or "").casefold()
    replacements = str.maketrans({"é": "e", "è": "e", "ê": "e", "ë": "e", "à": "a", "â": "a", "ä": "a", "ï": "i", "î": "i", "ô": "o", "ö": "o", "ù": "u", "û": "u", "ü": "u", "ç": "c"})
    text = text.translate(replacements)
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return " ".join(text.split())


def scalar_match(value: object, target: str) -> bool:
    if not isinstance(value, (str, int, float)):
        return False
    candidate = normalized(value)
    wanted = normalized(target)
    return bool(wanted and (wanted in candidate or wanted.replace(" ", "") in candidate.replace(" ", "")))


def matching_scalar_fields(record: dict[str, Any], target: str) -> dict[str, str]:
    return {str(key): str(value) for key, value in record.items() if scalar_match(value, target)}


def iter_polygon_geometries(value: object, path: str = "$") -> Iterable[tuple[str, dict[str, Any]]]:
    if isinstance(value, dict):
        geometry_type = str(value.get("type") or "")
        if geometry_type in ALLOWED_GEOMETRIES and isinstance(value.get("coordinates"), list):
            yield path, value
        geometry = value.get("geometry")
        if isinstance(geometry, dict):
            yield from iter_polygon_geometries(geometry, path + ".geometry")
        for key, child in value.items():
            if key == "geometry":
                continue
            if isinstance(child, (dict, list)):
                yield from iter_polygon_geometries(child, path + "." + str(key))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            if isinstance(child, (dict, list)):
                yield from iter_polygon_geometries(child, f"{path}[{index}]")


def geometry_bbox(geometry: dict[str, Any]) -> list[float] | None:
    positions: list[tuple[float, float]] = []

    def walk(value: object) -> None:
        if not isinstance(value, list):
            return
        if len(value) >= 2 and isinstance(value[0], (int, float)) and isinstance(value[1], (int, float)):
            positions.append((float(value[0]), float(value[1])))
            return
        for child in value:
            walk(child)

    walk(geometry.get("coordinates"))
    if not positions:
        return None
    return [min(x for x, _ in positions), min(y for _, y in positions), max(x for x, _ in positions), max(y for _, y in positions)]


def records_url(dataset_id: str, limit: int, offset: int) -> str:
    encoded = urllib.parse.quote(dataset_id, safe="")
    return f"{API_ROOT}/{encoded}/records?" + urllib.parse.urlencode({"limit": str(limit), "offset": str(offset)})


def fetch_all_records(dataset_id: str, max_records: int, page_size: int = 100) -> tuple[list[dict[str, Any]], int]:
    first = request_json(records_url(dataset_id, 1, 0))
    total = int(first.get("total_count", 0))
    if total > max_records:
        return [], total
    results: list[dict[str, Any]] = []
    offset = 0
    while offset < total:
        payload = request_json(records_url(dataset_id, min(page_size, max(1, total - offset)), offset))
        page = payload.get("results") or []
        results.extend(item for item in page if isinstance(item, dict))
        if not page:
            break
        offset += len(page)
    return results, total


def inspect_records(dataset_id: str, records: list[dict[str, Any]], targets: list[str]) -> dict[str, Any]:
    target_matches: dict[str, list[dict[str, Any]]] = {target: [] for target in targets}
    for index, record in enumerate(records):
        polygon_entries = [(path, geometry) for path, geometry in iter_polygon_geometries(record)]
        if not polygon_entries:
            continue
        for target in targets:
            fields = matching_scalar_fields(record, target)
            if not fields:
                continue
            target_matches[target].append(
                {
                    "record_index": index,
                    "matching_fields": fields,
                    "polygon_geometries": [
                        {
                            "path": path,
                            "type": geometry.get("type"),
                            "bbox": geometry_bbox(geometry),
                        }
                        for path, geometry in polygon_entries
                    ],
                }
            )
    matched = [target for target in targets if target_matches[target]]
    return {
        "dataset_id": dataset_id,
        "records_downloaded": len(records),
        "matched_polygon_targets": matched,
        "target_matches": target_matches,
    }


def load_candidates(path: Path, max_candidates: int) -> list[dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != DISCOVERY_FORMAT:
        raise ValueError(f"unsupported discovery manifest: {path}")
    candidates = [item for item in payload.get("candidates", []) if isinstance(item, dict) and item.get("dataset_id")]
    return candidates[:max_candidates]


def main() -> int:
    parser = argparse.ArgumentParser(description="Probe Brussels open-data candidate datasets for polygon area names")
    parser.add_argument("--discovery", type=Path, required=True)
    parser.add_argument("--target", action="append", default=[])
    parser.add_argument("--max-records", type=int, default=2500)
    parser.add_argument("--max-candidates", type=int, default=25)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    targets = args.target or list(DEFAULT_TARGETS)
    results: list[dict[str, Any]] = []
    proven_by_target: dict[str, list[str]] = {target: [] for target in targets}
    for candidate in load_candidates(args.discovery, max(1, args.max_candidates)):
        dataset_id = str(candidate["dataset_id"])
        records, total = fetch_all_records(dataset_id, max(1, args.max_records))
        entry: dict[str, Any] = {
            "dataset_id": dataset_id,
            "title": str(candidate.get("title", "")),
            "license": str(candidate.get("license", "")),
            "total_records": total,
        }
        if total > args.max_records:
            entry["status"] = "skipped_record_limit"
            entry["matched_polygon_targets"] = []
        else:
            entry.update(inspect_records(dataset_id, records, targets))
            entry["status"] = "inspected"
            for target in entry["matched_polygon_targets"]:
                proven_by_target[target].append(dataset_id)
        results.append(entry)
        print(dataset_id, entry["status"], "records=", total, "polygon targets=", entry.get("matched_polygon_targets", []))

    output = {
        "format": FORMAT,
        "source": API_ROOT,
        "targets": targets,
        "max_records": args.max_records,
        "candidate_count_probed": len(results),
        "datasets_with_polygon_match_by_target": proven_by_target,
        "production_approved_datasets": {},
        "production_gate": "manual semantic/CRS/license validation required after polygon-name proof",
        "results": results,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("probe ->", args.output)
    print("polygon matches ->", proven_by_target)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
