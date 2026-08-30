#!/usr/bin/env python3
"""Build a deterministic OSM road-source catalog for Grand Bruxelles.

This is a source lookup index only. Presence in this catalog MUST NOT be treated as
render, collision, streaming, safe-spawn, or JOUABLE authorization.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
from typing import Any

FORMAT = "grand-bruxelles-road-destination-catalog-v1"
SOURCE_FORMAT = "grand-bruxelles-osm-v1"
CATALOG_FIELDS = frozenset({
    "format", "source_format", "source_root", "road_record_count",
    "drivable_record_count", "eligible_record_count",
    "rejected_drivable_record_count", "entry_count", "duplicate_record_count",
    "compatible_document_count", "source_document_sha256", "entries",
    "authorization", "catalog_sha256",
})
ENTRY_FIELDS = frozenset({
    "osm_id", "name", "class", "width", "drivable", "point_count",
    "geometry_sha256", "source_paths", "source_file_count",
})
AUTHORIZATION_FIELDS = frozenset({
    "source_lookup_only", "render_authorized", "collision_authorized",
    "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized",
})


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_text(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def is_sha256(value: Any) -> bool:
    return type(value) is str and len(value) == 64 and all(ch in "0123456789abcdef" for ch in value)


def catalog_semantic_sha256(catalog: dict[str, Any]) -> str:
    unsigned = dict(catalog)
    unsigned.pop("catalog_sha256", None)
    return sha256_text(canonical_json(unsigned))


def require_source_number(value: Any, label: str) -> float:
    """Accept JSON numbers only; never normalize strings, booleans, or lossy integers."""
    if type(value) not in (int, float):
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: source JSON type drift {label}")
    number = float(value)
    if not math.isfinite(number):
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: non-finite source number {label}")
    if type(value) is int and int(number) != value:
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: lossy source number {label}")
    return number


def require_json_int(value: Any, label: str, *, minimum: int | None = None) -> int:
    if type(value) is not int:
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: JSON type drift {label}")
    if minimum is not None and value < minimum:
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: invalid integer {label}={value}")
    return value


def require_json_number(value: Any, label: str) -> float:
    if type(value) not in (int, float):
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: JSON type drift {label}")
    number = float(value)
    if not math.isfinite(number):
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: non-finite {label}")
    return number


def require_json_string(value: Any, label: str) -> str:
    if type(value) is not str:
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: JSON type drift {label}")
    return value


def require_canonical_source_document_path(value: Any, label: str = "source document path") -> str:
    """Require an exact canonical repository-relative POSIX path below data/osm/."""
    source_path = require_json_string(value, label)
    if not source_path or source_path.strip() != source_path or "\\" in source_path:
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: non-canonical source document path {source_path!r}")
    pure = PurePosixPath(source_path)
    if pure.is_absolute() or ".." in pure.parts or pure.as_posix() != source_path:
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: non-canonical source document path {source_path!r}")
    if not source_path.startswith("data/osm/") or not source_path.endswith(".game.json"):
        raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: non-canonical source document path {source_path!r}")
    return source_path


def normalized_points(raw_points: Any) -> list[list[float]]:
    if not isinstance(raw_points, list):
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: malformed source points container")
    if len(raw_points) < 2:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: insufficient source points")
    points: list[list[float]] = []
    for index, pair in enumerate(raw_points):
        if not isinstance(pair, list):
            raise SystemExit(
                f"ROAD_DESTINATION_CATALOG_FAIL: malformed source point points[{index}]"
            )
        if len(pair) != 2:
            raise SystemExit(
                f"ROAD_DESTINATION_CATALOG_FAIL: non-canonical source point dimension points[{index}]"
            )
        x = require_source_number(pair[0], f"points[{index}][0]")
        z = require_source_number(pair[1], f"points[{index}][1]")
        points.append([x, z])
    return points


def road_signature(road: dict[str, Any]) -> dict[str, Any] | None:
    raw_osm_id = road.get("osm_id")
    if type(raw_osm_id) is not int:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source JSON type drift osm_id")
    raw_name = road.get("name", "")
    raw_class = road.get("class", "")
    if type(raw_name) is not str:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source JSON type drift name")
    if type(raw_class) is not str:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source JSON type drift class")
    if raw_name.strip() != raw_name:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: non-canonical source name")
    if raw_class.strip() != raw_class:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: non-canonical source class")
    raw_drivable = road.get("drivable")
    if type(raw_drivable) is not bool:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source JSON type drift drivable")

    # Every record that claims the canonical source format must remain structurally valid,
    # even when it is not destination-eligible. Validate geometry and width before either
    # drivable or identity filtering so malformed source cannot disappear from provenance.
    points = normalized_points(road.get("points"))
    width = require_source_number(road.get("width"), "width")
    if width <= 0.0:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: non-positive source width")

    name = raw_name
    road_class = raw_class
    if not raw_drivable:
        return None
    if raw_osm_id <= 0 or not name:
        return None
    return {
        "osm_id": raw_osm_id, "name": name, "class": road_class,
        "width": width, "drivable": True, "points": points,
    }


def discover_documents(source_root: Path) -> list[Path]:
    return sorted(path for path in source_root.rglob("*.game.json") if path.is_file())


def build_catalog(source_root: Path) -> dict[str, Any]:
    source_root = source_root.resolve()
    entries: dict[int, dict[str, Any]] = {}
    document_digests: dict[str, str] = {}
    compatible_documents = road_record_count = drivable_record_count = 0
    eligible_record_count = rejected_drivable_record_count = duplicate_record_count = 0

    for path in discover_documents(source_root):
        try:
            raw_text = path.read_text(encoding="utf-8")
            document = json.loads(raw_text)
        except (OSError, json.JSONDecodeError) as exc:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: invalid JSON {path}: {exc}") from exc
        if not isinstance(document, dict) or document.get("format") != SOURCE_FORMAT:
            continue
        roads = document.get("roads")
        if not isinstance(roads, list):
            raise SystemExit(
                f"ROAD_DESTINATION_CATALOG_FAIL: malformed source roads container {path}"
            )
        compatible_documents += 1
        relative = require_canonical_source_document_path(
            path.relative_to(source_root.parent.parent).as_posix(), "generated source document path"
        )
        document_digests[relative] = hashlib.sha256(raw_text.encode("utf-8")).hexdigest()
        for road_index, raw_road in enumerate(roads):
            if not isinstance(raw_road, dict):
                raise SystemExit(
                    "ROAD_DESTINATION_CATALOG_FAIL: malformed source road record "
                    f"roads[{road_index}] in {path}"
                )
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
            osm_id = signature["osm_id"]
            semantic = {
                "osm_id": osm_id,
                "name": signature["name"],
                "class": signature["class"],
                "width": signature["width"],
                "drivable": True,
                "point_count": len(signature["points"]),
                "geometry_sha256": sha256_text(canonical_json(signature["points"])),
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

    payload: dict[str, Any] = {
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
    payload["catalog_sha256"] = catalog_semantic_sha256(payload)
    return payload


def validate_contract(catalog: dict[str, Any]) -> None:
    if type(catalog) is not dict or set(catalog) != CATALOG_FIELDS:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: catalog field set drift")
    if catalog.get("format") != FORMAT:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: format drift")
    if catalog.get("source_format") != SOURCE_FORMAT or catalog.get("source_root") != "data/osm":
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source contract drift")

    entries = catalog.get("entries")
    if not isinstance(entries, dict) or len(entries) < 1:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: no eligible source roads")
    eligible = require_json_int(catalog.get("eligible_record_count"), "eligible_record_count", minimum=0)
    entry_count = require_json_int(catalog.get("entry_count"), "entry_count", minimum=0)
    duplicates = require_json_int(catalog.get("duplicate_record_count"), "duplicate_record_count", minimum=0)
    drivable = require_json_int(catalog.get("drivable_record_count"), "drivable_record_count", minimum=0)
    rejected = require_json_int(catalog.get("rejected_drivable_record_count"), "rejected_drivable_record_count", minimum=0)
    compatible_documents = require_json_int(catalog.get("compatible_document_count"), "compatible_document_count", minimum=0)
    road_records = require_json_int(catalog.get("road_record_count"), "road_record_count", minimum=0)
    if entry_count != len(entries):
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: entry count drift")
    if eligible != entry_count + duplicates:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: unique/duplicate accounting drift")
    if drivable != eligible + rejected:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: drivable/rejected accounting drift")
    if road_records < drivable:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: road/drivable accounting drift")

    authorization = catalog.get("authorization")
    if type(authorization) is not dict or set(authorization) != AUTHORIZATION_FIELDS:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: authorization field set drift")
    for forbidden in (
        "render_authorized", "collision_authorized", "runtime_mount_authorized",
        "safe_spawn_authorized", "jouable_authorized",
    ):
        if authorization.get(forbidden) is not False:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: {forbidden} must stay false")
    if authorization.get("source_lookup_only") is not True:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source_lookup_only missing")

    source_digests = catalog.get("source_document_sha256")
    if not isinstance(source_digests, dict) or not source_digests:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source document digests missing")
    if compatible_documents != len(source_digests):
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: compatible document accounting drift")
    for raw_path, raw_digest in source_digests.items():
        source_path = require_canonical_source_document_path(raw_path)
        if type(raw_digest) is not str:
            raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: JSON type drift source document SHA256")
        if not is_sha256(raw_digest):
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: invalid source document SHA256 {source_path!r}")

    observed_duplicate_multiplicity = 0
    for raw_osm_id, raw_entry in entries.items():
        if type(raw_osm_id) is not str or not raw_osm_id.isdigit():
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: invalid OSM id {raw_osm_id!r}")
        osm_id = int(raw_osm_id)
        if raw_osm_id != str(osm_id):
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: non-canonical OSM id key {raw_osm_id!r}")
        if not isinstance(raw_entry, dict):
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: malformed entry {raw_osm_id!r}")
        if set(raw_entry) != ENTRY_FIELDS:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: entry field set drift {raw_osm_id!r}")
        entry_osm_id = require_json_int(raw_entry.get("osm_id"), "entry osm_id", minimum=1)
        if osm_id <= 0 or osm_id != entry_osm_id:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: OSM id key/value drift {raw_osm_id!r}")
        if raw_entry.get("drivable") is not True:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: indexed road is not drivable {osm_id}")
        entry_name = require_json_string(raw_entry.get("name"), "entry name")
        entry_class = require_json_string(raw_entry.get("class"), "entry class")
        if not entry_name or entry_name.strip() != entry_name:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: non-canonical entry name osm_id={osm_id}")
        if entry_class.strip() != entry_class:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: non-canonical entry class osm_id={osm_id}")
        entry_width = require_json_number(raw_entry.get("width"), "entry width")
        if entry_width <= 0.0:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: non-positive entry width osm_id={osm_id}")
        require_json_int(raw_entry.get("point_count"), "point_count", minimum=2)
        geometry_sha256 = raw_entry.get("geometry_sha256")
        if type(geometry_sha256) is not str:
            raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: JSON type drift geometry_sha256")
        if not is_sha256(geometry_sha256):
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: invalid geometry evidence {osm_id}")
        source_paths = raw_entry.get("source_paths")
        if not isinstance(source_paths, list) or not source_paths:
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: source paths missing {osm_id}")
        normalized_source_paths = [
            require_canonical_source_document_path(path, f"source path osm_id={osm_id}")
            for path in source_paths
        ]
        if normalized_source_paths != sorted(set(normalized_source_paths)):
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: source paths not deterministic {osm_id}")
        source_file_count = require_json_int(raw_entry.get("source_file_count"), "source_file_count", minimum=1)
        if source_file_count != len(normalized_source_paths):
            raise SystemExit(f"ROAD_DESTINATION_CATALOG_FAIL: source file count drift {osm_id}")
        observed_duplicate_multiplicity += source_file_count - 1
        for source_path in normalized_source_paths:
            if source_path not in source_digests:
                raise SystemExit(
                    "ROAD_DESTINATION_CATALOG_FAIL: source path missing locked digest "
                    f"osm_id={osm_id} source_path={source_path!r}"
                )

    if duplicates != observed_duplicate_multiplicity:
        raise SystemExit(
            "ROAD_DESTINATION_CATALOG_FAIL: duplicate/source multiplicity accounting drift "
            f"declared={duplicates} observed={observed_duplicate_multiplicity}"
        )

    stored_catalog_sha = catalog.get("catalog_sha256")
    if type(stored_catalog_sha) is not str:
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: JSON type drift catalog SHA256")
    if not is_sha256(stored_catalog_sha):
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: catalog SHA256 invalid")
    expected_catalog_sha = catalog_semantic_sha256(catalog)
    if stored_catalog_sha != expected_catalog_sha:
        raise SystemExit(
            "ROAD_DESTINATION_CATALOG_FAIL: catalog SHA256 drift "
            f"stored={stored_catalog_sha} expected={expected_catalog_sha}"
        )


def validate_source_binding(catalog: dict[str, Any], source_root: Path) -> None:
    """Re-derive source catalog and fail closed if persisted evidence detached."""
    validate_contract(catalog)
    rebuilt = build_catalog(source_root)
    validate_contract(rebuilt)
    if catalog.get("source_document_sha256") != rebuilt.get("source_document_sha256"):
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source binding drift: source document digest mismatch")
    accounting_keys = (
        "road_record_count", "drivable_record_count", "eligible_record_count",
        "rejected_drivable_record_count", "entry_count", "duplicate_record_count",
        "compatible_document_count",
    )
    for key in accounting_keys:
        if catalog.get(key) != rebuilt.get(key):
            raise SystemExit(
                "ROAD_DESTINATION_CATALOG_FAIL: source binding drift: "
                f"accounting mismatch key={key} stored={catalog.get(key)!r} rebuilt={rebuilt.get(key)!r}"
            )
    if catalog.get("entries") != rebuilt.get("entries"):
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source binding drift: road entry/source geometry mismatch")
    if catalog.get("catalog_sha256") != rebuilt.get("catalog_sha256"):
        raise SystemExit("ROAD_DESTINATION_CATALOG_FAIL: source binding drift: catalog semantic SHA mismatch")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-root", type=Path, default=Path("data/osm"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    catalog = build_catalog(args.source_root)
    validate_contract(catalog)
    validate_source_binding(catalog, args.source_root)
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
