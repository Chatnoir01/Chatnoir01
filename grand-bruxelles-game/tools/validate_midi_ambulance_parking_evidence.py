#!/usr/bin/env python3
"""Fail-closed validator for source-backed Midi ambulance parking evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import sys
from pathlib import Path
from urllib.parse import urlparse

FORMAT = "grand-bruxelles-midi-ambulance-parking-evidence-v1"
OSM_TYPES = {"node", "way", "relation"}
PARKING_PREFIXES = ("parking:left", "parking:right", "parking:both")
RIGHT_SIDE_AUTHORITATIVE_KEYS = {"parking:right", "parking:both"}
POSITIVE_CURBSIDE_VALUES = {
    "yes",
    "lane",
    "street_side",
    "on_kerb",
    "half_on_kerb",
    "shoulder",
    "separate",
}
ISO_UTC_RE = re.compile(r"20\d\d-\d\d-\d\dT\d\d:\d\d:\d\dZ")
SHA256_RE = re.compile(r"[0-9a-f]{64}")

# These mirror traffic_parking_model.gd. Readiness is based on the actual
# runtime slot geometry the consumer will synthesize, not an arbitrary count
# of source roads.
MIN_SEGMENT_LENGTH_M = 18.0
END_CLEARANCE_M = 8.0
CANDIDATE_SPACING_M = 26.0
DEFAULT_ROAD_WIDTH_M = 5.6
CURB_MARGIN_M = 1.25
PARKING_CLASSES = {
    "residential",
    "tertiary",
    "secondary",
    "unclassified",
    "service",
    "living_street",
}


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


def roads_by_id(snapshot: dict) -> dict[int, dict]:
    roads = snapshot.get("roads", [])
    if not isinstance(roads, list):
        fail("snapshot roads must be an array")
    result: dict[int, dict] = {}
    for road in roads:
        if not isinstance(road, dict):
            continue
        osm_id = road.get("osm_id")
        if isinstance(osm_id, int) and not isinstance(osm_id, bool) and osm_id > 0:
            result[int(osm_id)] = road
    return result


def target_anchor(snapshot: dict, anchor_id: str) -> tuple[float, float]:
    corridor = snapshot.get("corridor")
    if not isinstance(corridor, dict):
        fail("snapshot corridor missing")
    anchors = corridor.get("anchors")
    if not isinstance(anchors, list):
        fail("snapshot corridor anchors missing")
    for anchor in anchors:
        if not isinstance(anchor, dict) or str(anchor.get("id", "")) != anchor_id:
            continue
        x = anchor.get("x")
        z = anchor.get("z")
        if isinstance(x, (int, float)) and not isinstance(x, bool) and isinstance(z, (int, float)) and not isinstance(z, bool):
            return float(x), float(z)
    fail(f"target anchor not found in snapshot: {anchor_id}")


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
    if any(key == prefix or key.startswith(prefix + ":") for prefix in PARKING_PREFIXES):
        return
    fail(f"unsupported parking evidence tag: {key}={value}")


def canonical_source_element_sha256(element: dict) -> str:
    payload = json.dumps(
        element,
        sort_keys=True,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def validate_source_element(raw: dict, index: int, osm_type: str, source_osm_id: int, accessed: str) -> dict[str, str]:
    element = raw.get("source_element")
    if not isinstance(element, dict):
        fail(f"candidate[{index}] versioned source element missing")
    if element.get("type") != osm_type or element.get("id") != source_osm_id:
        fail(f"candidate[{index}] source element identity does not match declared OSM identity")
    version = element.get("version")
    if not isinstance(version, int) or isinstance(version, bool) or version <= 0:
        fail(f"candidate[{index}] source element version must be a positive integer")
    timestamp = str(element.get("timestamp", ""))
    if not ISO_UTC_RE.fullmatch(timestamp):
        fail(f"candidate[{index}] source element timestamp must be UTC YYYY-MM-DDTHH:MM:SSZ")
    if timestamp[:10] > accessed:
        fail(f"candidate[{index}] source element timestamp is newer than source_accessed_at")
    tags = element.get("tags")
    if not isinstance(tags, dict) or not tags:
        fail(f"candidate[{index}] source element tags missing")
    normalized_tags: dict[str, str] = {}
    for key, value in tags.items():
        key_text = str(key).strip()
        value_text = str(value).strip()
        if not key_text or not value_text:
            fail(f"candidate[{index}] source element tag key/value must be non-empty")
        normalized_tags[key_text] = value_text

    declared_digest = str(raw.get("source_element_sha256", "")).strip()
    if not SHA256_RE.fullmatch(declared_digest):
        fail(f"candidate[{index}] source element SHA-256 must be 64 lowercase hex characters")
    actual_digest = canonical_source_element_sha256(element)
    if declared_digest != actual_digest:
        fail(
            f"candidate[{index}] source element SHA-256 drift: "
            f"declared={declared_digest} actual={actual_digest}"
        )
    return normalized_tags


def runtime_authorizing_tag(tags: dict[str, str]) -> tuple[str, str] | None:
    """Return an exact right-side/both positive curb-parking tag, if present.

    The current parking model offsets every synthesized slot to the right of the
    directed road geometry. Left-only evidence therefore cannot authorize this
    consumer. Negative tags such as parking:both=no remain useful source truth,
    but they never authorize a runtime parking slot.
    """
    for key in ("parking:right", "parking:both"):
        value = str(tags.get(key, "")).strip()
        if value in POSITIVE_CURBSIDE_VALUES:
            return key, value
    return None


def point2(raw: object) -> tuple[float, float] | None:
    if not isinstance(raw, list) or len(raw) < 2:
        return None
    x, z = raw[0], raw[1]
    if not isinstance(x, (int, float)) or isinstance(x, bool):
        return None
    if not isinstance(z, (int, float)) or isinstance(z, bool):
        return None
    return float(x), float(z)


def safe_width(raw: object) -> float:
    if isinstance(raw, (int, float)) and not isinstance(raw, bool):
        return max(3.0, float(raw))
    return DEFAULT_ROAD_WIDTH_M


def runtime_slots_for_road(road: dict, anchor: tuple[float, float], radius_m: float) -> list[tuple[float, float]]:
    road_class = str(road.get("class", ""))
    if road_class not in PARKING_CLASSES:
        return []
    points = road.get("points", [])
    if not isinstance(points, list) or len(points) < 2:
        return []
    width = safe_width(road.get("width"))
    offset = width * 0.5 + CURB_MARGIN_M
    result: list[tuple[float, float]] = []
    ax, az = anchor
    for index in range(len(points) - 1):
        start = point2(points[index])
        finish = point2(points[index + 1])
        if start is None or finish is None:
            continue
        sx, sz = start
        fx, fz = finish
        dx, dz = fx - sx, fz - sz
        length = math.hypot(dx, dz)
        if length < MIN_SEGMENT_LENGTH_M:
            continue
        ux, uz = dx / length, dz / length
        right_x, right_z = -uz, ux
        usable = max(0.0, length - END_CLEARANCE_M * 2.0)
        slot_count = max(1, int(math.floor(usable / CANDIDATE_SPACING_M)) + 1)
        for slot in range(slot_count):
            along = END_CLEARANCE_M
            if slot_count > 1:
                along += usable * float(slot) / float(slot_count - 1)
            else:
                along += usable * 0.5
            road_x = sx + ux * along
            road_z = sz + uz * along
            parking_x = road_x + right_x * offset
            parking_z = road_z + right_z * offset
            if math.hypot(parking_x - ax, parking_z - az) <= radius_m:
                result.append((parking_x, parking_z))
    return result


def validate(registry: dict, snapshot: dict, require_ready: bool) -> dict:
    if registry.get("format") != FORMAT:
        fail(f"unexpected registry format: {registry.get('format')!r}")
    contract = registry.get("source_contract")
    if not isinstance(contract, dict) or contract.get("license") != "ODbL-1.0":
        fail("source contract must pin ODbL-1.0")
    if contract.get("versioned_source_binding_required") is not True:
        fail("source contract must require versioned source binding")

    target = registry.get("target")
    if not isinstance(target, dict):
        fail("target contract missing")
    required_slots = int(target.get("required_runtime_candidate_count", 0))
    if required_slots < 2:
        fail("at least two runtime parking candidates are required")
    anchor_id = str(target.get("anchor_id", "")).strip()
    if not anchor_id:
        fail("target anchor_id missing")
    radius_raw = target.get("candidate_radius_m")
    if not isinstance(radius_raw, (int, float)) or isinstance(radius_raw, bool) or float(radius_raw) <= 0.0:
        fail("target candidate_radius_m must be positive")
    radius_m = float(radius_raw)
    anchor = target_anchor(snapshot, anchor_id)

    known_roads = roads_by_id(snapshot)
    candidates = registry.get("candidates")
    if not isinstance(candidates, list):
        fail("candidates must be an array")

    seen_evidence: set[str] = set()
    seen_source_versions: set[tuple[str, int, int]] = set()
    approved_roads: set[int] = set()
    runtime_slots: list[tuple[float, float]] = []
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
        if not isinstance(road_osm_id, int) or isinstance(road_osm_id, bool) or road_osm_id <= 0:
            fail(f"candidate[{index}] road_osm_id must be a positive integer")
        road = known_roads.get(int(road_osm_id))
        if road is None:
            fail(f"candidate[{index}] road_osm_id {road_osm_id} is not in vertical slice")

        osm_type = str(raw.get("source_osm_type", ""))
        source_osm_id = raw.get("source_osm_id")
        if (
            osm_type not in OSM_TYPES
            or not isinstance(source_osm_id, int)
            or isinstance(source_osm_id, bool)
            or source_osm_id <= 0
        ):
            fail(f"candidate[{index}] invalid source OSM identity")
        source_url = str(raw.get("source_url", ""))
        if not valid_osm_url(source_url, osm_type, source_osm_id):
            fail(f"candidate[{index}] source_url does not match exact OSM identity")
        if raw.get("source_license") != "ODbL-1.0":
            fail(f"candidate[{index}] source license must be ODbL-1.0")
        accessed = str(raw.get("source_accessed_at", ""))
        if not re.fullmatch(r"20\d\d-\d\d-\d\d", accessed):
            fail(f"candidate[{index}] source_accessed_at must be YYYY-MM-DD")

        source_tags = validate_source_element(raw, index, osm_type, int(source_osm_id), accessed)
        source_version = int(raw["source_element"]["version"])
        source_key = (osm_type, int(source_osm_id), source_version)
        if source_key in seen_source_versions:
            fail(
                f"candidate[{index}] duplicate source element version: "
                f"{osm_type}/{source_osm_id}@{source_version}"
            )
        seen_source_versions.add(source_key)

        tags = raw.get("evidence_tags")
        if not isinstance(tags, dict) or not tags:
            fail(f"candidate[{index}] evidence_tags missing")
        normalized_evidence_tags: dict[str, str] = {}
        for key, value in tags.items():
            key_text = str(key).strip()
            value_text = str(value).strip()
            validate_tag(key_text, value_text)
            if source_tags.get(key_text) != value_text:
                fail(
                    f"candidate[{index}] source element tags do not contain evidence: "
                    f"{key_text}={value_text}"
                )
            normalized_evidence_tags[key_text] = value_text

        if not bool(raw.get("runtime_approved", False)):
            continue
        if osm_type != "way" or int(source_osm_id) != int(road_osm_id):
            fail(f"candidate[{index}] runtime curb evidence must bind the exact vertical-slice road way")
        authorizing = runtime_authorizing_tag(normalized_evidence_tags)
        if authorizing is None:
            fail(f"candidate[{index}] runtime evidence has no positive right-side/both curb parking authorization")
        source_authorizing = runtime_authorizing_tag(source_tags)
        if source_authorizing != authorizing:
            fail(f"candidate[{index}] runtime authorizing tag drifted from source element")
        source_note = str(raw.get("evidence_note", "")).strip()
        if len(source_note) < 12:
            fail(f"candidate[{index}] approved evidence needs a concrete evidence_note")

        approved_roads.add(int(road_osm_id))
        runtime_slots.extend(runtime_slots_for_road(road, anchor, radius_m))

    declared_ready = bool(registry.get("runtime_ready", False))
    computed_ready = len(runtime_slots) >= required_slots
    if declared_ready != computed_ready:
        fail(
            f"runtime_ready drift: declared={declared_ready} computed={computed_ready} "
            f"runtime_candidates={len(runtime_slots)} required={required_slots}"
        )
    if require_ready and not computed_ready:
        fail(
            f"ambulance parking evidence not ready: runtime_candidates={len(runtime_slots)} "
            f"required={required_slots}"
        )
    return {
        "candidate_count": len(candidates),
        "approved_distinct_road_count": len(approved_roads),
        "runtime_candidate_count": len(runtime_slots),
        "required_runtime_candidate_count": required_slots,
        "target_anchor_id": anchor_id,
        "candidate_radius_m": radius_m,
        "runtime_ready": computed_ready,
        "versioned_source_binding": True,
        "positive_curb_semantics_required": True,
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
