#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

ROAD_INDEX_FORMAT = "grand-bruxelles-road-runtime-index-v1"
CELL_INDEX_SCHEMA = "grand-bruxelles-registered-cell-manifest-index-v1"
TARGET_CRS = "EPSG:31370"
HOLD_STATUS = "HOLD_UNPROVEN_ROAD_TO_LAMBERT72_FRAME"


def load_json(path: Path):
    if not path.is_file():
        raise RuntimeError(f"required file missing: {path}")
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise RuntimeError(f"invalid JSON: {path}") from exc


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _repo_root(index_path: Path) -> Path:
    resolved = index_path.resolve()
    parts = resolved.parts
    if "grand-bruxelles-game" not in parts:
        raise RuntimeError("road index is not under grand-bruxelles-game")
    idx = parts.index("grand-bruxelles-game")
    return Path(*parts[: idx + 1])


def _resolve_source(repo_root: Path, path_value: str) -> Path:
    if not isinstance(path_value, str) or not path_value:
        raise RuntimeError("road source path missing")
    rel = Path(path_value)
    if rel.is_absolute() or ".." in rel.parts:
        raise RuntimeError("road source path must remain repository-relative")
    resolved = (repo_root / rel).resolve()
    try:
        resolved.relative_to(repo_root.resolve())
    except ValueError as exc:
        raise RuntimeError("road source path escapes repository root") from exc
    return resolved


def audit(road_index_path: Path, cell_index_path: Path, crosswalk_path: Path):
    road_index_path = Path(road_index_path)
    cell_index_path = Path(cell_index_path)
    crosswalk_path = Path(crosswalk_path)
    road_index = load_json(road_index_path)
    cell_index = load_json(cell_index_path)

    if road_index.get("format") != ROAD_INDEX_FORMAT:
        raise RuntimeError("unsupported road index format")
    if road_index.get("source_lookup_only") is not True:
        raise RuntimeError("road index widened beyond source lookup")
    auth = road_index.get("authorization") or {}
    if auth.get("source_lookup_only") is not True:
        raise RuntimeError("road source lookup authorization missing")
    for key, value in auth.items():
        if key.endswith("_authorized") and value is not False:
            raise RuntimeError(f"road authorization widened: {key}")

    if cell_index.get("schema") != CELL_INDEX_SCHEMA:
        raise RuntimeError("unsupported registered-cell index schema")
    if cell_index.get("destination_readiness") != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise RuntimeError("registered-cell readiness widened")
    for key, value in cell_index.items():
        if key.endswith("_authorized") and value is not False:
            raise RuntimeError(f"registered-cell authorization widened: {key}")

    entries = cell_index.get("entries") or []
    if not entries:
        raise RuntimeError("registered-cell index is empty")
    for entry in entries:
        if entry.get("crs") != TARGET_CRS:
            raise RuntimeError("registered-cell CRS drifted from EPSG:31370")
        bbox = entry.get("bbox")
        if not isinstance(bbox, list) or len(bbox) != 4:
            raise RuntimeError("registered-cell bbox missing")

    repo_root = _repo_root(road_index_path)
    documents = road_index.get("documents") or []
    if not documents:
        raise RuntimeError("road source index is empty")

    road_count = 0
    source_frames = []
    for descriptor in documents:
        source_path = _resolve_source(repo_root, descriptor.get("path"))
        expected_sha = descriptor.get("sha256")
        if not isinstance(expected_sha, str) or len(expected_sha) != 64:
            raise RuntimeError("road source SHA-256 missing")
        actual_sha = sha256_file(source_path)
        if actual_sha != expected_sha:
            raise RuntimeError(f"road source SHA drift: {source_path}")
        source = load_json(source_path)
        if source.get("license") != "ODbL-1.0":
            raise RuntimeError("road source ODbL provenance drifted")
        roads = source.get("roads") or []
        indexed_ids = descriptor.get("road_ids") or []
        if len(indexed_ids) == 0:
            raise RuntimeError("road source descriptor has no road ids")
        source_ids = {int(r.get("osm_id", 0)) for r in roads if isinstance(r, dict)}
        if any(int(rid) not in source_ids for rid in indexed_ids):
            raise RuntimeError("indexed road is absent from pinned source")
        road_count += len(indexed_ids)

        origin = source.get("origin") or {}
        if not isinstance(origin.get("lat"), (int, float)) or not isinstance(origin.get("lon"), (int, float)):
            raise RuntimeError("local road source origin is missing")
        explicit_crs = source.get("crs")
        transform = source.get("coordinate_transform")
        frame_proven = explicit_crs == TARGET_CRS or (
            isinstance(transform, dict)
            and transform.get("target_crs") == TARGET_CRS
            and isinstance(transform.get("method"), str)
            and bool(transform.get("method"))
        )
        source_frames.append({
            "path": descriptor.get("path"),
            "sha256": expected_sha,
            "origin": {"lat": origin["lat"], "lon": origin["lon"]},
            "explicit_crs": explicit_crs,
            "coordinate_transform_present": isinstance(transform, dict),
            "frame_proven": frame_proven,
        })

    if crosswalk_path.exists():
        raise RuntimeError("explicit road-cell crosswalk already exists; frame-audit HOLD lot must stop")

    frame_proven = all(item["frame_proven"] for item in source_frames)
    if frame_proven:
        status = "READY_FOR_DETERMINISTIC_SPATIAL_CROSSWALK_REVIEW"
    else:
        status = HOLD_STATUS

    return {
        "schema": "grand-bruxelles-road-registered-cell-frame-audit-v1",
        "status": status,
        "road_source_document_count": len(documents),
        "indexed_road_count": road_count,
        "registered_cell_count": len(entries),
        "registered_cell_crs": TARGET_CRS,
        "source_frames": source_frames,
        "road_cell_crosswalk_present": False,
        "road_crosswalk_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--road-index", required=True)
    parser.add_argument("--cell-index", required=True)
    parser.add_argument("--crosswalk", required=True)
    parser.add_argument("--report")
    args = parser.parse_args()
    report = audit(Path(args.road_index), Path(args.cell_index), Path(args.crosswalk))
    if args.report:
        Path(args.report).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "ROAD_REGISTERED_CELL_FRAME_AUDIT_OK "
        f"status={report['status']} roads={report['indexed_road_count']} "
        f"cells={report['registered_cell_count']} crosswalk=false"
    )


if __name__ == "__main__":
    main()
