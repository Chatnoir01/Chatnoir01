#!/usr/bin/env python3
"""Read-only temporal/provenance diagnostics for blocked UrbIS3D height conflicts.

This tool intentionally does *not* infer construction, demolition, or physical
change from UrbIS database lifecycle fields. It reuses only already-accepted
semantic 2D↔3D matches and reports BuildingFaces provenance verbatim.
"""
from __future__ import annotations

import argparse
import json
from collections import Counter
from datetime import date, datetime
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-citygen-urbis3d-temporal-provenance-v1"
REQUIRED_FIELDS = {
    "INSPIRE_ID",
    "BUSOLID_ID",
    "TYPE",
    "BEGINGENERATION",
    "ENDGENERATION",
    "SOURCEURI",
    "SOURCETYPE",
    "SOURCEID",
}


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _text(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text if text else None


def _unique_text(rows: list[dict[str, Any]], field: str) -> list[str]:
    return sorted({text for row in rows if (text := _text(row.get(field))) is not None})


def _parse_isoish(value: str) -> datetime | None:
    """Parse only explicit ISO-like source values; never guess locale formats."""
    text = value.strip()
    if not text:
        return None
    candidate = text[:-1] + "+00:00" if text.endswith("Z") else text
    try:
        parsed = datetime.fromisoformat(candidate)
    except ValueError:
        try:
            d = date.fromisoformat(candidate)
        except ValueError:
            return None
        return datetime(d.year, d.month, d.day)
    return parsed


def summarize_face_metadata(rows: list[dict[str, Any]], reference_date: str) -> dict[str, Any]:
    if not rows:
        raise ValueError("cannot summarize empty BuildingFaces metadata")
    try:
        reference = date.fromisoformat(reference_date)
    except ValueError as exc:
        raise ValueError(f"reference date must be ISO YYYY-MM-DD: {reference_date!r}") from exc

    begin_values = _unique_text(rows, "BEGINGENERATION")
    parseable_begin_count = 0
    begin_after_reference_count = 0
    unparseable_begin_count = 0
    for value in begin_values:
        parsed = _parse_isoish(value)
        if parsed is None:
            unparseable_begin_count += 1
            continue
        parseable_begin_count += 1
        if parsed.date() > reference:
            begin_after_reference_count += 1

    type_counts = Counter(
        text for row in rows if (text := _text(row.get("TYPE"))) is not None
    )
    return {
        "face_count": len(rows),
        "type_counts": dict(sorted(type_counts.items())),
        "face_inspire_id_values": _unique_text(rows, "INSPIRE_ID"),
        "begin_generation_values": begin_values,
        "end_generation_values": _unique_text(rows, "ENDGENERATION"),
        "source_uri_values": _unique_text(rows, "SOURCEURI"),
        "source_type_values": _unique_text(rows, "SOURCETYPE"),
        "source_id_values": _unique_text(rows, "SOURCEID"),
        "parseable_begin_generation_count": parseable_begin_count,
        "begin_generation_after_reference_count": begin_after_reference_count,
        "unparseable_begin_generation_count": unparseable_begin_count,
        "reference_date": reference_date,
        "policy": {
            "database_lifecycle_metadata_only": True,
            "physical_change_inference_allowed": False,
            "construction_date_inference_allowed": False,
            "automatic_resolution_allowed": False,
            "runtime_approved": False,
            "thresholds_changed": False,
        },
    }


def _semantic_conflict_map(
    semantic: dict[str, Any], validation: dict[str, Any]
) -> tuple[str, list[tuple[dict[str, Any], dict[str, Any]]]]:
    if (semantic.get("policy") or {}).get("runtime_approval") is not False:
        raise ValueError("semantic witness must remain runtime-unapproved")
    if validation.get("runtime_promotion_allowed") is not False:
        raise ValueError("validation witness must forbid runtime promotion")
    if validation.get("runtime_approved_count") != 0:
        raise ValueError("validation witness unexpectedly contains runtime approvals")

    semantic_cell = _text(semantic.get("cell"))
    validation_cell = _text(validation.get("cell_id"))
    if not semantic_cell or semantic_cell != validation_cell:
        raise ValueError("semantic/validation cell mismatch")

    matches_by_building: dict[str, dict[str, Any]] = {}
    for match in semantic.get("matches") or []:
        if not isinstance(match, dict) or match.get("status") != "matched_semantic_evidence":
            continue
        building_id = _text(match.get("matched_inspire_id"))
        if not building_id:
            continue
        if match.get("runtime_approved") is not False:
            raise ValueError(f"semantic match unexpectedly runtime-approved: {building_id}")
        busolid_id = _text(match.get("busolid_id"))
        if not busolid_id:
            raise ValueError(f"semantic match has no BUSOLID identity: {building_id}")
        if building_id in matches_by_building:
            raise ValueError(f"duplicate accepted semantic match: {building_id}")
        matches_by_building[building_id] = match

    pairs: list[tuple[dict[str, Any], dict[str, Any]]] = []
    for candidate in validation.get("candidates") or []:
        if not isinstance(candidate, dict) or candidate.get("secondary_status") != "blocked_conflict":
            continue
        building_id = _text(candidate.get("building_id"))
        if not building_id:
            raise ValueError("blocked conflict is missing building identity")
        if candidate.get("runtime_approved") is not False:
            raise ValueError(f"blocked conflict unexpectedly runtime-approved: {building_id}")
        match = matches_by_building.get(building_id)
        if match is None:
            raise ValueError(f"blocked conflict has no exact accepted semantic match: {building_id}")
        pairs.append((candidate, match))
    if not pairs:
        raise ValueError("validation witness contains no blocked height conflicts")
    pairs.sort(key=lambda pair: str(pair[0]["building_id"]))
    return semantic_cell, pairs


def _find_buildingfaces_sources(root: Path) -> list[Path]:
    try:
        from osgeo import ogr  # type: ignore
    except ImportError as exc:
        raise RuntimeError("GDAL/OGR is required for live UrbIS3D provenance diagnostics") from exc

    found: list[Path] = []
    observed: list[dict[str, Any]] = []
    for path in sorted(root.rglob("*.gpkg")):
        ds = ogr.Open(str(path), 0)
        if ds is None:
            continue
        layer = ds.GetLayerByName("BuildingFaces")
        if layer is None:
            continue
        definition = layer.GetLayerDefn()
        fields = {definition.GetFieldDefn(i).GetName() for i in range(definition.GetFieldCount())}
        observed.append({"path": str(path), "fields": sorted(fields)})
        if REQUIRED_FIELDS.issubset(fields):
            found.append(path)
    if not found:
        raise ValueError(f"no BuildingFaces source has required provenance fields; observed={observed}")
    return found


def _face_rows_for_busolid(paths: list[Path], busolid_id: str) -> list[dict[str, Any]]:
    try:
        from osgeo import ogr  # type: ignore
    except ImportError as exc:
        raise RuntimeError("GDAL/OGR is required for live UrbIS3D provenance diagnostics") from exc

    # OGR SQL string literal escaping. Identity itself is never transformed/fuzzed.
    escaped = busolid_id.replace("'", "''")
    by_face: dict[str, dict[str, Any]] = {}
    anonymous: list[dict[str, Any]] = []
    for path in paths:
        ds = ogr.Open(str(path), 0)
        if ds is None:
            continue
        layer = ds.GetLayerByName("BuildingFaces")
        if layer is None:
            continue
        if layer.SetAttributeFilter(f"BUSOLID_ID = '{escaped}'") != 0:
            raise ValueError(f"failed exact BUSOLID filter for {busolid_id}")
        definition = layer.GetLayerDefn()
        index = {definition.GetFieldDefn(i).GetName(): i for i in range(definition.GetFieldCount())}
        for feature in layer:
            row: dict[str, Any] = {}
            for field in REQUIRED_FIELDS:
                idx = index[field]
                row[field] = feature.GetFieldAsString(idx) if feature.IsFieldSetAndNotNull(idx) else None
            if _text(row.get("BUSOLID_ID")) != busolid_id:
                raise ValueError(f"BUSOLID filter returned non-identical identity: {busolid_id}")
            face_id = _text(row.get("INSPIRE_ID"))
            if face_id is None:
                anonymous.append(row)
                continue
            prior = by_face.get(face_id)
            if prior is not None and prior != row:
                raise ValueError(f"conflicting duplicate BuildingFace metadata: {face_id}")
            by_face[face_id] = row
        layer.SetAttributeFilter(None)

    rows = list(by_face.values()) + anonymous
    rows.sort(key=lambda row: (
        _text(row.get("INSPIRE_ID")) or "",
        _text(row.get("TYPE")) or "",
        _text(row.get("BEGINGENERATION")) or "",
    ))
    if not rows:
        raise ValueError(f"no BuildingFaces rows for accepted BUSOLID identity: {busolid_id}")
    return rows


def build(
    root: Path,
    semantic: dict[str, Any],
    validation: dict[str, Any],
    reference_date: str,
) -> dict[str, Any]:
    cell, pairs = _semantic_conflict_map(semantic, validation)
    sources = _find_buildingfaces_sources(root)

    records: list[dict[str, Any]] = []
    total_faces = 0
    post_reference_records = 0
    for candidate, match in pairs:
        building_id = str(candidate["building_id"])
        busolid_id = str(match["busolid_id"])
        rows = _face_rows_for_busolid(sources, busolid_id)
        metadata = summarize_face_metadata(rows, reference_date)
        total_faces += metadata["face_count"]
        if metadata["begin_generation_after_reference_count"] > 0:
            post_reference_records += 1
        records.append({
            "building_id": building_id,
            "busolid_id": busolid_id,
            "candidate_height_m": candidate.get("candidate_height_m"),
            "semantic_height_m": candidate.get("semantic_height_m"),
            "metadata": metadata,
            "runtime_approved": False,
        })

    return {
        "format": FORMAT,
        "cell_id": cell,
        "reference_date": reference_date,
        "counts": {
            "blocked_conflicts": len(pairs),
            "records": len(records),
            "buildingfaces_rows": total_faces,
            "records_with_begin_generation_after_reference": post_reference_records,
            "gpkg_sources_with_required_buildingfaces_schema": len(sources),
        },
        "source_files": [str(path) for path in sources],
        "records": records,
        "policy": {
            "read_only": True,
            "identity_source": "exact BUSOLID_ID from already-accepted semantic match only",
            "database_lifecycle_metadata_only": True,
            "physical_change_inference_allowed": False,
            "construction_date_inference_allowed": False,
            "automatic_resolution_allowed": False,
            "runtime_promotion_allowed": False,
            "thresholds_changed": False,
            "note": (
                "UrbIS3D generation/end-generation fields are database lifecycle metadata; "
                "they do not establish real-world construction or demolition chronology."
            ),
        },
        "runtime_approved_count": 0,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--semantic", type=Path, required=True)
    parser.add_argument("--validation", type=Path, required=True)
    parser.add_argument("--reference-date", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    result = build(args.root, _read(args.semantic), _read(args.validation), args.reference_date)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "URBIS3D_TEMPORAL_PROVENANCE_OK",
        result["cell_id"],
        f"conflicts={result['counts']['blocked_conflicts']}",
        f"faces={result['counts']['buildingfaces_rows']}",
        f"post_reference_records={result['counts']['records_with_begin_generation_after_reference']}",
        "physical_change_inference=false",
        "runtime=false",
    )


if __name__ == "__main__":
    main()
