#!/usr/bin/env python3
"""Materialize one immutable verified UrbIS LoD2 source registry batch.

The registry stores the exact official BU_ID owner list plus source hashes. This
materializer regenerates one NDJSON record per selected official BuildingFace,
retaining owner/solid/face IDs, raw UrbIS face TYPE and original EPSG:31370 XYZ
coordinates. Selection never depends on what other batches are currently present
in repository data, so a registry remains reproducible after future persistence.

No game-world transform, semantic naming, collision or runtime authorization is
performed here.
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
from shapely.geometry import Point, shape as shapely_shape


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


def load_registry(registry_path: Path, repo_root: Path) -> tuple[dict[str, Any], dict[str, Any], Path]:
    registry = json.loads(registry_path.read_text(encoding="utf-8"))
    if registry.get("storage_policy") != "regenerate_from_locked_official_source":
        raise RuntimeError("registry storage_policy must be regenerate_from_locked_official_source")
    for key in [
        "runtime_authorized",
        "runtime_mount_authorized",
        "collision_authorized",
        "geometry_modified",
        "semantic_names_authorized",
    ]:
        if registry.get(key) is not False:
            raise RuntimeError(f"registry must keep {key}=false")

    contract_rel = registry.get("contract")
    if not isinstance(contract_rel, str) or not contract_rel:
        raise RuntimeError("registry contract path is missing")
    contract_path = repo_root / contract_rel
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    hard = contract.get("hard_rules", {})
    if hard.get("runtime_authorized") is not False:
        raise RuntimeError("contract must keep runtime_authorized=false")
    if hard.get("materialization_authorized") is not False:
        raise RuntimeError("contract must keep materialization_authorized=false")
    return registry, contract, contract_path


def locked_selection(registry: dict[str, Any]) -> list[str]:
    selection = registry.get("selection", {})
    selected = [str(value) for value in selection.get("owner_ids", [])]
    if not selected:
        raise RuntimeError("registry selection.owner_ids is empty")
    if len(selected) != len(set(selected)):
        raise RuntimeError("registry selection.owner_ids contains duplicates")
    if any(not value.isdigit() for value in selected):
        raise RuntimeError("registry selection.owner_ids must contain numeric BU_ID strings")
    if selected != sorted(selected, key=int):
        raise RuntimeError("registry selection.owner_ids must be sorted by numeric BU_ID")
    if len(selected) != int(selection["owner_count"]):
        raise RuntimeError(
            f"registry owner count mismatch: list={len(selected)} manifest={selection['owner_count']}"
        )
    if selected[0] != str(selection["first_building_id"]):
        raise RuntimeError("registry first BU_ID mismatch")
    if selected[-1] != str(selection["last_building_id"]):
        raise RuntimeError("registry last BU_ID mismatch")
    digest = selected_owner_sha256(selected)
    if digest != selection["selected_owner_ids_sha256"]:
        raise RuntimeError(
            f"registry owner-list digest mismatch: expected {selection['selected_owner_ids_sha256']}, got {digest}"
        )
    return selected


def verify_selection_geometry(
    selected: list[str],
    owners: dict[str, dict[str, Any]],
    contract: dict[str, Any],
    verifier,
) -> None:
    municipality_name = contract["municipality"]["name"]
    municipality_feature = verifier.request_municipality_feature(municipality_name)
    municipality_geometry = shapely_shape(municipality_feature["geometry"])
    if municipality_geometry.is_empty or not municipality_geometry.is_valid:
        raise RuntimeError("official municipality geometry is invalid/empty")

    bbox = list(map(float, contract["cell"]["bbox"]))
    for building_id in selected:
        owner = owners.get(building_id)
        if owner is None:
            raise RuntimeError(f"locked BU_ID {building_id} missing from official source package")
        samples = int(owner["xy_samples"])
        if samples <= 0:
            raise RuntimeError(f"locked BU_ID {building_id} has no usable official XY sample")
        x = float(owner["sum_x"]) / samples
        y = float(owner["sum_y"]) / samples
        if not verifier.inside_bbox(x, y, bbox):
            raise RuntimeError(f"locked BU_ID {building_id} drifted outside registry cell")
        if not municipality_geometry.covers(Point(x, y)):
            raise RuntimeError(
                f"locked BU_ID {building_id} drifted outside official municipality {municipality_name}"
            )


def materialize(
    repo_root: Path,
    registry_path: Path,
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

    registry, contract, contract_path = load_registry(registry_path, repo_root)
    selected = locked_selection(registry)

    source = registry["source"]
    contract_source = contract["source"]
    for key in ["dataset_id", "revision", "distribution_key", "license"]:
        if str(source.get(key)) != str(contract_source.get(key)):
            raise RuntimeError(f"registry/contract source mismatch for {key}")

    distribution_url = verifier.resolve_distribution(
        verifier.DEFAULT_FEED,
        source["distribution_key"],
        source["revision"],
    )
    package = verifier.http_get(distribution_url)
    package_sha256 = sha256_bytes(package)
    if package_sha256 != source["package_sha256"]:
        raise RuntimeError(
            f"official package hash drift: expected {source['package_sha256']}, got {package_sha256}"
        )

    owners, solids_stats = verifier.read_owner_evidence(package)
    verify_selection_geometry(selected, owners, contract, verifier)

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
        if face_shp_sha256 != source["building_faces_shp_sha256"]:
            raise RuntimeError("BuildingFaces SHP hash drift")
        if face_dbf_sha256 != source["building_faces_dbf_sha256"]:
            raise RuntimeError("BuildingFaces DBF hash drift")
        if solids_stats["building_solids_shp_sha256"] != source["building_solids_shp_sha256"]:
            raise RuntimeError("BuildingSolids SHP hash drift")
        if solids_stats["building_solids_dbf_sha256"] != source["building_solids_dbf_sha256"]:
            raise RuntimeError("BuildingSolids DBF hash drift")

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
        "schema": "grand-bruxelles-urbis-lod2-source-batch-materialization-v2",
        "batch_id": registry["batch_id"],
        "registry": str(registry_path.relative_to(repo_root)),
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
        f"batch={registry['batch_id']} owners={len(selected)} solids={len(selected_urls)} "
        f"faces={face_count} points={point_count} parts={part_count} "
        f"bytes={len(source_payload)} sha256={report['output']['sha256']}",
        flush=True,
    )
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--registry", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()

    root = args.repo_root.resolve()
    try:
        materialize(
            root,
            args.registry.resolve(),
            args.output.resolve(),
            args.report.resolve(),
        )
    except Exception as exc:
        print(f"URBIS_LOD2_SOURCE_BATCH_MATERIALIZATION_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
