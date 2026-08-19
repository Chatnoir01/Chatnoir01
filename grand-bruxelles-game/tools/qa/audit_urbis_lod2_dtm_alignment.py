#!/usr/bin/env python3
"""Measure B01 UrbIS LoD2 ground-face elevations against official UrbIS DTM 2021.

Evidence only. The tool resolves and hashes the official DTM archives needed by
B01, validates their 0.5 m EPSG:31370 grid metadata, samples the DTM at each
unique official GROUNDSURFACE vertex, and reports source_ground_z - dtm_z.

No vertical offset, pass threshold, terrain mesh, collision or runtime mount is
authorized here.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import shutil
import statistics
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
import zipfile
from collections import defaultdict
from pathlib import Path, PurePosixPath
from typing import Any

USER_AGENT = "Grand-Bruxelles-Game/1.0 (B01 authoritative DTM alignment audit)"
ALLOWED_HOST = "urbisdownload.datastore.brussels"
EXPECTED_EPSG = 31370


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def http_get(url: str, timeout: int = 120) -> bytes:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() != ALLOWED_HOST:
        raise RuntimeError(f"official DTM URL must use {ALLOWED_HOST}: {url}")
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read()


def xml_urls(payload: bytes, base_url: str) -> set[str]:
    root = ET.fromstring(payload)
    urls: set[str] = set()
    for element in root.iter():
        href = element.attrib.get("href") or element.attrib.get("src")
        if href:
            urls.add(urllib.parse.urljoin(base_url, href.strip()))
        text = (element.text or "").strip()
        if text.startswith(("http://", "https://")):
            urls.add(urllib.parse.urljoin(base_url, text))
    return urls


def crawl_feed(start_url: str, max_depth: int = 2) -> tuple[list[dict[str, Any]], set[str]]:
    queue = [(start_url, 0)]
    seen: set[str] = set()
    feed_rows: list[dict[str, Any]] = []
    all_links: set[str] = set()
    while queue:
        url, depth = queue.pop(0)
        if url in seen or depth > max_depth:
            continue
        seen.add(url)
        payload = http_get(url, timeout=90)
        links = xml_urls(payload, url)
        feed_rows.append({"url": url, "depth": depth, "bytes": len(payload), "links": len(links)})
        all_links.update(links)
        if depth < max_depth:
            for child in sorted(links):
                parsed = urllib.parse.urlparse(child)
                low = child.lower()
                if (parsed.hostname or "").lower() == ALLOWED_HOST and (low.endswith(".xml") or "atomfeed" in low):
                    queue.append((child, depth + 1))
    return feed_rows, all_links


def resolve_archives(links: set[str], tiles: list[str]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for tile in tiles:
        matches = sorted({
            url for url in links
            if url.lower().endswith(".zip")
            and tile in Path(urllib.parse.urlparse(url).path).name
            and "dtm" in Path(urllib.parse.urlparse(url).path).name.lower()
        })
        if len(matches) != 1:
            raise RuntimeError(f"expected exactly one official DTM archive for {tile}, got {matches}")
        rows.append({"tile": tile, "url": matches[0]})
    return rows


def nominal_tile_bbox(tile: str) -> tuple[float, float, float, float]:
    if len(tile) != 6 or not tile.isdigit():
        raise RuntimeError(f"invalid DTM tile code {tile}")
    e = int(tile[:3]) * 1000.0
    n = int(tile[3:]) * 1000.0
    return e, n, e + 1000.0, n + 1000.0


def safe_extract_all(archive: Path, destination: Path) -> list[Path]:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    extracted: list[Path] = []
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            path = PurePosixPath(info.filename)
            if path.is_absolute() or ".." in path.parts:
                raise RuntimeError(f"unsafe ZIP member {info.filename}")
            if info.is_dir():
                continue
            target = (destination / Path(*path.parts)).resolve()
            if target != root and root not in target.parents:
                raise RuntimeError(f"ZIP member escapes extraction root: {info.filename}")
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            extracted.append(target)
    return extracted


def download_validate_tiles(
    archives: list[dict[str, str]],
    work_dir: Path,
    expected_resolution: float,
):
    try:
        import rasterio  # type: ignore
    except ImportError as exc:
        raise RuntimeError("rasterio is required") from exc

    datasets = []
    evidence: list[dict[str, Any]] = []
    for item in archives:
        tile = item["tile"]
        url = item["url"]
        payload = http_get(url, timeout=180)
        if not payload:
            raise RuntimeError(f"empty DTM archive {tile}")
        archive_path = work_dir / f"{tile}.zip"
        archive_path.parent.mkdir(parents=True, exist_ok=True)
        archive_path.write_bytes(payload)
        extract_dir = work_dir / tile
        members = safe_extract_all(archive_path, extract_dir)
        tiffs = sorted(path for path in members if path.suffix.lower() in {".tif", ".tiff"})
        if len(tiffs) != 1:
            raise RuntimeError(f"{tile}: expected exactly one TIFF, got {[p.name for p in tiffs]}")
        tif = tiffs[0]
        src = rasterio.open(tif)
        embedded_epsg = src.crs.to_epsg() if src.crs else None
        if embedded_epsg is not None and embedded_epsg != EXPECTED_EPSG:
            src.close()
            raise RuntimeError(f"{tile}: embedded CRS {embedded_epsg} contradicts EPSG:{EXPECTED_EPSG}")
        rx = abs(float(src.transform.a))
        ry = abs(float(src.transform.e))
        if abs(rx - expected_resolution) > 1e-9 or abs(ry - expected_resolution) > 1e-9:
            src.close()
            raise RuntimeError(f"{tile}: expected {expected_resolution} m pixels, got {rx},{ry}")
        if src.width != 2000 or src.height != 2000 or src.count != 1:
            src.close()
            raise RuntimeError(f"{tile}: unexpected raster dimensions {src.width}x{src.height} bands={src.count}")
        expected_bounds = nominal_tile_bbox(tile)
        actual_bounds = [float(src.bounds.left), float(src.bounds.bottom), float(src.bounds.right), float(src.bounds.top)]
        for got, want in zip(actual_bounds, expected_bounds):
            if abs(got - want) > expected_resolution:
                src.close()
                raise RuntimeError(f"{tile}: bounds {actual_bounds} do not match nominal {list(expected_bounds)}")
        evidence.append({
            "tile": tile,
            "url": url,
            "archive_bytes": len(payload),
            "archive_sha256": sha256_bytes(payload),
            "raster_filename": tif.name,
            "raster_sha256": sha256_file(tif),
            "width": src.width,
            "height": src.height,
            "dtype": src.dtypes[0],
            "embedded_crs_epsg": embedded_epsg,
            "crs_epsg": embedded_epsg or EXPECTED_EPSG,
            "crs_basis": "embedded_raster" if embedded_epsg is not None else "authoritative_contract",
            "bounds": actual_bounds,
            "resolution": [rx, ry],
            "nodata": src.nodata,
            "transform": [float(v) for v in src.transform[:6]],
        })
        datasets.append((tile, src))
    return datasets, evidence


def percentile(values: list[float], q: float) -> float:
    if not values:
        raise RuntimeError("percentile requires values")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = (len(ordered) - 1) * q
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1.0 - weight) + ordered[upper] * weight


def sample_dtm(datasets, easting: float, northing: float) -> tuple[str, float]:
    for tile, src in datasets:
        b = src.bounds
        if not (float(b.left) <= easting < float(b.right) and float(b.bottom) < northing <= float(b.top)):
            continue
        sample = next(src.sample([(easting, northing)], masked=True))
        value = sample[0]
        if hasattr(value, "mask") and bool(value.mask):
            raise RuntimeError(f"DTM nodata at {easting},{northing} in tile {tile}")
        dtm_z = float(value)
        nodata = src.nodata
        if not math.isfinite(dtm_z) or (nodata is not None and dtm_z == float(nodata)):
            raise RuntimeError(f"invalid DTM value at {easting},{northing} in tile {tile}: {dtm_z}")
        return tile, dtm_z
    raise RuntimeError(f"no validated DTM tile covers source point {easting},{northing}")


def load_ground_vertices(source_path: Path, expected_sha: str):
    payload = source_path.read_bytes()
    if sha256_bytes(payload) != expected_sha:
        raise RuntimeError("B01 source payload SHA drift")
    all_faces = 0
    ground_faces = 0
    owners: set[str] = set()
    solids: set[str] = set()
    owner_vertices: dict[str, set[tuple[float, float, float]]] = defaultdict(set)
    with source_path.open("r", encoding="utf-8") as handle:
        for line in handle:
            text = line.strip()
            if not text:
                continue
            row = json.loads(text)
            all_faces += 1
            owners.add(str(row["building_id"]))
            solids.add(str(row["solid_id"]))
            if str(row["face_type"]) != "GROUNDSURFACE":
                continue
            ground_faces += 1
            building_id = str(row["building_id"])
            for part in row.get("parts", []):
                for vertex in part.get("vertices", []):
                    if len(vertex) < 3 or vertex[2] is None:
                        raise RuntimeError(f"ground face missing XYZ for owner {building_id}")
                    owner_vertices[building_id].add((float(vertex[0]), float(vertex[1]), float(vertex[2])))
    return payload, owners, solids, all_faces, ground_faces, owner_vertices


def close_datasets(datasets) -> None:
    for _, src in datasets:
        src.close()


def run(source_path: Path, contract_path: Path, output_dir: Path, work_dir: Path) -> dict[str, Any]:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    hard = contract["hard_rules"]
    for key in [
        "runtime_authorized", "runtime_mount_authorized", "collision_authorized",
        "final_world_y_authorized", "terrain_runtime_authorized", "source_geometry_modified",
    ]:
        if hard.get(key) is not False:
            raise RuntimeError(f"contract must keep {key}=false")
    if hard.get("artifact_only") is not True:
        raise RuntimeError("contract must remain artifact_only=true")
    if contract["measurement"].get("authorization_threshold") is not None:
        raise RuntimeError("measurement-only gate must not contain an authorization threshold")

    dtm = contract["dtm"]
    feed_rows, links = crawl_feed(dtm["atom_feed"])
    archives = resolve_archives(links, list(dtm["expected_1km_tile_codes"]))
    datasets = []
    try:
        datasets, archive_evidence = download_validate_tiles(
            archives, work_dir, float(dtm["expected_resolution_m"])
        )
        payload, owners, solids, all_faces, ground_faces, owner_vertices = load_ground_vertices(
            source_path, contract["source_payload_sha256"]
        )
        expected = contract["expected_source"]
        if len(owners) != int(expected["owners"]):
            raise RuntimeError(f"owner count drift: {len(owners)}")
        if len(solids) != int(expected["solids"]):
            raise RuntimeError(f"solid count drift: {len(solids)}")
        if all_faces != int(expected["all_faces"]):
            raise RuntimeError(f"face count drift: {all_faces}")
        if ground_faces != int(expected["ground_faces"]):
            raise RuntimeError(f"ground face count drift: {ground_faces}")
        if set(owner_vertices) != owners:
            missing = sorted(owners - set(owner_vertices), key=int)
            raise RuntimeError(f"owners without GROUNDSURFACE vertices: {missing}")

        residual_rows: list[dict[str, Any]] = []
        owner_residuals: dict[str, list[float]] = defaultdict(list)
        dtm_values: list[float] = []
        source_ground_values: list[float] = []
        for building_id in sorted(owner_vertices, key=int):
            for easting, northing, source_z in sorted(owner_vertices[building_id]):
                tile, dtm_z = sample_dtm(datasets, easting, northing)
                residual = source_z - dtm_z
                owner_residuals[building_id].append(residual)
                dtm_values.append(dtm_z)
                source_ground_values.append(source_z)
                residual_rows.append({
                    "building_id": building_id,
                    "easting": f"{easting:.6f}",
                    "northing": f"{northing:.6f}",
                    "source_ground_z": f"{source_z:.6f}",
                    "dtm_z": f"{dtm_z:.6f}",
                    "residual_source_minus_dtm_m": f"{residual:.6f}",
                    "dtm_tile": tile,
                })

        if not residual_rows:
            raise RuntimeError("no DTM residual samples were produced")
        if len(owner_residuals) != len(owners):
            raise RuntimeError("not every owner received a DTM residual")

        residuals = [float(row["residual_source_minus_dtm_m"]) for row in residual_rows]
        abs_residuals = [abs(value) for value in residuals]
        owner_medians = [statistics.median(values) for values in owner_residuals.values()]
        abs_owner_medians = [abs(value) for value in owner_medians]

        owner_rows: list[dict[str, Any]] = []
        for building_id in sorted(owner_residuals, key=int):
            values = owner_residuals[building_id]
            owner_rows.append({
                "building_id": building_id,
                "sample_count": len(values),
                "median_residual_m": f"{statistics.median(values):.6f}",
                "min_residual_m": f"{min(values):.6f}",
                "max_residual_m": f"{max(values):.6f}",
                "max_abs_residual_m": f"{max(abs(v) for v in values):.6f}",
            })

        output_dir.mkdir(parents=True, exist_ok=True)
        with (output_dir / "ground_vertex_residuals.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(residual_rows[0]))
            writer.writeheader()
            writer.writerows(residual_rows)
        with (output_dir / "per_owner_dtm_alignment.csv").open("w", newline="", encoding="utf-8") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(owner_rows[0]))
            writer.writeheader()
            writer.writerows(owner_rows)

        archive_report = {
            "schema": "grand-bruxelles-b01-dtm-archive-evidence-v1",
            "dataset": dtm["name"],
            "dataset_id": dtm["dataset_id"],
            "source_crs": contract["source_crs"],
            "feeds_crawled": feed_rows,
            "archives": archive_evidence,
        }
        (output_dir / "dtm_archive_evidence.json").write_text(
            json.dumps(archive_report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )

        report = {
            "schema": "grand-bruxelles-urbis-lod2-dtm-alignment-report-v1",
            "batch_id": contract["batch_id"],
            "source_payload_sha256": sha256_bytes(payload),
            "source_counts": {
                "owners": len(owners),
                "solids": len(solids),
                "faces": all_faces,
                "ground_faces": ground_faces,
                "unique_ground_vertices": len(residual_rows),
            },
            "dtm": {
                "dataset": dtm["name"],
                "dataset_id": dtm["dataset_id"],
                "tiles": [item["tile"] for item in archive_evidence],
                "resolution_m": float(dtm["expected_resolution_m"]),
                "sampled_min_z": min(dtm_values),
                "sampled_max_z": max(dtm_values),
            },
            "source_ground_z": {
                "min": min(source_ground_values),
                "max": max(source_ground_values),
            },
            "vertex_residual_source_minus_dtm_m": {
                "count": len(residuals),
                "mean": statistics.fmean(residuals),
                "median": statistics.median(residuals),
                "min": min(residuals),
                "max": max(residuals),
                "abs_p50": percentile(abs_residuals, 0.50),
                "abs_p90": percentile(abs_residuals, 0.90),
                "abs_p95": percentile(abs_residuals, 0.95),
                "abs_p99": percentile(abs_residuals, 0.99),
                "abs_max": max(abs_residuals),
                "within_0_25m": sum(1 for value in abs_residuals if value <= 0.25),
                "within_0_50m": sum(1 for value in abs_residuals if value <= 0.50),
                "within_1m": sum(1 for value in abs_residuals if value <= 1.0),
                "within_2m": sum(1 for value in abs_residuals if value <= 2.0),
                "within_5m": sum(1 for value in abs_residuals if value <= 5.0),
            },
            "owner_median_residual_m": {
                "count": len(owner_medians),
                "mean": statistics.fmean(owner_medians),
                "median": statistics.median(owner_medians),
                "min": min(owner_medians),
                "max": max(owner_medians),
                "abs_p50": percentile(abs_owner_medians, 0.50),
                "abs_p90": percentile(abs_owner_medians, 0.90),
                "abs_p95": percentile(abs_owner_medians, 0.95),
                "abs_max": max(abs_owner_medians),
            },
            "interpretation": {
                "authorization_threshold": None,
                "vertical_datum_compatible": None,
                "final_world_y_authorized": False,
                "note": "Measurement only. A later gate must interpret residuals and define a global terrain/world-Y datum policy before any LoD2 runtime mount."
            },
            "runtime_authorized": False,
            "runtime_mount_authorized": False,
            "collision_authorized": False,
            "final_world_y_authorized": False,
            "terrain_runtime_authorized": False,
            "artifact_only": True,
        }
        (output_dir / "dtm_alignment_report.json").write_text(
            json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(
            "URBIS_LOD2_B01_DTM_ALIGNMENT_MEASURED: "
            f"owners={len(owners)} vertices={len(residuals)} "
            f"median={report['vertex_residual_source_minus_dtm_m']['median']:.6f} "
            f"abs_p95={report['vertex_residual_source_minus_dtm_m']['abs_p95']:.6f} "
            f"owner_abs_p95={report['owner_median_residual_m']['abs_p95']:.6f} "
            "final_world_y_authorized=false",
            flush=True,
        )
        return report
    finally:
        close_datasets(datasets)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--contract", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--work-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        run(args.source.resolve(), args.contract.resolve(), args.output_dir.resolve(), args.work_dir.resolve())
    except Exception as exc:
        print(f"URBIS_LOD2_B01_DTM_ALIGNMENT_ERROR: {exc}", flush=True)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
