#!/usr/bin/env python3
"""Derive a fail-closed game-oriented inventory from a verified City of Brussels Open Data snapshot.

This classifier is intentionally conservative. It does not infer semantic runtime behavior.
It only classifies objective source capabilities from catalogue metadata + verified snapshot
availability: point fields, shape fields, continuous-update metadata, and whether exact source
bytes were retrieved. All runtime/game authorization remains false.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

SCHEMA = "grand-bruxelles-city-open-data-game-inventory-v1"


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _default_meta(row: dict[str, Any]) -> dict[str, Any]:
    metas = row.get("metas") if isinstance(row.get("metas"), dict) else {}
    default = metas.get("default") if isinstance(metas.get("default"), dict) else {}
    return default


def _themes(default: dict[str, Any]) -> list[str]:
    value = default.get("theme_fr") or default.get("theme")
    if isinstance(value, list):
        return sorted({str(x) for x in value if x})
    if value:
        return [str(value)]
    return []


def classify_dataset(row: dict[str, Any], snapshot_entry: dict[str, Any]) -> dict[str, Any]:
    dataset_id = str(row["dataset_id"])
    if snapshot_entry.get("dataset_id") != dataset_id:
        raise ValueError(f"snapshot/catalog identity mismatch: {dataset_id}")

    default = _default_meta(row)
    fields = row.get("fields") if isinstance(row.get("fields"), list) else []
    point_fields = sorted(str(f.get("name")) for f in fields if f.get("type") == "geo_point_2d")
    shape_fields = sorted(str(f.get("name")) for f in fields if f.get("type") == "geo_shape")
    geometry_types = default.get("geometry_types")
    if not isinstance(geometry_types, list):
        geometry_types = []

    status = str(snapshot_entry.get("status"))
    source_available = status == "downloaded"
    has_point = bool(point_fields)
    has_shape = bool(shape_fields)
    geospatial = has_point or has_shape

    if not source_available:
        candidate_class = "HOLD_SOURCE_UNAVAILABLE" if row.get("has_records") else "HOLD_NO_RECORDS"
    elif has_shape:
        candidate_class = "MAP_GEOMETRY_CANDIDATE"
    elif has_point:
        candidate_class = "MAP_POI_CANDIDATE"
    else:
        candidate_class = "DATA_ENRICHMENT_CANDIDATE"

    continuous = default.get("update_frequency") == "CONT"
    return {
        "dataset_id": dataset_id,
        "title": default.get("title_fr") or default.get("title"),
        "official_themes": _themes(default),
        "license": default.get("license"),
        "records_count_catalog": default.get("records_count"),
        "snapshot_status": status,
        "source_bytes_verified": source_available,
        "federated": bool(default.get("federated")),
        "update_frequency": default.get("update_frequency"),
        "continuous_update_metadata": continuous,
        "geometry": {
            "has_geospatial_fields": geospatial,
            "point_fields": point_fields,
            "shape_fields": shape_fields,
            "official_geometry_types": sorted(str(x) for x in geometry_types),
        },
        "game_inventory": {
            "candidate_class": candidate_class,
            "poi_candidate": source_available and has_point,
            "linear_or_area_candidate": source_available and has_shape,
            "realtime_candidate": source_available and geospatial and continuous,
            "static_map_candidate": source_available and geospatial and not continuous,
            "semantic_runtime_role_inferred": False,
            "runtime_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        },
    }


def build_inventory(catalog: list[dict[str, Any]], snapshot: dict[str, Any], provenance: dict[str, Any] | None = None) -> dict[str, Any]:
    if snapshot.get("schema") != "grand-bruxelles-city-open-data-full-snapshot-index-v1":
        raise ValueError("unexpected verified snapshot schema")
    entries = snapshot.get("datasets")
    if not isinstance(entries, list):
        raise ValueError("verified snapshot has no datasets list")
    by_id = {str(e["dataset_id"]): e for e in entries}
    if len(by_id) != len(entries):
        raise ValueError("duplicate dataset_id in verified snapshot")

    catalog_ids = [str(row["dataset_id"]) for row in catalog]
    if len(set(catalog_ids)) != len(catalog_ids):
        raise ValueError("duplicate dataset_id in catalog")
    if set(catalog_ids) != set(by_id):
        raise ValueError("catalog and verified snapshot do not cover the same dataset ids")

    classified = [classify_dataset(row, by_id[str(row["dataset_id"])]) for row in sorted(catalog, key=lambda r: str(r["dataset_id"]))]

    summary = {
        "catalog_dataset_count": len(classified),
        "source_bytes_verified_count": sum(x["source_bytes_verified"] for x in classified),
        "geospatial_dataset_count": sum(x["geometry"]["has_geospatial_fields"] for x in classified),
        "point_dataset_count": sum(bool(x["geometry"]["point_fields"]) for x in classified),
        "shape_dataset_count": sum(bool(x["geometry"]["shape_fields"]) for x in classified),
        "continuous_geospatial_dataset_count": sum(x["game_inventory"]["realtime_candidate"] for x in classified),
        "map_geometry_candidate_count": sum(x["game_inventory"]["candidate_class"] == "MAP_GEOMETRY_CANDIDATE" for x in classified),
        "map_poi_candidate_count": sum(x["game_inventory"]["candidate_class"] == "MAP_POI_CANDIDATE" for x in classified),
        "data_enrichment_candidate_count": sum(x["game_inventory"]["candidate_class"] == "DATA_ENRICHMENT_CANDIDATE" for x in classified),
        "hold_count": sum(x["game_inventory"]["candidate_class"].startswith("HOLD_") for x in classified),
    }

    return {
        "schema": SCHEMA,
        "source": "City of Brussels Open Data",
        "source_snapshot_schema": snapshot["schema"],
        "source_catalog_sha256": snapshot.get("catalog_sha256"),
        "source_snapshot_all_entries_accounted": snapshot.get("all_catalog_entries_accounted") is True,
        "provenance": provenance or {},
        "summary": summary,
        "authorization": {
            "classification_only": True,
            "source_registration": False,
            "canonical_registration": False,
            "runtime_directory_scan": False,
            "runtime_mount": False,
            "rendered_geometry": False,
            "collision": False,
            "safe_spawn": False,
            "jouable_promotion": False,
        },
        "datasets": classified,
    }


def compact_inventory(full: dict[str, Any]) -> dict[str, Any]:
    """Return the persisted, compact planning measurement for all catalogue entries."""
    out = {k: full[k] for k in [
        "schema", "source", "source_snapshot_schema", "source_catalog_sha256",
        "source_snapshot_all_entries_accounted", "provenance", "summary", "authorization"
    ]}
    out["datasets"] = [
        {
            "dataset_id": row["dataset_id"],
            "candidate_class": row["game_inventory"]["candidate_class"],
            "geospatial": row["geometry"]["has_geospatial_fields"],
            "realtime_candidate": row["game_inventory"]["realtime_candidate"],
            "official_themes": row["official_themes"],
        }
        for row in full["datasets"]
    ]
    return out


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--catalog", required=True)
    parser.add_argument("--snapshot-index", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--source-run-id")
    parser.add_argument("--source-artifact-id")
    parser.add_argument("--source-head-sha")
    parser.add_argument("--source-artifact-digest")
    parser.add_argument("--compact", action="store_true")
    args = parser.parse_args()
    catalog_path = Path(args.catalog)
    snapshot_path = Path(args.snapshot_index)
    catalog = read_json(catalog_path)
    snapshot = read_json(snapshot_path)
    if not isinstance(catalog, list):
        raise ValueError("catalog must be a list")
    provenance = {
        k: v for k, v in {
            "source_run_id": args.source_run_id,
            "source_artifact_id": args.source_artifact_id,
            "source_head_sha": args.source_head_sha,
            "source_artifact_digest": args.source_artifact_digest,
        }.items() if v is not None
    }
    result = build_inventory(catalog, snapshot, provenance=provenance)
    if args.compact:
        result = compact_inventory(result)
    out = Path(args.output)
    write_json(out, result)
    digest = sha256_file(out)
    Path(str(out) + ".sha256").write_text(f"{digest}  {out.name}\n", encoding="utf-8")
    s = result["summary"]
    print(
        "CITY_OPEN_DATA_GAME_INVENTORY_OK "
        f"datasets={s['catalog_dataset_count']} geospatial={s['geospatial_dataset_count']} "
        f"shape={s['shape_dataset_count']} poi={s['map_poi_candidate_count']} "
        f"realtime={s['continuous_geospatial_dataset_count']} holds={s['hold_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
