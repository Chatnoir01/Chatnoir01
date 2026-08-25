#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

CELL_ID_RE = re.compile(r"^bxl-e(?P<east>-?\d+)-n(?P<north>-?\d+)-s(?P<size>\d+)$")
REQUIRED_SOURCE_ONLY_GATES = (
    "runtime_geometry",
    "collisions",
    "streaming",
    "terrain",
    "heights",
    "photo_match",
    "performance",
)
CANONICAL_MANIFEST_ROOT = Path("data/cell_manifests")


def canonical_json(value: Any) -> bytes:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def parse_manifest_cell_id(cell_id: str) -> tuple[str, int, int, int]:
    match = CELL_ID_RE.fullmatch(cell_id)
    if not match:
        raise RuntimeError(f"invalid registered cell id: {cell_id}")
    east = int(match.group("east"))
    north = int(match.group("north"))
    size = int(match.group("size"))
    if size != 500:
        raise RuntimeError(f"registered cell must use 500 m grid: {cell_id}")
    return f"E{east}_N{north}", east, north, size


def canonical_manifest_path(path: Path, root: Path) -> str:
    if tuple(root.parts[-2:]) != tuple(CANONICAL_MANIFEST_ROOT.parts):
        raise RuntimeError(
            f"registered cell manifest root must end in {CANONICAL_MANIFEST_ROOT.as_posix()}: {root}"
        )
    try:
        relative = path.relative_to(root)
    except ValueError as exc:
        raise RuntimeError(f"registered cell manifest escaped root: {path}") from exc
    if len(relative.parts) != 1 or relative.suffix.lower() != ".json":
        raise RuntimeError(f"registered cell manifest path must be a direct JSON child: {path}")
    return (CANONICAL_MANIFEST_ROOT / relative).as_posix()


def load_registered_cells(root: Path) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for path in sorted(root.glob("*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("format") != "grand-bruxelles-cell-maturity-v1":
            raise RuntimeError(f"unsupported cell manifest format: {path}")
        cell_id = str(payload.get("cell_id", ""))
        driveway_cell_id, east, north, size = parse_manifest_cell_id(cell_id)
        if payload.get("crs") != "EPSG:31370":
            raise RuntimeError(f"registered cell CRS mismatch: {cell_id}")
        bbox = payload.get("bbox")
        expected_bbox = [float(east), float(north), float(east + size), float(north + size)]
        if bbox != expected_bbox:
            raise RuntimeError(f"registered cell bbox mismatch: {cell_id}: {bbox!r} != {expected_bbox!r}")
        maturity = payload.get("maturity") or {}
        if maturity.get("state") != "data_ready":
            raise RuntimeError(f"registered cell maturity state drift: {cell_id}: {maturity.get('state')!r}")
        gates = maturity.get("gates") or {}
        for gate in REQUIRED_SOURCE_ONLY_GATES:
            if gate not in gates or not isinstance(gates[gate], bool):
                raise RuntimeError(f"registered cell missing boolean maturity gate {gate}: {cell_id}")
        for gate, value in gates.items():
            if not isinstance(value, bool):
                raise RuntimeError(f"registered cell maturity gate must be boolean {gate}: {cell_id}")
            if value is not False:
                raise RuntimeError(f"registered cell maturity gate opened unexpectedly {gate}: {cell_id}")
        rows.append({
            "registered_cell_id": cell_id,
            "driveway_cell_id": driveway_cell_id,
            "manifest_path": canonical_manifest_path(path, root),
            "maturity_state": maturity.get("state"),
            "maturity_gates": {key: gates[key] for key in sorted(gates)},
            "runtime_mount_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        })
    if not rows:
        raise RuntimeError("no registered cell manifests found")
    seen = [row["driveway_cell_id"] for row in rows]
    if len(seen) != len(set(seen)):
        raise RuntimeError("duplicate registered driveway cell mapping")
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--driveway-catalog", required=True)
    parser.add_argument("--cell-manifests", required=True)
    parser.add_argument("--production-base-sha", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()

    catalog = json.loads(Path(args.driveway_catalog).read_text(encoding="utf-8"))
    if catalog.get("schema") != "grand-bruxelles-driveway-regional-cell-catalog-v1":
        raise RuntimeError("unexpected driveway catalog schema")
    if catalog.get("destination_readiness") != "DISCOVERED_SOURCE_ONLY":
        raise RuntimeError("driveway catalog readiness drift")
    for key in (
        "source_registration_authorized", "road_crosswalk_authorized", "parking_evidence_runtime_approved",
        "runtime_authorized", "runtime_mount_authorized", "collision_authorized", "materialization_authorized",
        "semantic_names_authorized", "game_world_transform_authorized", "jouable_promotion_authorized",
    ):
        if catalog.get(key) is not False:
            raise RuntimeError(f"driveway catalog rail opened unexpectedly: {key}")

    source_cells = catalog.get("partition", {}).get("cells") or []
    source_by_cell: dict[str, list[dict[str, Any]]] = {}
    for row in source_cells:
        cell_id = str(row.get("cell_id", ""))
        if not re.fullmatch(r"E-?\d+_N-?\d+", cell_id):
            raise RuntimeError(f"invalid driveway source cell id: {cell_id}")
        feature_count = row.get("feature_count")
        if not isinstance(feature_count, int) or feature_count <= 0:
            raise RuntimeError(f"invalid driveway feature count for {cell_id}")
        source_by_cell.setdefault(cell_id, []).append(row)

    registered = load_registered_cells(Path(args.cell_manifests))
    matches: list[dict[str, Any]] = []
    unmatched_registered: list[dict[str, Any]] = []
    for cell in registered:
        source_rows = source_by_cell.get(cell["driveway_cell_id"], [])
        if not source_rows:
            unmatched_registered.append(cell)
            continue
        municipalities = sorted(str(row["municipality"]) for row in source_rows)
        feature_count = sum(int(row["feature_count"]) for row in source_rows)
        matches.append({
            **cell,
            "driveway_municipalities": municipalities,
            "driveway_feature_count": feature_count,
            "crosswalk_evidence_only": True,
            "road_crosswalk_authorized": False,
        })

    result = {
        "schema": "grand-bruxelles-driveway-registered-cell-crosswalk-v1",
        "production_base_sha": args.production_base_sha,
        "source_catalog": {
            "schema": catalog["schema"],
            "feature_count": catalog["source"]["feature_count"],
            "cell_count": catalog["partition"]["cell_count"],
            "cells_sha256": catalog["partition"]["cells_sha256"],
        },
        "registered_manifest_count": len(registered),
        "matched_registered_manifest_count": len(matches),
        "unmatched_registered_manifest_count": len(unmatched_registered),
        "matches": matches,
        "unmatched_registered_cells": unmatched_registered,
        "destination_readiness": "CELL_CROSSWALK_EVIDENCE_ONLY",
        "source_registration_authorized": False,
        "road_crosswalk_authorized": False,
        "parking_evidence_runtime_approved": False,
        "runtime_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    semantic = dict(result)
    semantic.pop("production_base_sha", None)
    result["semantic_sha256"] = sha256(canonical_json(semantic))
    Path(args.out).write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "DRIVEWAY_REGISTERED_CELL_CROSSWALK_OK "
        f"registered={len(registered)} matched={len(matches)} unmatched={len(unmatched_registered)} "
        f"semantic_sha256={result['semantic_sha256']}"
    )


if __name__ == "__main__":
    main()
