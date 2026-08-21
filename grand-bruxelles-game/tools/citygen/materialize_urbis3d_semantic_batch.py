#!/usr/bin/env python3
"""Materialize independent UrbIS3D semantic-height evidence for a CityGen cell batch.

The package plan is produced by select_cell_urbis3d_packages.py. Official packages
are downloaded once per municipality, safely extracted, spatially filtered to each
500 m cell, and merged across municipality boundaries. The output is evidence only:
runtime approval is always false and any ambiguous cross-package duplication fails
closed for that cell.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
import shutil
import statistics
import urllib.parse
import urllib.request
import zipfile
from collections import Counter
from pathlib import Path
from typing import Any

PLAN_FORMAT = "grand-bruxelles-citygen-urbis3d-package-plan-v1"
CRS = "EPSG:31370"
OUTPUT_NAME = "urbis3d_semantic_height_evidence.json"
USER_AGENT = "GrandBruxellesGame/1.0 autonomous-urbis3d (+github.com/Chatnoir01/Chatnoir01)"
ALLOWED_HOSTS = (
    "datastore.brussels",
    "urbisdownload.datastore.brussels",
    "geoservices-urbis.irisnet.be",
    "gis.urban.brussels",
    "urban.brussels",
)
MAX_ARCHIVE_MEMBERS = 5000
MAX_DECLARED_UNCOMPRESSED_BYTES = 8 * 1024 * 1024 * 1024


def _read(path: Path) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(payload, dict):
        raise ValueError(f"expected JSON object: {path}")
    return payload


def _write(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _allowed_url(url: str) -> bool:
    parsed = urllib.parse.urlparse(url)
    host = (parsed.hostname or "").casefold()
    return parsed.scheme == "https" and any(host == allowed or host.endswith("." + allowed) for allowed in ALLOWED_HOSTS)


def _download(url: str, destination: Path) -> dict[str, Any]:
    if not _allowed_url(url):
        raise ValueError(f"UrbIS3D package URL is not an approved official host: {url}")
    destination.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "*/*"})
    digest = hashlib.sha256()
    total = 0
    with urllib.request.urlopen(request, timeout=300) as response, destination.open("wb") as handle:
        final_url = response.geturl()
        if not _allowed_url(final_url):
            raise ValueError(f"UrbIS3D redirect left approved official hosts: {final_url}")
        while True:
            chunk = response.read(1024 * 1024)
            if not chunk:
                break
            total += len(chunk)
            digest.update(chunk)
            handle.write(chunk)
    if total == 0:
        raise ValueError(f"empty UrbIS3D distribution: {url}")
    return {"url": url, "bytes": total, "sha256": digest.hexdigest()}


def _safe_extract(package: Path, destination: Path) -> list[Path]:
    destination.mkdir(parents=True, exist_ok=True)
    prefix = package.read_bytes()[:16]
    if prefix == b"SQLite format 3\x00":
        target = destination / "selected.gpkg"
        shutil.copy2(package, target)
        return [target]
    if not zipfile.is_zipfile(package):
        raise ValueError(f"unsupported UrbIS3D distribution container: {package}")
    with zipfile.ZipFile(package) as archive:
        members = archive.infolist()
        if len(members) > MAX_ARCHIVE_MEMBERS:
            raise ValueError("UrbIS3D ZIP contains an unreasonable number of members")
        declared = sum(max(0, int(member.file_size)) for member in members)
        if declared > MAX_DECLARED_UNCOMPRESSED_BYTES:
            raise ValueError("UrbIS3D ZIP declared uncompressed size exceeds safety budget")
        base = destination.resolve()
        for member in members:
            target = (destination / member.filename).resolve()
            if target != base and base not in target.parents:
                raise ValueError(f"unsafe UrbIS3D ZIP member path: {member.filename}")
        archive.extractall(destination)
    packages = sorted(path for path in destination.rglob("*.gpkg") if path.is_file())
    if not packages:
        raise ValueError("official UrbIS3D distribution contains no GeoPackage")
    return packages


def _load_matcher():
    module_path = Path(__file__).resolve().parents[1] / "match_urbis3d_semantic_heights.py"
    spec = importlib.util.spec_from_file_location("match_urbis3d_semantic_heights", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import semantic matcher: {module_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _same_match(left: dict[str, Any], right: dict[str, Any]) -> bool:
    if left.get("matched_inspire_id") != right.get("matched_inspire_id") or left.get("status") != right.get("status"):
        return False
    for key in ("semantic_height_m", "match_score", "match_margin"):
        a, b = left.get(key), right.get(key)
        if a is None or b is None:
            if a != b:
                return False
        elif not math.isclose(float(a), float(b), abs_tol=1e-6):
            return False
    return True


def _merge_evidence(
    *,
    cell_id: str,
    bbox: list[float],
    municipalities: list[str],
    building_count: int,
    pieces: list[dict[str, Any]],
    package_provenance: list[dict[str, Any]],
    matcher,
) -> dict[str, Any]:
    by_solid: dict[str, dict[str, Any]] = {}
    for piece in pieces:
        if piece.get("cell") != cell_id or piece.get("policy", {}).get("runtime_approval") is not False:
            raise ValueError("per-package semantic evidence identity/safety drift")
        for match in piece.get("matches") or []:
            solid = str(match.get("busolid_id") or "")
            if not solid:
                raise ValueError("semantic match is missing BUSOLID identity")
            previous = by_solid.get(solid)
            if previous is None:
                by_solid[solid] = match
            elif not _same_match(previous, match):
                raise ValueError(f"cross-package semantic ambiguity for BUSOLID {solid}")

    matches = [by_solid[key] for key in sorted(by_solid)]
    counters: Counter[str] = Counter(str(match.get("status") or "unknown") for match in matches)
    heights = [
        float(match["semantic_height_m"])
        for match in matches
        if match.get("status") == "matched_semantic_evidence" and match.get("semantic_height_m") is not None
    ]
    return {
        "schema": matcher.SCHEMA,
        "cell": cell_id,
        "municipality": ",".join(municipalities),
        "municipalities": municipalities,
        "bbox_epsg31370": bbox,
        "policy": {
            "crs": CRS,
            "match_basis": "BUSOLID_ID GROUNDSURFACE 2D overlap against UrbIS 2D building footprint",
            "height_basis": "median ROOFSURFACE Z minus median GROUNDSURFACE Z",
            "min_match_score": matcher.MIN_MATCH_SCORE,
            "min_runner_up_margin": matcher.MIN_RUNNER_UP_MARGIN,
            "plausible_height_range_m": [matcher.MIN_HEIGHT_M, matcher.MAX_HEIGHT_M],
            "dsm_dtm_comparison_performed": False,
            "runtime_approval": False,
            "multi_municipality_merge": "dedupe identical BUSOLID evidence; conflicting duplicates fail closed",
        },
        "counts": {
            "urbis_2d_buildings": building_count,
            "building_solids_in_bbox": len(matches),
            **dict(sorted(counters.items())),
        },
        "semantic_height_summary_m": {
            "count": len(heights),
            "min": min(heights) if heights else None,
            "median": statistics.median(heights) if heights else None,
            "p75": matcher.percentile(heights, 0.75),
            "max": max(heights) if heights else None,
        },
        "source_packages": package_provenance,
        "matches": matches,
    }


def materialize(plan_path: Path, source_root: Path, cache_root: Path, report_path: Path) -> dict[str, Any]:
    plan = _read(plan_path)
    if plan.get("format") != PLAN_FORMAT or plan.get("crs") != CRS:
        raise ValueError("unsupported UrbIS3D package plan or CRS")
    policy = plan.get("policy") or {}
    if policy.get("runtime_authorized") is not False or policy.get("runtime_promotion_allowed") is not False:
        raise ValueError("UrbIS3D package plan must remain runtime-forbidden")

    packages_by_nis: dict[str, dict[str, Any]] = {}
    package_roots: dict[str, Path] = {}
    for package in plan.get("packages") or []:
        if not isinstance(package, dict):
            raise ValueError("invalid UrbIS3D package plan row")
        nis = str(package.get("nis_code") or "")
        url = str(package.get("url") or "")
        if not nis or nis in packages_by_nis:
            raise ValueError("duplicate/invalid UrbIS3D municipality package")
        packages_by_nis[nis] = package
        package_dir = cache_root / nis
        binary = package_dir / "distribution.bin"
        extracted = package_dir / "extracted"
        if extracted.exists():
            shutil.rmtree(extracted)
        download = _download(url, binary)
        gpkg = _safe_extract(binary, extracted)
        package["download"] = download
        package["gpkg_count"] = len(gpkg)
        package_roots[nis] = extracted

    matcher = _load_matcher()
    matcher.ogr.UseExceptions()
    successes: list[str] = []
    failures: list[dict[str, str]] = []
    for cell in plan.get("cells") or []:
        cell_id = str((cell or {}).get("cell_id") or "")
        try:
            bbox = [float(value) for value in cell.get("bbox")]
            municipalities = [str(value) for value in cell.get("municipalities") or []]
            nis_codes = [str(value) for value in cell.get("nis_codes") or []]
            if len(municipalities) != len(nis_codes) or not municipalities:
                raise ValueError("cell municipality/package ownership is invalid")
            cell_dir = source_root / cell_id
            buildings_path = cell_dir / "raw" / "buildings.geojson"
            if not buildings_path.is_file():
                raise ValueError("authoritative UrbIS Buildings payload is missing")
            buildings = matcher.load_buildings(buildings_path, tuple(bbox))
            pieces: list[dict[str, Any]] = []
            provenance: list[dict[str, Any]] = []
            for municipality, nis in zip(municipalities, nis_codes):
                root = package_roots.get(nis)
                package = packages_by_nis.get(nis)
                if root is None or package is None:
                    raise ValueError(f"selected municipality package is unavailable: {municipality}/{nis}")
                dataset, layer, gpkg_path = matcher.find_buildingfaces(root)
                solids = matcher.collect_solids(layer, tuple(bbox))
                evidence = matcher.build_evidence(
                    buildings,
                    solids,
                    tuple(bbox),
                    cell_id=cell_id,
                    municipality=municipality,
                )
                dataset = None
                pieces.append(evidence)
                provenance.append({
                    "municipality": municipality,
                    "nis_code": nis,
                    "url": package["url"],
                    "embedded_date": package.get("embedded_date"),
                    "sha256": package["download"]["sha256"],
                    "gpkg": gpkg_path.name,
                })
            merged = _merge_evidence(
                cell_id=cell_id,
                bbox=bbox,
                municipalities=municipalities,
                building_count=len(buildings),
                pieces=pieces,
                package_provenance=provenance,
                matcher=matcher,
            )
            _write(cell_dir / OUTPUT_NAME, merged)
            successes.append(cell_id)
            print(
                "CITYGEN_URBIS3D_SEMANTIC_CELL_OK",
                cell_id,
                f"solids={merged['counts']['building_solids_in_bbox']}",
                f"semantic={merged['counts'].get('matched_semantic_evidence', 0)}",
                "runtime_approved=false",
            )
        except Exception as exc:
            output = source_root / cell_id / OUTPUT_NAME
            output.unlink(missing_ok=True)
            failures.append({"cell_id": cell_id, "error": str(exc)})
            print("CITYGEN_URBIS3D_SEMANTIC_CELL_PENDING", cell_id, str(exc))

    report = {
        "format": "grand-bruxelles-citygen-urbis3d-semantic-batch-report-v1",
        "planned_cells": len(plan.get("cells") or []),
        "success_cells": successes,
        "failures": failures,
        "package_count": len(packages_by_nis),
        "runtime_authorized": False,
        "runtime_promotion_allowed": False,
    }
    _write(report_path, report)
    if plan.get("cells") and not successes:
        raise RuntimeError("all selected UrbIS3D semantic cells failed; probable systemic source/tooling failure")
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--plan", type=Path, required=True)
    parser.add_argument("--source-root", type=Path, required=True)
    parser.add_argument("--cache-root", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = materialize(args.plan, args.source_root, args.cache_root, args.report)
    except Exception as exc:
        print(f"CITYGEN_URBIS3D_SEMANTIC_BATCH_ERROR: {exc}")
        return 1
    print(
        "CITYGEN_URBIS3D_SEMANTIC_BATCH_OK",
        f"success={len(report['success_cells'])}",
        f"failed={len(report['failures'])}",
        "runtime_authorized=false",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
