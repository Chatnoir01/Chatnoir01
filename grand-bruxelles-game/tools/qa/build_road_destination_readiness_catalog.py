#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from typing import Any

HEX64 = re.compile(r"^[0-9a-f]{64}$")


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def sha256_json(payload: Any) -> str:
    raw = json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(raw)


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise RuntimeError(f"expected JSON object: {path}")
    return data


def require_hex64(value: object, label: str) -> str:
    text = str(value or "").lower()
    if not HEX64.fullmatch(text):
        raise RuntimeError(f"invalid {label}: {value!r}")
    return text


def require_false(mapping: dict[str, Any], keys: list[str], label: str) -> None:
    for key in keys:
        if mapping.get(key) is not False:
            raise RuntimeError(f"{label} authorization drift: {key}={mapping.get(key)!r}")


def canonical_repo_path(root: Path, raw: str, prefix: str) -> Path:
    path = Path(raw)
    if path.is_absolute() or ".." in path.parts:
        raise RuntimeError(f"unsafe repository path: {raw}")
    normalized = path.as_posix()
    if not normalized.startswith(prefix):
        raise RuntimeError(f"non-canonical repository path: {raw}")
    resolved = (root / path).resolve()
    root_resolved = root.resolve()
    try:
        resolved.relative_to(root_resolved)
    except ValueError as exc:
        raise RuntimeError(f"repository path escapes root: {raw}") from exc
    return resolved


def municipality_evidence(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    provenance = manifest.get("provenance") or {}
    intersections = provenance.get("municipality_intersections")
    if intersections is not None:
        if not isinstance(intersections, list) or not intersections:
            raise RuntimeError("municipality_intersections must be a non-empty list")
        rows = []
        for item in intersections:
            nis = str(item.get("niscode") or "")
            inspire = str(item.get("inspire_id") or "")
            ratio = float(item.get("coverage_ratio"))
            if not nis or not inspire or not (0.0 < ratio <= 1.0):
                raise RuntimeError(f"invalid municipality intersection: {item}")
            rows.append({"niscode": nis, "inspire_id": inspire, "coverage_ratio": ratio})
        rows.sort(key=lambda r: (r["niscode"], r["inspire_id"]))
        total = sum(r["coverage_ratio"] for r in rows)
        if abs(total - 1.0) > 1e-9:
            raise RuntimeError(f"municipality boundary coverage drift: {total}")
        return rows

    nis = str(provenance.get("municipality_niscode") or "")
    inspire = str(provenance.get("municipality_id") or "")
    ratio = float(provenance.get("municipality_coverage_ratio", 0.0))
    if not nis or not inspire or abs(ratio - 1.0) > 1e-9:
        raise RuntimeError("canonical cell lacks deterministic municipality provenance")
    return [{"niscode": nis, "inspire_id": inspire, "coverage_ratio": ratio}]


def point_contract(points: object) -> tuple[int, list[float], str]:
    if not isinstance(points, list) or len(points) < 2:
        raise RuntimeError("road source points must contain at least two coordinates")
    normalized: list[list[float]] = []
    for point in points:
        if not isinstance(point, list) or len(point) < 2:
            raise RuntimeError(f"invalid road point: {point!r}")
        normalized.append([float(point[0]), float(point[1])])
    xs = [p[0] for p in normalized]
    ys = [p[1] for p in normalized]
    bbox = [min(xs), min(ys), max(xs), max(ys)]
    return len(normalized), bbox, sha256_json(normalized)


def build_catalog(repo_root: Path, road_index_path: Path, cell_index_path: Path, crosswalk_path: Path) -> dict[str, Any]:
    root = repo_root.resolve()
    road_index = load_json(road_index_path)
    cell_index = load_json(cell_index_path)
    crosswalk = load_json(crosswalk_path)

    if road_index.get("format") != "grand-bruxelles-road-runtime-index-v1":
        raise RuntimeError("road runtime index format drift")
    if road_index.get("source_lookup_only") is not True:
        raise RuntimeError("road runtime index must remain source_lookup_only")
    auth = road_index.get("authorization") or {}
    if auth.get("source_lookup_only") is not True:
        raise RuntimeError("road runtime index source lookup authorization drift")
    require_false(auth, ["render_authorized", "collision_authorized", "runtime_mount_authorized", "safe_spawn_authorized", "jouable_authorized"], "road runtime index")

    if cell_index.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise RuntimeError("registered cell index schema drift")
    require_false(cell_index, ["runtime_directory_scan_authorized", "road_crosswalk_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"], "registered cell index")
    cell_semantic = require_hex64(cell_index.get("semantic_sha256"), "registered cell semantic sha")

    if crosswalk.get("schema") != "grand-bruxelles-road-registered-cell-crosswalk-v1":
        raise RuntimeError("road-cell crosswalk schema drift")
    require_false(crosswalk, ["road_cell_mapping_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"], "road-cell crosswalk")
    crosswalk_semantic = require_hex64(crosswalk.get("semantic_sha256"), "road-cell crosswalk semantic sha")
    if crosswalk.get("registered_cell_index_semantic_sha256") != cell_semantic:
        raise RuntimeError("crosswalk registered-cell identity drift")

    cells: dict[str, dict[str, Any]] = {}
    for entry in cell_index.get("entries") or []:
        cell_id = str(entry.get("cell_id") or "")
        if not cell_id or cell_id in cells:
            raise RuntimeError(f"invalid/duplicate registered cell: {cell_id!r}")
        if entry.get("crs") != "EPSG:31370" or entry.get("maturity_state") != "data_ready" or entry.get("evidence_only") is not True:
            raise RuntimeError(f"registered cell not evidence-only/data-ready EPSG:31370: {cell_id}")
        require_false(entry, ["runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"], f"registered cell {cell_id}")
        manifest_rel = str(entry.get("manifest_path") or "")
        manifest_path = canonical_repo_path(root, manifest_rel, "data/cell_manifests/")
        if not manifest_path.is_file():
            raise RuntimeError(f"missing canonical cell manifest: {manifest_rel}")
        expected_manifest_sha = require_hex64(entry.get("manifest_sha256"), f"manifest sha {cell_id}")
        if sha256_bytes(manifest_path.read_bytes()) != expected_manifest_sha:
            raise RuntimeError(f"registered cell manifest bytes drift: {cell_id}")
        manifest = load_json(manifest_path)
        if manifest.get("cell_id") != cell_id or manifest.get("crs") != "EPSG:31370" or manifest.get("bbox") != entry.get("bbox"):
            raise RuntimeError(f"registered cell manifest identity drift: {cell_id}")
        maturity = manifest.get("maturity") or {}
        if maturity.get("state") != "data_ready":
            raise RuntimeError(f"registered cell maturity drift: {cell_id}")
        gates = maturity.get("gates") or {}
        if not gates or any(value is not False for value in gates.values()):
            raise RuntimeError(f"registered cell maturity gate opened: {cell_id}")
        cells[cell_id] = {
            "entry": entry,
            "manifest": manifest,
            "municipalities": municipality_evidence(manifest),
        }

    source_roads: dict[int, dict[str, Any]] = {}
    road_sources: dict[int, dict[str, str]] = {}
    for document in road_index.get("documents") or []:
        rel = str(document.get("path") or "")
        source_path = canonical_repo_path(root, rel, "data/osm/")
        if not source_path.is_file():
            raise RuntimeError(f"missing road source document: {rel}")
        expected_sha = require_hex64(document.get("sha256"), f"road source sha {rel}")
        if sha256_bytes(source_path.read_bytes()) != expected_sha:
            raise RuntimeError(f"road source bytes drift: {rel}")
        source = load_json(source_path)
        if source.get("license") != "ODbL-1.0" or "OpenStreetMap" not in str(source.get("source") or ""):
            raise RuntimeError(f"road source provenance/license drift: {rel}")
        road_by_id = {int(r["osm_id"]): r for r in source.get("roads") or []}
        indexed_ids = [int(value) for value in document.get("road_ids") or []]
        if len(indexed_ids) != len(set(indexed_ids)):
            raise RuntimeError(f"duplicate road ids in runtime descriptor: {rel}")
        for road_id in indexed_ids:
            road = road_by_id.get(road_id)
            if road is None:
                raise RuntimeError(f"runtime-indexed road missing from source: {road_id}")
            if road.get("drivable") is not True:
                raise RuntimeError(f"runtime-indexed road is not drivable: {road_id}")
            if road_id in source_roads:
                raise RuntimeError(f"road appears in multiple runtime documents: {road_id}")
            source_roads[road_id] = road
            road_sources[road_id] = {"path": rel, "sha256": expected_sha, "license": "ODbL-1.0", "provider": str(source.get("source"))}

    rows = crosswalk.get("rows") or []
    if int(crosswalk.get("mapped_road_count", -1)) != len(rows):
        raise RuntimeError("crosswalk mapped road accounting drift")
    destinations: list[dict[str, Any]] = []
    seen_roads: set[int] = set()
    for mapping in rows:
        road_id = int(mapping.get("road_osm_id"))
        if road_id in seen_roads:
            raise RuntimeError(f"duplicate road mapping: {road_id}")
        seen_roads.add(road_id)
        if mapping.get("mapping_evidence_only") is not True:
            raise RuntimeError(f"road mapping lost evidence-only rail: {road_id}")
        require_false(mapping, ["road_cell_mapping_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"], f"road mapping {road_id}")
        road = source_roads.get(road_id)
        if road is None:
            raise RuntimeError(f"mapped road missing from runtime source contract: {road_id}")
        cell_id = str(mapping.get("cell_id") or "")
        cell = cells.get(cell_id)
        if cell is None:
            raise RuntimeError(f"mapped cell is not registered: {cell_id}")
        entry = cell["entry"]
        grid = str(mapping.get("grid_cell_id") or "")
        bbox = [float(v) for v in entry.get("bbox") or []]
        if len(bbox) != 4:
            raise RuntimeError(f"invalid registered cell bbox: {cell_id}")
        points_count, points_bbox, points_sha = point_contract(road.get("points"))
        municipalities = cell["municipalities"]
        destinations.append({
            "destination_id": f"road-{road_id}",
            "road_osm_id": road_id,
            "road_name": str(road.get("name") or ""),
            "road_class": str(road.get("class") or ""),
            "road_width_m": float(road.get("width", 0.0)),
            "source_path": road_sources[road_id]["path"],
            "source_sha256": road_sources[road_id]["sha256"],
            "source_provider": road_sources[road_id]["provider"],
            "source_license": road_sources[road_id]["license"],
            "source_local_point_count": points_count,
            "source_local_bbox": points_bbox,
            "source_points_sha256": points_sha,
            "cell_id": cell_id,
            "grid_cell_id": grid,
            "cell_bbox": bbox,
            "cell_crs": "EPSG:31370",
            "cell_manifest_path": str(entry["manifest_path"]),
            "cell_manifest_sha256": str(entry["manifest_sha256"]),
            "municipality_niscodes": [m["niscode"] for m in municipalities],
            "municipalities": municipalities,
            "readiness": "REGISTERED_NOT_RENDERED",
            "render_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        })

    destinations.sort(key=lambda item: item["road_osm_id"])
    catalog: dict[str, Any] = {
        "schema": "grand-bruxelles-road-destination-readiness-catalog-v1",
        "status": "SOURCE_BACKED_REGISTERED_NOT_RENDERED",
        "destination_count": len(destinations),
        "mapped_cell_count": len({d["cell_id"] for d in destinations}),
        "source_document_count": len(road_index.get("documents") or []),
        "road_runtime_catalog_sha256": require_hex64(road_index.get("catalog_sha256"), "road runtime catalog sha"),
        "registered_cell_index_semantic_sha256": cell_semantic,
        "road_cell_crosswalk_semantic_sha256": crosswalk_semantic,
        "authorization": {
            "road_cell_mapping_authorized": False,
            "runtime_directory_scan_authorized": False,
            "runtime_mount_authorized": False,
            "render_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        },
        "destinations": destinations,
    }
    semantic_payload = dict(catalog)
    catalog["semantic_sha256"] = sha256_json(semantic_payload)
    return catalog


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, required=True)
    parser.add_argument("--road-index", type=Path, required=True)
    parser.add_argument("--cell-index", type=Path, required=True)
    parser.add_argument("--crosswalk", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    catalog = build_catalog(args.repo_root, args.road_index, args.cell_index, args.crosswalk)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"ROAD_DESTINATION_READINESS_CATALOG_OK destinations={catalog['destination_count']} semantic={catalog['semantic_sha256']} runtime=false")


if __name__ == "__main__":
    main()
