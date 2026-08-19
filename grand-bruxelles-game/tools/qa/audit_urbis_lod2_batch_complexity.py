#!/usr/bin/env python3
"""Audit the exact source geometry complexity of one verified UrbIS LoD2 batch.

Evidence only. This reuses the production batch contract and verifier, then reads
BuildingFaces for the selected official BuildingSolids. It emits full source face
coordinates only as a CI artifact. It never writes runtime data or authorizes
materialization.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import io
import json
import re
import tempfile
import zipfile
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any

import shapefile
from shapely.geometry import Point, shape as shapely_shape

FACE_TYPES = {
    "WALLSURFACE",
    "ROOFSURFACE",
    "GROUNDSURFACE",
    "CLOSURESURFACE",
    "OUTERCEILINGSURFACE",
    "OUTERFLOORSURFACE",
}
SOLID_URL_RE = re.compile(r"https?://databrussels\.be/id/buildingsolid/(\d+)", re.I)
FACE_URL_RE = re.compile(r"https?://databrussels\.be/id/buildingface/(\d+)", re.I)


def load_verifier(repo_root: Path):
    path = repo_root / "grand-bruxelles-game" / "tools" / "qa" / "verify_urbis_lod2_source_batch.py"
    spec = importlib.util.spec_from_file_location("urbis_batch_verifier", path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import verifier: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def layer_member(archive: zipfile.ZipFile, token: str, suffix: str) -> str | None:
    token_l = token.lower()
    suffix_l = suffix.lower()
    matches = [
        name for name in archive.namelist()
        if token_l in Path(name).stem.lower() and name.lower().endswith(suffix_l)
    ]
    if not matches:
        return None
    exact = [name for name in matches if Path(name).stem.lower() in {token_l, token_l + "s"}]
    if len(exact) == 1:
        return exact[0]
    if len(matches) == 1:
        return matches[0]
    raise RuntimeError(f"ambiguous {token} {suffix}: {matches}")


def normalize_solid(value: object, selected_urls: set[str], selected_numeric: set[str]) -> str | None:
    text = str(value or "").strip()
    if text in selected_urls:
        return text
    match = SOLID_URL_RE.fullmatch(text)
    if match and match.group(1) in selected_numeric:
        return next(url for url in selected_urls if url.endswith("/" + match.group(1)))
    if text.isdigit() and text in selected_numeric:
        return next(url for url in selected_urls if url.endswith("/" + text))
    return None


def record_solid(values: dict[str, Any], selected_urls: set[str], selected_numeric: set[str]) -> str | None:
    for value in values.values():
        solid = normalize_solid(value, selected_urls, selected_numeric)
        if solid:
            return solid
    return None


def record_face_id(values: dict[str, Any]) -> str:
    for value in values.values():
        text = str(value or "").strip()
        if FACE_URL_RE.fullmatch(text):
            return text
    return ""


def record_face_type(values: dict[str, Any]) -> str:
    for value in values.values():
        text = str(value or "").strip().upper()
        if text in FACE_TYPES:
            return text
    return "UNKNOWN"


def select_batch(contract: dict[str, Any], verifier, repo_root: Path, package: bytes):
    owners, source_stats = verifier.read_owner_evidence(package)
    persisted = verifier.scan_persisted_ids(repo_root)
    municipality_feature = verifier.request_municipality_feature(contract["municipality"]["name"])
    municipality_geometry = shapely_shape(municipality_feature["geometry"])
    if municipality_geometry.is_empty or not municipality_geometry.is_valid:
        raise RuntimeError("official municipality geometry is invalid/empty")

    bbox = list(map(float, contract["cell"]["bbox"]))
    cell_missing: list[str] = []
    for building_id, owner in owners.items():
        if building_id in persisted or int(owner["xy_samples"]) <= 0:
            continue
        x = float(owner["sum_x"]) / int(owner["xy_samples"])
        y = float(owner["sum_y"]) / int(owner["xy_samples"])
        if not verifier.inside_bbox(x, y, bbox):
            continue
        if not municipality_geometry.covers(Point(x, y)):
            continue
        cell_missing.append(building_id)
    cell_missing.sort(key=int)

    selection = contract["selection"]
    if len(cell_missing) != int(selection["expected_cell_missing_owners"]):
        raise RuntimeError(
            f"cell count drift: expected {selection['expected_cell_missing_owners']}, got {len(cell_missing)}"
        )
    batch_index = int(selection["batch_index"])
    batch_size = int(selection["max_owners"])
    start = (batch_index - 1) * batch_size
    selected = cell_missing[start : start + batch_size]
    if len(selected) != int(selection["expected_owner_count"]):
        raise RuntimeError("selected owner count drift")
    if selected[0] != str(selection["expected_first_building_id"]):
        raise RuntimeError("selected first BU_ID drift")
    if selected[-1] != str(selection["expected_last_building_id"]):
        raise RuntimeError("selected last BU_ID drift")
    return selected, owners, source_stats


def part_payload(shape: Any) -> tuple[list[dict[str, Any]], int, int]:
    points = list(getattr(shape, "points", []) or [])
    z_values = list(getattr(shape, "z", []) or [])
    starts = list(getattr(shape, "parts", []) or [])
    part_types = list(getattr(shape, "partTypes", []) or [])
    if not starts and points:
        starts = [0]
    parts: list[dict[str, Any]] = []
    for index, start in enumerate(starts):
        end = starts[index + 1] if index + 1 < len(starts) else len(points)
        vertices = []
        for point_index in range(start, end):
            x, y = points[point_index][:2]
            z = z_values[point_index] if point_index < len(z_values) else None
            vertices.append([float(x), float(y), None if z is None else float(z)])
        parts.append({
            "part_type": int(part_types[index]) if index < len(part_types) else None,
            "vertices": vertices,
        })
    return parts, len(points), len(starts)


def audit_faces(package: bytes, selected: list[str], owners: dict[str, dict[str, Any]], output_dir: Path):
    selected_owner_set = set(selected)
    solid_to_owner: dict[str, str] = {}
    for building_id in selected:
        for solid_id in owners[building_id]["solid_ids"]:
            solid_to_owner[str(solid_id)] = building_id
    selected_urls = set(solid_to_owner)
    selected_numeric = {url.rsplit("/", 1)[-1] for url in selected_urls}

    owner_face_count = Counter()
    owner_point_count = Counter()
    owner_part_count = Counter()
    owner_types: dict[str, Counter] = defaultdict(Counter)
    solid_face_count = Counter()
    total_face_count = 0
    total_point_count = 0
    total_part_count = 0
    face_types = Counter()

    output_dir.mkdir(parents=True, exist_ok=True)
    geometry_path = output_dir / "selected_building_faces.ndjson"

    with zipfile.ZipFile(io.BytesIO(package)) as archive, tempfile.TemporaryDirectory() as tmp:
        shp_name = layer_member(archive, "buildingface", ".shp")
        dbf_name = layer_member(archive, "buildingface", ".dbf")
        shx_name = layer_member(archive, "buildingface", ".shx")
        if not shp_name or not dbf_name:
            raise RuntimeError("BuildingFaces SHP/DBF missing from resolved distribution")
        for name in [shp_name, dbf_name] + ([shx_name] if shx_name else []):
            archive.extract(name, tmp)

        face_shp_sha256 = hashlib.sha256(archive.read(shp_name)).hexdigest()
        face_dbf_sha256 = hashlib.sha256(archive.read(dbf_name)).hexdigest()
        kwargs: dict[str, str] = {
            "shp": str(Path(tmp) / shp_name),
            "dbf": str(Path(tmp) / dbf_name),
        }
        if shx_name:
            kwargs["shx"] = str(Path(tmp) / shx_name)
        reader = shapefile.Reader(**kwargs, encoding="utf-8", encodingErrors="replace")

        with geometry_path.open("w", encoding="utf-8") as geometry_handle:
            for shape_record in reader.iterShapeRecords():
                values = shape_record.record.as_dict()
                solid_id = record_solid(values, selected_urls, selected_numeric)
                if not solid_id:
                    continue
                building_id = solid_to_owner[solid_id]
                if building_id not in selected_owner_set:
                    raise RuntimeError("matched face resolved outside selected owner set")
                face_type = record_face_type(values)
                parts, point_count, part_count = part_payload(shape_record.shape)
                face_payload = {
                    "building_id": building_id,
                    "solid_id": solid_id,
                    "face_id": record_face_id(values),
                    "face_type": face_type,
                    "parts": parts,
                }
                geometry_handle.write(json.dumps(face_payload, ensure_ascii=False, separators=(",", ":")) + "\n")

                total_face_count += 1
                total_point_count += point_count
                total_part_count += part_count
                face_types[face_type] += 1
                solid_face_count[solid_id] += 1
                owner_face_count[building_id] += 1
                owner_point_count[building_id] += point_count
                owner_part_count[building_id] += part_count
                owner_types[building_id][face_type] += 1

    missing_solids = sorted(selected_urls - set(solid_face_count))
    if missing_solids:
        raise RuntimeError(f"{len(missing_solids)} selected solid(s) have no matched BuildingFaces")

    owner_rows = []
    for building_id in selected:
        owner_rows.append({
            "building_id": building_id,
            "solid_count": len(owners[building_id]["solid_ids"]),
            "face_count": owner_face_count[building_id],
            "point_count": owner_point_count[building_id],
            "part_count": owner_part_count[building_id],
            "wall_faces": owner_types[building_id]["WALLSURFACE"],
            "roof_faces": owner_types[building_id]["ROOFSURFACE"],
            "ground_faces": owner_types[building_id]["GROUNDSURFACE"],
            "unknown_faces": owner_types[building_id]["UNKNOWN"],
        })
    with (output_dir / "per_owner_complexity.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(owner_rows[0]))
        writer.writeheader()
        writer.writerows(owner_rows)

    return {
        "building_faces_shp_sha256": face_shp_sha256,
        "building_faces_dbf_sha256": face_dbf_sha256,
        "selected_solid_count": len(selected_urls),
        "matched_solid_count": len(solid_face_count),
        "face_count": total_face_count,
        "point_count": total_point_count,
        "part_count": total_part_count,
        "face_type_counts": dict(sorted(face_types.items())),
        "source_geometry_ndjson_bytes": geometry_path.stat().st_size,
        "max_owner_faces": max(owner_face_count.values()) if owner_face_count else 0,
        "max_owner_points": max(owner_point_count.values()) if owner_point_count else 0,
        "owners_with_unknown_face_type": sum(1 for value in owner_types.values() if value["UNKNOWN"] > 0),
    }


def run(contract_path: Path, repo_root: Path, output_dir: Path, feed_url: str) -> dict[str, Any]:
    verifier = load_verifier(repo_root)
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    if contract["hard_rules"]["runtime_authorized"] is not False:
        raise RuntimeError("runtime_authorized must remain false")
    if contract["hard_rules"]["materialization_authorized"] is not False:
        raise RuntimeError("materialization_authorized must remain false")

    source = contract["source"]
    distribution_url = verifier.resolve_distribution(feed_url, source["distribution_key"], source["revision"])
    package = verifier.http_get(distribution_url)
    package_sha256 = hashlib.sha256(package).hexdigest()
    selected, owners, source_stats = select_batch(contract, verifier, repo_root, package)
    complexity = audit_faces(package, selected, owners, output_dir)

    result = {
        "schema": "grand-bruxelles-urbis-lod2-batch-complexity-v1",
        "batch_id": contract["batch_id"],
        "production_base_sha": contract["production_base_sha"],
        "audit_main_sha": "3869ca0593975a5fef49631b0deb8253af743f32",
        "source": {
            "distribution_url": distribution_url,
            "revision": source["revision"],
            "package_sha256": package_sha256,
            "building_solids_shp_sha256": source_stats["building_solids_shp_sha256"],
            "building_solids_dbf_sha256": source_stats["building_solids_dbf_sha256"],
        },
        "selected_owner_count": len(selected),
        "selected_first_building_id": selected[0],
        "selected_last_building_id": selected[-1],
        "complexity": complexity,
        "runtime_authorized": False,
        "materialization_authorized": False,
        "note": "Full selected BuildingFaces source coordinates are artifact evidence only; no runtime transform or source modification.",
    }
    (output_dir / "complexity.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(
        "URBIS_LOD2_BATCH_COMPLEXITY_OK: "
        f"batch={contract['batch_id']} owners={len(selected)} solids={complexity['selected_solid_count']} "
        f"faces={complexity['face_count']} points={complexity['point_count']} "
        f"bytes={complexity['source_geometry_ndjson_bytes']}",
        flush=True,
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path("."))
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--feed-url", default=None)
    args = parser.parse_args()
    repo_root = args.repo_root.resolve()
    verifier = load_verifier(repo_root)
    feed_url = args.feed_url or verifier.DEFAULT_FEED
    try:
        run(args.contract.resolve(), repo_root, args.output_dir.resolve(), feed_url)
    except Exception as exc:
        print(f"URBIS_LOD2_BATCH_COMPLEXITY_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
