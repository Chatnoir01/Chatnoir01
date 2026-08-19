#!/usr/bin/env python3
"""Measure C01 30k LoD2 ground faces against official UrbIS DTM and evaluate rigid owner anchors.

Evidence only: source vertices are never warped and this tool cannot authorize final world Y,
runtime mounting, terrain mounting, collisions, or JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import math
import shutil
import statistics
import subprocess
import time
import urllib.parse
import xml.etree.ElementTree as ET
import zipfile
from collections import defaultdict
from pathlib import Path, PurePosixPath
from typing import Any

ALLOWED_HOST = "urbisdownload.datastore.brussels"
EXPECTED_EPSG = 31370


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def percentile(values: list[float], q: float) -> float:
    if not values:
        raise RuntimeError("percentile requires values")
    values = sorted(values)
    if len(values) == 1:
        return values[0]
    pos = (len(values) - 1) * q
    lo, hi = math.floor(pos), math.ceil(pos)
    if lo == hi:
        return values[lo]
    w = pos - lo
    return values[lo] * (1.0 - w) + values[hi] * w


def validate_hard_rules(contract: dict[str, Any]) -> None:
    hard = contract["hard_rules"]
    for key in [
        "runtime_authorized", "runtime_mount_authorized", "collision_authorized",
        "final_world_y_authorized", "terrain_runtime_authorized",
        "source_geometry_modified", "jouable_promotion_authorized",
    ]:
        if hard.get(key) is not False:
            raise RuntimeError(f"contract must keep {key}=false")
    if hard.get("owner_rigid_translation_only") is not True:
        raise RuntimeError("owner_rigid_translation_only must be true")
    if hard.get("artifact_only") is not True:
        raise RuntimeError("artifact_only must be true")
    policy = contract["policy"]
    if policy.get("source_vertex_warping_allowed") is not False:
        raise RuntimeError("source vertex warping must remain forbidden")
    if policy.get("authorization_threshold") is not None:
        raise RuntimeError("measurement lot cannot contain an authorization threshold")


def safe_extract_zip(archive: Path, destination: Path) -> list[Path]:
    destination.mkdir(parents=True, exist_ok=True)
    root = destination.resolve()
    out: list[Path] = []
    with zipfile.ZipFile(archive) as zf:
        for info in zf.infolist():
            p = PurePosixPath(info.filename)
            if p.is_absolute() or ".." in p.parts:
                raise RuntimeError(f"unsafe ZIP member: {info.filename}")
            if info.is_dir():
                continue
            target = (destination / Path(*p.parts)).resolve()
            if target != root and root not in target.parents:
                raise RuntimeError(f"ZIP member escapes extraction root: {info.filename}")
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info) as src, target.open("wb") as dst:
                shutil.copyfileobj(src, dst)
            out.append(target)
    return out


def bounded_curl(url: str, output: Path, retries: int = 4, max_seconds: int = 180) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or (parsed.hostname or "").lower() != ALLOWED_HOST:
        raise RuntimeError(f"URL must use locked official host {ALLOWED_HOST}: {url}")
    output.parent.mkdir(parents=True, exist_ok=True)
    last = ""
    for attempt in range(1, retries + 1):
        tmp = output.with_suffix(output.suffix + ".partial")
        tmp.unlink(missing_ok=True)
        cmd = [
            "curl", "--fail", "--location", "--silent", "--show-error",
            "--connect-timeout", "20", "--max-time", str(max_seconds),
            "--speed-limit", "1024", "--speed-time", "30",
            "--output", str(tmp), url,
        ]
        started = time.monotonic()
        proc = subprocess.run(cmd, text=True, capture_output=True)
        elapsed = time.monotonic() - started
        size = tmp.stat().st_size if tmp.exists() else 0
        if proc.returncode == 0 and size > 0:
            tmp.replace(output)
            return
        last = f"curl_exit={proc.returncode} elapsed={elapsed:.1f}s partial_bytes={size} stderr={proc.stderr.strip()}"
        tmp.unlink(missing_ok=True)
        if attempt < retries:
            time.sleep(min(2 ** attempt, 8))
    raise RuntimeError(f"bounded official download exhausted {retries} attempts: {last}")


def download_bytes(url: str, work_dir: Path) -> bytes:
    target = work_dir / (hashlib.sha256(url.encode()).hexdigest() + ".payload")
    bounded_curl(url, target, retries=3, max_seconds=60)
    return target.read_bytes()


def xml_urls(payload: bytes, base_url: str) -> set[str]:
    root = ET.fromstring(payload)
    urls: set[str] = set()
    for el in root.iter():
        href = el.attrib.get("href") or el.attrib.get("src")
        if href:
            urls.add(urllib.parse.urljoin(base_url, href.strip()))
        text = (el.text or "").strip()
        if text.startswith(("http://", "https://")):
            urls.add(urllib.parse.urljoin(base_url, text))
    return urls


def crawl_feed(start_url: str, work_dir: Path, max_depth: int = 2) -> tuple[list[dict[str, Any]], set[str]]:
    queue = [(start_url, 0)]
    seen: set[str] = set()
    links: set[str] = set()
    rows: list[dict[str, Any]] = []
    while queue:
        url, depth = queue.pop(0)
        if url in seen or depth > max_depth:
            continue
        seen.add(url)
        payload = download_bytes(url, work_dir)
        found = xml_urls(payload, url)
        rows.append({"url": url, "depth": depth, "bytes": len(payload), "links": len(found)})
        links.update(found)
        if depth < max_depth:
            for child in sorted(found):
                parsed = urllib.parse.urlparse(child)
                low = child.lower()
                if (parsed.hostname or "").lower() == ALLOWED_HOST and (low.endswith(".xml") or "atomfeed" in low):
                    queue.append((child, depth + 1))
    return rows, links


def resolve_dtm_urls(links: set[str], tiles: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for tile in tiles:
        matches = sorted({
            u for u in links
            if u.lower().endswith(".zip")
            and tile in Path(urllib.parse.urlparse(u).path).name
            and "dtm" in Path(urllib.parse.urlparse(u).path).name.lower()
        })
        if len(matches) != 1:
            raise RuntimeError(f"expected one official DTM archive for {tile}, got {matches}")
        result[tile] = matches[0]
    return result


def derive_tile(e: float, n: float) -> str:
    return f"{int(math.floor(e / 1000.0)):03d}{int(math.floor(n / 1000.0)):03d}"


def prepare(source_root: Path, contract_path: Path, output_dir: Path, work_dir: Path, resolve_feed: bool) -> dict[str, Any]:
    contract = json.loads(contract_path.read_text(encoding="utf-8"))
    validate_hard_rules(contract)
    expected = contract["expected_source"]
    matches = list(source_root.rglob("source_materialization_index.json"))
    if len(matches) != 1:
        raise RuntimeError(f"expected one source_materialization_index.json, got {len(matches)}")
    index = matches[0]
    observed_index_sha = sha256_file(index)
    if observed_index_sha != expected["index_sha256"]:
        raise RuntimeError(f"C01 materialization index SHA drift: {observed_index_sha}")
    idx = json.loads(index.read_text(encoding="utf-8"))
    observed_owners = idx.get("owner_count", idx.get("selection", {}).get("owner_count", -1))
    if int(observed_owners) != int(expected["owners"]):
        raise RuntimeError("materialized owner count drift")
    cells = idx.get("cells")
    if not isinstance(cells, dict) or len(cells) != int(expected["spatial_cells"]):
        raise RuntimeError(f"spatial cell count drift: {len(cells) if isinstance(cells, dict) else 'invalid'}")

    owner_seen: set[str] = set()
    owner_ground: dict[str, set[tuple[float, float, float]]] = defaultdict(set)
    for cell_id in sorted(cells):
        rel = str(cells[cell_id]["relative_path"])
        p = index.parent / rel
        if not p.exists():
            p = source_root / rel
        if not p.exists():
            p = source_root / "cells" / cell_id / "source.ndjson"
        if not p.exists():
            raise RuntimeError(f"missing materialized cell payload: {cell_id} {rel}")
        for line in p.open("r", encoding="utf-8"):
            if not line.strip():
                continue
            rec = json.loads(line)
            bid = str(rec["building_id"])
            owner_seen.add(bid)
            if str(rec.get("face_type")) != "GROUNDSURFACE":
                continue
            for part in rec.get("parts", []):
                for vertex in part.get("vertices", []):
                    if len(vertex) < 3 or vertex[2] is None:
                        raise RuntimeError(f"owner {bid} GROUNDSURFACE missing XYZ")
                    owner_ground[bid].add((float(vertex[0]), float(vertex[1]), float(vertex[2])))

    if len(owner_seen) != int(expected["owners"]):
        raise RuntimeError(f"owner accounting drift: {len(owner_seen)}")
    missing = owner_seen - set(owner_ground)
    if missing:
        raise RuntimeError(f"owners missing GROUNDSURFACE: {sorted(missing, key=int)[:20]}")

    rows_by_tile: dict[str, list[tuple[str, float, float, float]]] = defaultdict(list)
    for bid in sorted(owner_ground, key=int):
        for e, n, z in sorted(owner_ground[bid]):
            rows_by_tile[derive_tile(e, n)].append((bid, e, n, z))
    samples = sum(len(v) for v in rows_by_tile.values())
    tiles = sorted(rows_by_tile)
    if samples != int(expected["unique_ground_samples"]):
        raise RuntimeError(f"ground sample count drift: {samples}")
    if len(tiles) != int(expected["dtm_tile_count"]):
        raise RuntimeError(f"DTM tile count drift: {len(tiles)}")
    if tiles != list(expected["dtm_tiles"]):
        raise RuntimeError("DTM tile list drift")

    output_dir.mkdir(parents=True, exist_ok=True)
    with (output_dir / "ground_samples.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["tile", "building_id", "easting", "northing", "source_ground_z"])
        for tile in tiles:
            for bid, e, n, z in rows_by_tile[tile]:
                w.writerow([tile, bid, f"{e:.9f}", f"{n:.9f}", f"{z:.9f}"])
    plan = {
        "schema": "grand-bruxelles-region-lod2-c01-dtm-sample-plan-v1",
        "campaign_id": contract["campaign_id"],
        "source_index_sha256": observed_index_sha,
        "owners": len(owner_seen),
        "owners_with_ground": len(owner_ground),
        "unique_ground_samples": samples,
        "dtm_tile_count": len(tiles),
        "dtm_tiles": [{"tile": t, "samples": len(rows_by_tile[t])} for t in tiles],
        "runtime_authorized": False,
        "final_world_y_authorized": False,
    }
    (output_dir / "dtm_sample_plan.json").write_text(json.dumps(plan, indent=2) + "\n", encoding="utf-8")
    if resolve_feed:
        feed_rows, links = crawl_feed(contract["dtm"]["atom_feed"], work_dir)
        urls = resolve_dtm_urls(links, tiles)
        resolved = {
            "schema": "grand-bruxelles-region-lod2-c01-dtm-source-resolution-v1",
            "dataset_id": contract["dtm"]["dataset_id"],
            "feed": contract["dtm"]["atom_feed"],
            "feed_pages": feed_rows,
            "tiles": [{"tile": t, "url": urls[t]} for t in tiles],
        }
        (output_dir / "dtm_sources.json").write_text(json.dumps(resolved, indent=2) + "\n", encoding="utf-8")
    print(f"C01_DTM_PREPARED: owners={len(owner_seen)} samples={samples} tiles={len(tiles)} runtime_authorized=false")
    return plan


def validate_raster(tile: str, tif: Path, expected_resolution: float):
    import rasterio  # type: ignore
    src = rasterio.open(tif)
    epsg = src.crs.to_epsg() if src.crs else None
    if epsg is not None and epsg != EXPECTED_EPSG:
        src.close(); raise RuntimeError(f"{tile}: unexpected CRS {epsg}")
    if src.width != 2000 or src.height != 2000 or src.count != 1:
        src.close(); raise RuntimeError(f"{tile}: unexpected raster shape {src.width}x{src.height} bands={src.count}")
    rx, ry = abs(float(src.transform.a)), abs(float(src.transform.e))
    if abs(rx - expected_resolution) > 1e-9 or abs(ry - expected_resolution) > 1e-9:
        src.close(); raise RuntimeError(f"{tile}: resolution drift {rx},{ry}")
    e0, n0 = int(tile[:3]) * 1000.0, int(tile[3:]) * 1000.0
    expected_bounds = (e0, n0, e0 + 1000.0, n0 + 1000.0)
    actual = (float(src.bounds.left), float(src.bounds.bottom), float(src.bounds.right), float(src.bounds.top))
    for got, want in zip(actual, expected_bounds):
        if abs(got - want) > expected_resolution:
            src.close(); raise RuntimeError(f"{tile}: bounds drift {actual} vs {expected_bounds}")
    return src, {
        "embedded_epsg": epsg, "bounds": actual, "resolution": [rx, ry],
        "width": src.width, "height": src.height, "dtype": src.dtypes[0], "nodata": src.nodata,
    }


def sample_tile(tile: str, samples_path: Path, sources_path: Path, contract_path: Path, output_dir: Path, work_dir: Path) -> dict[str, Any]:
    contract = json.loads(contract_path.read_text(encoding="utf-8")); validate_hard_rules(contract)
    sources = json.loads(sources_path.read_text(encoding="utf-8"))
    source_map = {str(r["tile"]): str(r["url"]) for r in sources["tiles"]}
    if tile not in source_map:
        raise RuntimeError(f"tile {tile} absent from resolved DTM sources")
    selected: list[dict[str, str]] = []
    with samples_path.open(newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            if row["tile"] == tile:
                selected.append(row)
    if not selected:
        raise RuntimeError(f"tile {tile} has no C01 ground samples")

    archive = work_dir / f"dtm-{tile}.zip"
    bounded_curl(source_map[tile], archive, retries=4, max_seconds=240)
    archive_sha = sha256_file(archive)
    extract = work_dir / f"dtm-{tile}"
    members = safe_extract_zip(archive, extract)
    tiffs = sorted(p for p in members if p.suffix.lower() in {".tif", ".tiff"})
    if len(tiffs) != 1:
        raise RuntimeError(f"{tile}: expected one TIFF, got {[p.name for p in tiffs]}")
    tif = tiffs[0]
    src, meta = validate_raster(tile, tif, float(contract["dtm"]["expected_resolution_m"]))
    output_dir.mkdir(parents=True, exist_ok=True)
    residual_path = output_dir / f"residuals_{tile}.csv"
    vals: list[float] = []
    with residual_path.open("w", newline="", encoding="utf-8") as f:
        fields = ["tile", "building_id", "easting", "northing", "source_ground_z", "dtm_z", "residual_source_minus_dtm_m"]
        w = csv.DictWriter(f, fieldnames=fields); w.writeheader()
        for row in selected:
            e, n, source_z = float(row["easting"]), float(row["northing"]), float(row["source_ground_z"])
            b = src.bounds
            if not (float(b.left) <= e < float(b.right) and float(b.bottom) < n <= float(b.top)):
                src.close(); raise RuntimeError(f"{tile}: sample outside validated raster: {e},{n}")
            value = next(src.sample([(e, n)], masked=True))[0]
            if hasattr(value, "mask") and bool(value.mask):
                src.close(); raise RuntimeError(f"{tile}: nodata at {e},{n}")
            dtm_z = float(value)
            if not math.isfinite(dtm_z) or (src.nodata is not None and dtm_z == float(src.nodata)):
                src.close(); raise RuntimeError(f"{tile}: invalid DTM value {dtm_z} at {e},{n}")
            residual = source_z - dtm_z; vals.append(residual)
            w.writerow({**row, "dtm_z": f"{dtm_z:.9f}", "residual_source_minus_dtm_m": f"{residual:.9f}"})
    src.close()
    evidence = {
        "schema": "grand-bruxelles-region-lod2-c01-dtm-tile-evidence-v1",
        "tile": tile, "url": source_map[tile], "archive_sha256": archive_sha,
        "archive_bytes": archive.stat().st_size, "raster_filename": tif.name,
        "raster_sha256": sha256_file(tif), "samples": len(vals),
        "source_minus_dtm_min_m": min(vals), "source_minus_dtm_max_m": max(vals),
        "raster": meta, "runtime_authorized": False, "final_world_y_authorized": False,
    }
    (output_dir / f"dtm_evidence_{tile}.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
    print(f"C01_DTM_TILE_OK: tile={tile} samples={len(vals)} archive_sha256={archive_sha}")
    return evidence


def evaluate_q(owner_residuals: dict[str, list[float]], q: float, deadband: float) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    all_post: list[float] = []; shifts: list[float] = []; owner_max: list[float] = []; rows: list[dict[str, Any]] = []
    for bid in sorted(owner_residuals, key=int):
        residuals = owner_residuals[bid]
        shift = percentile([-r for r in residuals], q)
        post = [r + shift for r in residuals]
        abs_post = [abs(v) for v in post]
        shifts.append(shift); all_post.extend(post); owner_max.append(max(abs_post))
        rows.append({
            "building_id": bid, "sample_count": len(residuals), "rigid_shift_m": shift,
            "post_residual_median_m": statistics.median(post), "post_residual_min_m": min(post),
            "post_residual_max_m": max(post), "post_max_abs_residual_m": max(abs_post),
        })
    aa = [abs(v) for v in all_post]
    summary = {
        "quantile": q, "owners": len(owner_residuals), "samples": len(all_post),
        "shift_m": {"min": min(shifts), "median": statistics.median(shifts), "max": max(shifts), "p90": percentile(shifts, .9), "p95": percentile(shifts, .95)},
        "post_residual_m": {
            "mean": statistics.fmean(all_post), "median": statistics.median(all_post), "min": min(all_post), "max": max(all_post),
            "abs_p50": percentile(aa, .5), "abs_p90": percentile(aa, .9), "abs_p95": percentile(aa, .95), "abs_p99": percentile(aa, .99), "abs_max": max(aa),
            "within_0_25m": sum(v <= .25 for v in aa), "within_0_50m": sum(v <= .5 for v in aa), "within_1m": sum(v <= 1.0 for v in aa),
            "positive_over_deadband": sum(v > deadband for v in all_post), "negative_below_deadband": sum(v < -deadband for v in all_post),
            "within_deadband": sum(abs(v) <= deadband for v in all_post),
        },
        "owner_max_abs_residual_m": {"p50": percentile(owner_max, .5), "p90": percentile(owner_max, .9), "p95": percentile(owner_max, .95), "p99": percentile(owner_max, .99), "max": max(owner_max)},
    }
    return summary, rows


def aggregate(input_dir: Path, contract_path: Path, output_dir: Path) -> dict[str, Any]:
    contract = json.loads(contract_path.read_text(encoding="utf-8")); validate_hard_rules(contract)
    expected = contract["expected_source"]
    residual_files = sorted(input_dir.rglob("residuals_*.csv"))
    evidence_files = sorted(input_dir.rglob("dtm_evidence_*.json"))
    if len(residual_files) != int(expected["dtm_tile_count"]) or len(evidence_files) != int(expected["dtm_tile_count"]):
        raise RuntimeError(f"expected {expected['dtm_tile_count']} residual/evidence files, got {len(residual_files)}/{len(evidence_files)}")
    evidence = [json.loads(p.read_text(encoding="utf-8")) for p in evidence_files]
    tiles = sorted(str(r["tile"]) for r in evidence)
    if tiles != list(expected["dtm_tiles"]):
        raise RuntimeError("aggregate DTM tile set drift")

    owner_residuals: dict[str, list[float]] = defaultdict(list)
    sample_count = 0
    seen_samples: set[tuple[str, str, str]] = set()
    for p in residual_files:
        with p.open(newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                bid = str(row["building_id"])
                key = (bid, row["easting"], row["northing"])
                if key in seen_samples:
                    raise RuntimeError(f"duplicate ground sample across DTM tiles: {key}")
                seen_samples.add(key)
                owner_residuals[bid].append(float(row["residual_source_minus_dtm_m"])); sample_count += 1
    if len(owner_residuals) != int(expected["owners"]):
        raise RuntimeError(f"owners with residuals drift: {len(owner_residuals)}")
    if sample_count != int(expected["unique_ground_samples"]):
        raise RuntimeError(f"aggregate sample count drift: {sample_count}")

    baseline = [abs(v) for vals in owner_residuals.values() for v in vals]
    baseline_p95 = percentile(baseline, .95)
    policy = contract["policy"]; deadband = float(policy["float_burial_deadband_m"])
    candidates: list[dict[str, Any]] = []; candidate_rows: dict[float, list[dict[str, Any]]] = {}
    for raw in policy["candidate_quantiles"]:
        q = float(raw); summary, rows = evaluate_q(owner_residuals, q, deadband)
        candidates.append(summary); candidate_rows[q] = rows
    selected = min(candidates, key=lambda r: (float(r["post_residual_m"]["abs_p95"]), float(r["owner_max_abs_residual_m"]["p95"]), abs(float(r["quantile"]) - .5)))
    q = float(selected["quantile"])
    if float(selected["post_residual_m"]["abs_p95"]) >= baseline_p95:
        raise RuntimeError("rigid owner anchor does not improve baseline p95")

    output_dir.mkdir(parents=True, exist_ok=True)
    rows = candidate_rows[q]
    fields = ["building_id", "sample_count", "rigid_shift_m", "post_residual_median_m", "post_residual_min_m", "post_residual_max_m", "post_max_abs_residual_m"]
    with (output_dir / "rigid_anchor_selected_per_owner.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fields); w.writeheader(); w.writerows(rows)
    owner_map = {r["building_id"]: {"rigid_shift_m": r["rigid_shift_m"], "sample_count": r["sample_count"], "post_max_abs_residual_m": r["post_max_abs_residual_m"]} for r in rows}
    (output_dir / "rigid_anchor_selected_by_owner.json").write_text(json.dumps(owner_map, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    locks = {r["tile"]: {"url": r["url"], "archive_sha256": r["archive_sha256"], "raster_sha256": r["raster_sha256"], "samples": r["samples"]} for r in evidence}
    (output_dir / "dtm_tile_locks.json").write_text(json.dumps(locks, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    report = {
        "schema": "grand-bruxelles-region-lod2-c01-dtm-rigid-anchor-measurement-v1",
        "campaign_id": contract["campaign_id"], "production_base_sha": contract["production_base_sha"],
        "input": {"owners": len(owner_residuals), "unique_ground_samples": sample_count, "dtm_tile_count": len(evidence), "baseline_vertex_abs_p95_m": baseline_p95},
        "horizontal_transform": contract["horizontal_transform"], "policy": policy, "candidates": candidates,
        "selected_numerical_candidate": {"quantile": q, "owner_count": len(rows), "shift_m": selected["shift_m"], "post_residual_m": selected["post_residual_m"], "owner_max_abs_residual_m": selected["owner_max_abs_residual_m"], "runtime_authorized": False, "final_world_y_authorized": False},
        "runtime_authorized": False, "runtime_mount_authorized": False, "collision_authorized": False,
        "final_world_y_authorized": False, "terrain_runtime_authorized": False, "source_geometry_modified": False,
        "jouable_promotion_authorized": False, "artifact_only": True,
    }
    (output_dir / "dtm_rigid_anchor_measurement.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"C01_DTM_RIGID_ANCHOR_MEASURED: q={q:.2f} owners={len(rows)} samples={sample_count} baseline_p95={baseline_p95:.6f} post_p95={selected['post_residual_m']['abs_p95']:.6f} runtime_authorized=false")
    return report


def main() -> int:
    ap = argparse.ArgumentParser(); sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("prepare"); p.add_argument("--source-root", type=Path, required=True); p.add_argument("--contract", type=Path, required=True); p.add_argument("--output-dir", type=Path, required=True); p.add_argument("--work-dir", type=Path, required=True); p.add_argument("--resolve-feed", action="store_true")
    p = sub.add_parser("sample-tile"); p.add_argument("--tile", required=True); p.add_argument("--samples", type=Path, required=True); p.add_argument("--sources", type=Path, required=True); p.add_argument("--contract", type=Path, required=True); p.add_argument("--output-dir", type=Path, required=True); p.add_argument("--work-dir", type=Path, required=True)
    p = sub.add_parser("aggregate"); p.add_argument("--input-dir", type=Path, required=True); p.add_argument("--contract", type=Path, required=True); p.add_argument("--output-dir", type=Path, required=True)
    args = ap.parse_args()
    try:
        if args.cmd == "prepare":
            prepare(args.source_root.resolve(), args.contract.resolve(), args.output_dir.resolve(), args.work_dir.resolve(), args.resolve_feed)
        elif args.cmd == "sample-tile":
            sample_tile(args.tile, args.samples.resolve(), args.sources.resolve(), args.contract.resolve(), args.output_dir.resolve(), args.work_dir.resolve())
        else:
            aggregate(args.input_dir.resolve(), args.contract.resolve(), args.output_dir.resolve())
    except Exception as exc:
        print(f"C01_DTM_RIGID_ANCHOR_ERROR: {exc}", flush=True); return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
