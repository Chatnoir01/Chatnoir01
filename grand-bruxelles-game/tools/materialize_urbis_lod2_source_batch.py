#!/usr/bin/env python3
"""Materialize one verified UrbIS LoD2 source batch without runtime transforms.

The output is source persistence only: one NDJSON record per selected official
BuildingFace, retaining official owner/solid/face IDs, raw UrbIS face TYPE and
original EPSG:31370 XYZ coordinates. No game-world transform, semantic naming,
collision or runtime authorization is performed here.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib.util
import io
import json
import tempfile
import zipfile
from collections import Counter
from pathlib import Path
from typing import Any

import shapefile


def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def selected_owner_sha256(selected: list[str]) -> str:
    return sha256_bytes(("\n".join(selected) + "\n").encode("utf-8"))


def materialize(
    repo_root: Path,
    contract_path: Path,
    output_path: Path,
    report_path: Path,
) -> dict[str, Any]:
    verifier = load_module(
        "urbis_batch_verifier",
        repo_root / "grand-bruxelles-game/tools/qa/verify_urbis_lod2_source_batch.py",
    )
    audit = load_module(
        "urbis_batch_complexity",
        repo_root / "grand-bruxelles-game/tools/qa/audit_urbis_lod2_batch_complexity.py",
    )

    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    hard = contract.get("hard_rules", {})
    if hard.get("runtime_authorized") is not False:
        raise RuntimeError("contract must keep runtime_authorized=false")
    if hard.get("materialization_authorized") is not False:
        raise RuntimeError("contract must keep materialization_authorized=false")

    source = contract["source"]
    distribution_url = verifier.resolve_distribution(
        verifier.DEFAULT_FEED,
        source["distribution_key"],
        source["revision"],
    )
    package = verifier.http_get(distribution_url)
    package_sha256 = sha256_bytes(package)

    selected, owners, solids_stats = audit.select_batch(
        contract, verifier, repo_root, package
    )
    solid_to_owner: dict[str, str] = {}
    for building_id in selected:
        for solid_id in owners[building_id]["solid_ids"]:
            solid_id = str(solid_id)
            previous = solid_to_owner.setdefault(solid_id, building_id)
            if previous != building_id:
                raise RuntimeError(
                    f"solid {solid_id} maps to multiple selected owners: {previous}, {building_id}"
                )

    selected_urls = set(solid_to_owner)
    selected_numeric = {url.rsplit("/", 1)[-1] for url in selected_urls}
    matched_solids: set[str] = set()
    face_types: Counter[str] = Counter()
    face_count = 0
    point_count = 0
    part_count = 0

    output_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(io.BytesIO(package)) as archive, tempfile.TemporaryDirectory() as tmp:
        shp_name = audit.layer_member(archive, "buildingface", ".shp")
        dbf_name = audit.layer_member(archive, "buildingface", ".dbf")
        shx_name = audit.layer_member(archive, "buildingface", ".shx")
        if not shp_name or not dbf_name:
            raise RuntimeError("BuildingFaces SHP/DBF missing from resolved distribution")

        face_shp_sha256 = sha256_bytes(archive.read(shp_name))
        face_dbf_sha256 = sha256_bytes(archive.read(dbf_name))

        for name in [shp_name, dbf_name] + ([shx_name] if shx_name else []):
            archive.extract(name, tmp)

        kwargs: dict[str, str] = {
            "shp": str(Path(tmp) / shp_name),
            "dbf": str(Path(tmp) / dbf_name),
        }
        if shx_name:
            kwargs["shx"] = str(Path(tmp) / shx_name)
        reader = shapefile.Reader(
            **kwargs,
            encoding="utf-8",
            encodingErrors="replace",
        )

        with output_path.open("w", encoding="utf-8", newline="\n") as handle:
            for shape_record in reader.iterShapeRecords():
                values = shape_record.record.as_dict()
                solid_id = audit.record_solid(values, selected_urls, selected_numeric)
                if not solid_id:
                    continue

                building_id = solid_to_owner[solid_id]
                face_id = audit.record_face_id(values)
                if not face_id:
                    raise RuntimeError(
                        f"selected solid {solid_id} contains a BuildingFace without official face ID"
                    )
                raw_type = str(values.get("TYPE") or "").strip()
                if not raw_type:
                    raise RuntimeError(f"selected face {face_id} has empty raw TYPE")

                parts, points_here, parts_here = audit.part_payload(shape_record.shape)
                if not parts:
                    raise RuntimeError(f"selected face {face_id} has no source MultiPatch parts")

                record = {
                    "building_id": building_id,
                    "solid_id": solid_id,
                    "face_id": face_id,
                    "face_type": raw_type,
                    "parts": parts,
                }
                handle.write(
                    json.dumps(record, ensure_ascii=False, separators=(",", ":")) + "\n"
                )

                matched_solids.add(solid_id)
                face_types[raw_type] += 1
                face_count += 1
                point_count += points_here
                part_count += parts_here

    missing_solids = sorted(selected_urls - matched_solids)
    if missing_solids:
        raise RuntimeError(
            f"{len(missing_solids)} selected solid(s) have no persisted BuildingFaces"
        )

    source_payload = output_path.read_bytes()
    report = {
        "schema": "grand-bruxelles-urbis-lod2-source-batch-materialization-v1",
        "batch_id": contract["batch_id"],
        "contract": str(contract_path.relative_to(repo_root)),
        "source": {
            "distribution_url": distribution_url,
            "revision": source["revision"],
            "package_sha256": package_sha256,
            "building_solids_shp_sha256": solids_stats["building_solids_shp_sha256"],
            "building_solids_dbf_sha256": solids_stats["building_solids_dbf_sha256"],
            "building_faces_shp_sha256": face_shp_sha256,
            "building_faces_dbf_sha256": face_dbf_sha256,
            "crs": "EPSG:31370",
            "coordinate_payload": "original source XYZ; no game-world transform",
        },
        "selection": {
            "owner_count": len(selected),
            "solid_count": len(selected_urls),
            "face_count": face_count,
            "point_count": point_count,
            "part_count": part_count,
            "first_building_id": selected[0],
            "last_building_id": selected[-1],
            "selected_owner_ids_sha256": selected_owner_sha256(selected),
            "face_type_counts": dict(sorted(face_types.items())),
        },
        "output": {
            "path": str(output_path),
            "bytes": len(source_payload),
            "sha256": sha256_bytes(source_payload),
            "format": "NDJSON / one official BuildingFace per line",
        },
        "runtime_authorized": False,
        "runtime_mount_authorized": False,
        "geometry_modified": False,
        "semantic_names_authorized": False,
    }
    report_path.write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )

    print(
        "URBIS_LOD2_SOURCE_BATCH_MATERIALIZED_OK: "
        f"batch={contract['batch_id']} owners={len(selected)} solids={len(selected_urls)} "
        f"faces={face_count} points={point_count} parts={part_count} "
        f"bytes={len(source_payload)} sha256={report['output']['sha256']}",
        flush=True,
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    root = args.repo_root.resolve()
    try:
        materialize(
            root,
            args.contract.resolve(),
            args.output.resolve(),
            args.report.resolve(),
        )
    except Exception as exc:
        print(f"URBIS_LOD2_SOURCE_BATCH_MATERIALIZATION_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
