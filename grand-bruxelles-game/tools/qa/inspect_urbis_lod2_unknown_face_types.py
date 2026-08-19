#!/usr/bin/env python3
"""Emit raw DBF properties for selected B01 BuildingFaces whose type is unknown."""

from __future__ import annotations

import argparse
import importlib.util
import io
import json
import tempfile
import zipfile
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


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    root = args.repo_root.resolve()
    verifier = load_module(
        "urbis_batch_verifier",
        root / "grand-bruxelles-game/tools/qa/verify_urbis_lod2_source_batch.py",
    )
    audit = load_module(
        "urbis_batch_complexity",
        root / "grand-bruxelles-game/tools/qa/audit_urbis_lod2_batch_complexity.py",
    )
    contract = json.loads(args.contract.read_text(encoding="utf-8"))
    source = contract["source"]
    distribution_url = verifier.resolve_distribution(
        verifier.DEFAULT_FEED, source["distribution_key"], source["revision"]
    )
    package = verifier.http_get(distribution_url)
    selected, owners, _ = audit.select_batch(contract, verifier, root, package)
    solid_to_owner: dict[str, str] = {}
    for building_id in selected:
        for solid_id in owners[building_id]["solid_ids"]:
            solid_to_owner[str(solid_id)] = building_id
    selected_urls = set(solid_to_owner)
    selected_numeric = {url.rsplit("/", 1)[-1] for url in selected_urls}

    unknown: list[dict[str, Any]] = []
    with zipfile.ZipFile(io.BytesIO(package)) as archive, tempfile.TemporaryDirectory() as tmp:
        dbf_name = audit.layer_member(archive, "buildingface", ".dbf")
        if not dbf_name:
            raise RuntimeError("BuildingFaces DBF missing")
        archive.extract(dbf_name, tmp)
        reader = shapefile.Reader(
            dbf=str(Path(tmp) / dbf_name),
            encoding="utf-8",
            encodingErrors="replace",
        )
        for record in reader.iterRecords():
            values = record.as_dict()
            solid_id = audit.record_solid(values, selected_urls, selected_numeric)
            if not solid_id:
                continue
            if audit.record_face_type(values) != "UNKNOWN":
                continue
            unknown.append({
                "building_id": solid_to_owner[solid_id],
                "solid_id": solid_id,
                "face_id": audit.record_face_id(values),
                "raw_properties": values,
            })

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(unknown, ensure_ascii=False, indent=2, default=str) + "\n", encoding="utf-8")
    print(f"URBIS_LOD2_UNKNOWN_FACE_TYPES_OK: count={len(unknown)}", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
