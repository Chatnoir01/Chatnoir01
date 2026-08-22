#!/usr/bin/env python3
"""Fail-closed validator for source-backed Midi ambulance parking evidence."""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

FORMAT = "grand-bruxelles-midi-ambulance-parking-evidence-v1"
OSM_TYPES = {"node", "way", "relation"}
ALLOWED_TAGS = {
    ("amenity", "parking"),
    ("amenity", "parking_space"),
}
PARKING_PREFIXES = ("parking:left", "parking:right", "parking:both")


def fail(message: str) -> None:
    raise ValueError(message)


def load_json(path: Path) -> dict:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read JSON {path}: {exc}")
    if not isinstance(data, dict):
        fail("registry root must be an object")
    return data


def road_ids(snapshot: dict) -> set[int]:
    roads = snapshot.get("roads", [])
    if not isinstance(roads, list):
        fail("snapshot roads must be an array")
    result: set[int] = set()
    for road in roads:
        if isinstance(road, dict) and isinstance(road.get("osm_id"), int):
            result.add(int(road["osm_id"]))
    return result


def valid_osm_url(url: str, osm_type: str, osm_id: int) -> bool:
    parsed = urlparse(url)
    return (
        parsed.scheme == "https"
        and parsed.netloc in {"www.openstreetmap.org", "openstreetmap.org"}
        and parsed.path.rstrip("/") == f"/{osm_type}/{osm_id}"
        and not parsed.query
        and not parsed.fragment
    )


def validate_tag(key: str, value: str) -> None:
    key = key.strip()
    value = value.strip()
    if not key or not value:
        fail("parking evidence tag key/value must be non-empty")
    if (key, value) in ALLOWED_TAGS:
        return
    if any(key == prefix or key.startswith(prefix + ":") for prefix in PARKING_PREFIXES):
        return
    fail(f"unsupported parking evidence tag: {key}={value}")


def validate(registry: dict, snapshot: dict, require_ready: bool) -> dict:
    if registry.get("format") != FORMAT:
        fail(f"unexpected registry format: {registry.get('format')!r}")
    contract = registry.get("source_contract")
    if not isinstance(contract, dict) or contract.get("license") != "ODbL-1.0":
        fail("source contract must pin ODbL-1.0")
    target = registry.get("target")
    if not isinstance(target, dict):
        fail("target contract missing")
    required = int(target.get("required_distinct_road_count", 0))
    if required < 2:
        fail("at least two distinct source-backed roads are required")

    known_roads = road_ids(snapshot)
    candidates = registry.get("candidates")
    if not isinstance(candidates, list):
        fail("candidates must be an array")

    seen_evidence: set[str] = set()
    approved_roads: set[int] = set()
    for index, raw in enumerate(candidates):
        if not isinstance(raw, dict):
            fail(f"candidate[{index}] must be an object")
        evidence_id = str(raw.get("evidence_id", "")).strip()
        if not re.fullmatch(r"midi-parking-[a-z0-9][a-z0-9_-]*", evidence_id):
            fail(f"candidate[{index}] invalid evidence_id")
        if evidence_id in seen_evidence:
            fail(f"duplicate evidence_id: {evidence_id}")
        seen_evidence.add(evidence_id)

        road_osm_id = raw.get("road_osm_id")
        if not isinstance(road_osm_id, int) or road_osm_id <= 0:
            fail(f"candidate[{index}] road_osm_id must be a positive integer")
        if road_osm_id not in known_roads:
            fail(f"candidate[{index}] road_osm_id {road_osm_id} is not in vertical slice")

        osm_type = str(raw.get("source_osm_type", ""))
        source_osm_id = raw.get("source_osm_id")
        if osm_type not in OSM_TYPES or not isinstance(source_osm_id, int) or source_osm_id <= 0:
            fail(f"candidate[{index}] invalid source OSM identity")
        source_url = str(raw.get("source_url", ""))
        if not valid_osm_url(source_url, osm_type, source_osm_id):
            fail(f"candidate[{index}] source_url does not match exact OSM identity")
        if raw.get("source_license") != "ODbL-1.0":
            fail(f"candidate[{index}] source license must be ODbL-1.0")
        accessed = str(raw.get("source_accessed_at", ""))
        if not re.fullmatch(r"20\d\d-\d\d-\d\d", accessed):
            fail(f"candidate[{index}] source_accessed_at must be YYYY-MM-DD")

        tags = raw.get("evidence_tags")
        if not isinstance(tags, dict) or not tags:
            fail(f"candidate[{index}] evidence_tags missing")
        for key, value in tags.items():
            validate_tag(str(key), str(value))

        if not bool(raw.get("runtime_approved", False)):
            continue
        source_note = str(raw.get("evidence_note", "")).strip()
        if len(source_note) < 12:
            fail(f"candidate[{index}] approved evidence needs a concrete evidence_note")
        approved_roads.add(road_osm_id)

    declared_ready = bool(registry.get("runtime_ready", False))
    computed_ready = len(approved_roads) >= required
    if declared_ready != computed_ready:
        fail(
            f"runtime_ready drift: declared={declared_ready} computed={computed_ready} "
            f"approved_distinct_roads={len(approved_roads)} required={required}"
        )
    if require_ready and not computed_ready:
        fail(
            f"ambulance parking evidence not ready: approved_distinct_roads={len(approved_roads)} "
            f"required={required}"
        )
    return {
        "candidate_count": len(candidates),
        "approved_distinct_road_count": len(approved_roads),
        "required_distinct_road_count": required,
        "runtime_ready": computed_ready,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--snapshot", type=Path, required=True)
    parser.add_argument("--require-ready", action="store_true")
    args = parser.parse_args()
    try:
        result = validate(load_json(args.registry), load_json(args.snapshot), args.require_ready)
    except ValueError as exc:
        print(f"MIDI_AMBULANCE_PARKING_EVIDENCE_FAIL: {exc}", file=sys.stderr)
        return 1
    print("MIDI_AMBULANCE_PARKING_EVIDENCE_OK: " + json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
