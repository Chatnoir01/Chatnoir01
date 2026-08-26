#!/usr/bin/env python3
"""Freeze and validate City of Brussels Open Data catalogue overlap evidence for Midi.

This tool is evidence-only. It never authorizes source ingestion, persistence,
runtime mounting, rendering, collision, spawn, or JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any, Iterable

SCHEMA = "grand-bruxelles-midi-city-open-data-zone-overlap-v1"
SOURCE_URL = "https://opendata.brussels.be/api/explore/v2.1/catalog/exports/json?limit=-1&offset=0&timezone=UTC"
SOURCE_AUTHORITY = "City of Brussels Open Data"
MIDI_MANIFEST = "grand-bruxelles-game/data/urbis/midi/manifest.json"
MIDI_CRS = "EPSG:31370"
MIDI_BBOX = [147250.0, 168900.0, 148500.0, 170250.0]
# Envelope of all four MIDI_BBOX corners transformed EPSG:31370 -> EPSG:4326.
# Stored as evidence so final validation has no projection/network dependency.
MIDI_BBOX_WGS84 = [
    4.3297073628844815,
    50.830516520506116,
    4.347460321372539,
    50.84265685566135,
]
CLOSED_RAILS = {
    "source_ingestion": False,
    "source_persistence": False,
    "source_registration": False,
    "canonical_registration": False,
    "runtime_directory_scan": False,
    "runtime_mount": False,
    "rendered_geometry": False,
    "collision": False,
    "safe_spawn": False,
    "jouable_promotion": False,
}


def canonical_json_bytes(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_bytes(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _iter_numbers(value: Any) -> Iterable[tuple[float, float]]:
    if isinstance(value, list):
        if len(value) >= 2 and all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in value[:2]):
            yield float(value[0]), float(value[1])
            return
        for item in value:
            yield from _iter_numbers(item)


def bbox_from_geojson_feature(value: Any) -> list[float] | None:
    if not isinstance(value, dict):
        return None
    geometry = value.get("geometry") if value.get("type") == "Feature" else value
    if not isinstance(geometry, dict):
        return None
    points = list(_iter_numbers(geometry.get("coordinates")))
    if not points:
        return None
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    return [min(xs), min(ys), max(xs), max(ys)]


def bboxes_intersect(a: list[float], b: list[float]) -> bool:
    if len(a) != 4 or len(b) != 4:
        raise ValueError("bbox must have four numbers")
    return not (a[2] < b[0] or a[0] > b[2] or a[3] < b[1] or a[1] > b[3])


def is_geospatial_candidate(dataset: dict[str, Any]) -> bool:
    default = dataset.get("metas", {}).get("default", {})
    geometry_types = default.get("geometry_types")
    if isinstance(geometry_types, list) and len(geometry_types) > 0:
        return True
    features = dataset.get("features")
    if isinstance(features, list) and "geo" in features:
        return True
    fields = dataset.get("fields")
    if isinstance(fields, list):
        return any(
            isinstance(field, dict) and field.get("type") in {"geo_point_2d", "geo_shape"}
            for field in fields
        )
    return False


def classify_dataset(dataset: dict[str, Any]) -> dict[str, Any]:
    default = dataset.get("metas", {}).get("default", {})
    bbox = bbox_from_geojson_feature(default.get("bbox"))
    proven = bbox is not None and bboxes_intersect(bbox, MIDI_BBOX_WGS84)
    status = "OVERLAP_PROVEN" if proven else "UNRESOLVED"
    if proven:
        reason = "catalog_metadata_bbox_intersects_midi_wgs84_envelope"
    elif bbox is None:
        reason = "catalog_has_geospatial_metadata_but_no_usable_bbox"
    else:
        reason = "catalog_metadata_bbox_does_not_intersect_midi; this_is_not_proof_of_real_world_absence"
    geometry_types = default.get("geometry_types")
    return {
        "dataset_id": str(dataset.get("dataset_id", "")),
        "title": default.get("title"),
        "publisher": default.get("publisher"),
        "license": default.get("license"),
        "license_url": default.get("license_url"),
        "records_count": default.get("records_count"),
        "modified": default.get("modified"),
        "metadata_processed": default.get("metadata_processed"),
        "geometry_types": geometry_types if isinstance(geometry_types, list) else [],
        "bbox_wgs84": bbox,
        "status": status,
        "reason": reason,
    }


def semantic_payload(snapshot: dict[str, Any]) -> dict[str, Any]:
    return {
        "schema": snapshot["schema"],
        "target_zone": snapshot["target_zone"],
        "candidate_rule": snapshot["candidate_rule"],
        "catalog_total_datasets": snapshot["catalog_total_datasets"],
        "geospatial_candidate_count": snapshot["geospatial_candidate_count"],
        "overlap_proven_count": snapshot["overlap_proven_count"],
        "unresolved_count": snapshot["unresolved_count"],
        "datasets": snapshot["datasets"],
        "authorization": snapshot["authorization"],
    }


def build_snapshot(catalog_raw: bytes, retrieved_at: str, production_base_sha: str) -> dict[str, Any]:
    catalog = json.loads(catalog_raw)
    if not isinstance(catalog, list):
        raise ValueError("catalog export must be a JSON list")
    rows = [
        classify_dataset(dataset)
        for dataset in catalog
        if isinstance(dataset, dict) and is_geospatial_candidate(dataset)
    ]
    rows.sort(key=lambda row: row["dataset_id"])
    if any(not row["dataset_id"] for row in rows):
        raise ValueError("candidate dataset missing dataset_id")
    if len({row["dataset_id"] for row in rows}) != len(rows):
        raise ValueError("duplicate candidate dataset_id")
    proven = sum(row["status"] == "OVERLAP_PROVEN" for row in rows)
    unresolved = sum(row["status"] == "UNRESOLVED" for row in rows)
    snapshot: dict[str, Any] = {
        "schema": SCHEMA,
        "status": "FROZEN_METADATA_OVERLAP_EVIDENCE_ONLY",
        "production_base_sha": production_base_sha,
        "provenance": {
            "authority": SOURCE_AUTHORITY,
            "catalog_export_url": SOURCE_URL,
            "retrieved_at_utc": retrieved_at,
            "catalog_export_sha256": sha256_bytes(catalog_raw),
            "catalog_export_size_bytes": len(catalog_raw),
            "note": "Mutable public catalogue was read once to create this lock; CI validates only this frozen file.",
        },
        "target_zone": {
            "name": "Midi",
            "state": "JOUABLE",
            "manifest": MIDI_MANIFEST,
            "crs": MIDI_CRS,
            "bbox": MIDI_BBOX,
            "bbox_wgs84": MIDI_BBOX_WGS84,
            "bbox_wgs84_derivation": "envelope of all four EPSG:31370 bbox corners transformed to EPSG:4326",
        },
        "candidate_rule": {
            "name": "explicit_geospatial_metadata_only",
            "definition": "geometry_types non-empty OR catalog feature 'geo' OR schema contains geo_point_2d/geo_shape",
            "title_theme_inference_forbidden": True,
        },
        "catalog_total_datasets": len(catalog),
        "geospatial_candidate_count": len(rows),
        "overlap_proven_count": proven,
        "unresolved_count": unresolved,
        "datasets": rows,
        "authorization": dict(CLOSED_RAILS),
    }
    snapshot["snapshot_semantic_sha256"] = sha256_bytes(canonical_json_bytes(semantic_payload(snapshot)))
    return snapshot


def validate_snapshot(snapshot: dict[str, Any]) -> None:
    assert snapshot["schema"] == SCHEMA
    assert snapshot["status"] in {
        "RED_FIRST_ACQUISITION_PENDING",
        "FROZEN_METADATA_OVERLAP_EVIDENCE_ONLY",
    }
    assert snapshot["target_zone"]["name"] == "Midi"
    assert snapshot["target_zone"]["crs"] == MIDI_CRS
    assert snapshot["target_zone"]["bbox"] == MIDI_BBOX
    assert snapshot["target_zone"]["bbox_wgs84"] == MIDI_BBOX_WGS84
    assert snapshot["authorization"] == CLOSED_RAILS
    if snapshot["status"] == "RED_FIRST_ACQUISITION_PENDING":
        return
    datasets = snapshot["datasets"]
    assert isinstance(datasets, list)
    assert datasets == sorted(datasets, key=lambda row: row["dataset_id"])
    assert len({row["dataset_id"] for row in datasets}) == len(datasets)
    assert snapshot["geospatial_candidate_count"] == len(datasets)
    proven = 0
    unresolved = 0
    for row in datasets:
        assert row["status"] in {"OVERLAP_PROVEN", "UNRESOLVED"}
        bbox = row["bbox_wgs84"]
        if row["status"] == "OVERLAP_PROVEN":
            assert bbox is not None and bboxes_intersect(bbox, MIDI_BBOX_WGS84), row["dataset_id"]
            proven += 1
        else:
            unresolved += 1
            assert "absence" in row["reason"] or bbox is None
    assert snapshot["overlap_proven_count"] == proven
    assert snapshot["unresolved_count"] == unresolved
    assert proven + unresolved == len(datasets)
    assert snapshot["catalog_total_datasets"] >= len(datasets)
    expected = sha256_bytes(canonical_json_bytes(semantic_payload(snapshot)))
    assert snapshot["snapshot_semantic_sha256"] == expected


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)

    acquire = sub.add_parser("acquire")
    acquire.add_argument("--catalog", required=True)
    acquire.add_argument("--output", required=True)
    acquire.add_argument("--retrieved-at", required=True)
    acquire.add_argument("--production-base-sha", required=True)

    validate = sub.add_parser("validate")
    validate.add_argument("--snapshot", required=True)

    args = parser.parse_args()
    if args.command == "acquire":
        raw = Path(args.catalog).read_bytes()
        snapshot = build_snapshot(raw, args.retrieved_at, args.production_base_sha)
        validate_snapshot(snapshot)
        Path(args.output).write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(
            "MIDI_CITY_OPEN_DATA_ACQUIRED "
            f"catalog={snapshot['catalog_total_datasets']} "
            f"geospatial={snapshot['geospatial_candidate_count']} "
            f"overlap_proven={snapshot['overlap_proven_count']} "
            f"unresolved={snapshot['unresolved_count']} "
            f"semantic={snapshot['snapshot_semantic_sha256']}"
        )
        return 0
    snapshot = json.loads(Path(args.snapshot).read_text(encoding="utf-8"))
    validate_snapshot(snapshot)
    print(
        "MIDI_CITY_OPEN_DATA_SNAPSHOT_OK "
        f"status={snapshot['status']} "
        f"production_base={snapshot['production_base_sha']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
