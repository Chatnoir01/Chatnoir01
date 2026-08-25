#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

ROAD_INDEX_FORMAT = "grand-bruxelles-road-runtime-index-v1"
CELL_INDEX_SCHEMA = "grand-bruxelles-registered-cell-manifest-index-v1"
TARGET_CRS = "EPSG:31370"
HOLD_STATUS = "HOLD_UNPROVEN_ROAD_TO_LAMBERT72_FRAME"
BOUND_STATUS = "CROSSWALK_FRAME_EVIDENCE_BOUND"


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
    resolved = index_path.resolve(); parts = resolved.parts
    if "grand-bruxelles-game" not in parts:
        raise RuntimeError("road index is not under grand-bruxelles-game")
    return Path(*parts[: parts.index("grand-bruxelles-game") + 1])


def _resolve_source(repo_root: Path, path_value: str) -> Path:
    if not isinstance(path_value, str) or not path_value:
        raise RuntimeError("road source path missing")
    rel = Path(path_value)
    if rel.is_absolute() or ".." in rel.parts:
        raise RuntimeError("road source path must remain repository-relative")
    resolved = (repo_root / rel).resolve()
    try: resolved.relative_to(repo_root.resolve())
    except ValueError as exc: raise RuntimeError("road source path escapes repository root") from exc
    return resolved


def _closed(doc, label):
    for key, value in (doc or {}).items():
        if key.endswith("_authorized") and value is not False:
            raise RuntimeError(f"{label} authorization widened: {key}")


def audit(road_index_path: Path, cell_index_path: Path, crosswalk_path: Path, coverage_path: Path | None = None):
    road_index_path = Path(road_index_path); cell_index_path = Path(cell_index_path); crosswalk_path = Path(crosswalk_path)
    road_index = load_json(road_index_path); cell_index = load_json(cell_index_path)
    if road_index.get("format") != ROAD_INDEX_FORMAT or road_index.get("source_lookup_only") is not True:
        raise RuntimeError("road index widened or unsupported")
    auth = road_index.get("authorization") or {}
    if auth.get("source_lookup_only") is not True: raise RuntimeError("road source lookup authorization missing")
    _closed(auth, "road")
    if cell_index.get("schema") != CELL_INDEX_SCHEMA or cell_index.get("destination_readiness") != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise RuntimeError("registered-cell index widened or unsupported")
    _closed(cell_index, "registered-cell")
    entries = cell_index.get("entries") or []
    if not entries: raise RuntimeError("registered-cell index is empty")
    cells_by_id = {}
    for entry in entries:
        if entry.get("crs") != TARGET_CRS: raise RuntimeError("registered-cell CRS drifted")
        bbox = entry.get("bbox")
        if not isinstance(bbox, list) or len(bbox) != 4: raise RuntimeError("registered-cell bbox missing")
        cells_by_id[entry.get("cell_id")] = bbox

    repo_root = _repo_root(road_index_path); documents = road_index.get("documents") or []
    if not documents: raise RuntimeError("road source index is empty")
    road_count = 0; source_frames = []; runtime_ids = set(); doc_shas = set()
    for descriptor in documents:
        source_path = _resolve_source(repo_root, descriptor.get("path")); expected_sha = descriptor.get("sha256")
        if not isinstance(expected_sha, str) or len(expected_sha) != 64: raise RuntimeError("road source SHA-256 missing")
        if sha256_file(source_path) != expected_sha: raise RuntimeError(f"road source SHA drift: {source_path}")
        doc_shas.add(expected_sha); source = load_json(source_path)
        if source.get("license") != "ODbL-1.0": raise RuntimeError("road source ODbL provenance drifted")
        roads = source.get("roads") or []; indexed_ids = descriptor.get("road_ids") or []
        source_ids = {int(r.get("osm_id", 0)) for r in roads if isinstance(r, dict)}
        if not indexed_ids or any(int(rid) not in source_ids for rid in indexed_ids): raise RuntimeError("indexed road absent from pinned source")
        runtime_ids.update(int(rid) for rid in indexed_ids); road_count += len(indexed_ids)
        origin = source.get("origin") or {}; explicit_crs = source.get("crs"); transform = source.get("coordinate_transform")
        if not isinstance(origin.get("lat"), (int,float)) or not isinstance(origin.get("lon"), (int,float)): raise RuntimeError("local road origin missing")
        native = explicit_crs == TARGET_CRS or (isinstance(transform, dict) and transform.get("target_crs") == TARGET_CRS and bool(transform.get("method")))
        source_frames.append({"path":descriptor.get("path"),"sha256":expected_sha,"origin":{"lat":origin["lat"],"lon":origin["lon"]},"explicit_crs":explicit_crs,"coordinate_transform_present":isinstance(transform,dict),"frame_proven":native})

    crosswalk_present = crosswalk_path.exists(); external_frame = False
    if crosswalk_present:
        if coverage_path is None: raise RuntimeError("explicit road-cell crosswalk requires reviewed coverage-frame evidence")
        coverage = load_json(Path(coverage_path)); crosswalk = load_json(crosswalk_path)
        if coverage.get("schema") != "grand-bruxelles-road-cell-coverage-candidates-v2" or coverage.get("status") != "DISCOVERED_SOURCE_ONLY": raise RuntimeError("coverage evidence widened")
        _closed(coverage, "coverage")
        frame = coverage.get("frame") or {}
        if frame.get("crs") != TARGET_CRS or frame.get("formula") != "E=origin_easting_m+x;N=origin_northing_m-z": raise RuntimeError("coverage Lambert72 frame contract drifted")
        if coverage.get("road_source_sha256") not in doc_shas: raise RuntimeError("coverage source SHA is not bound to runtime road descriptor")
        if crosswalk.get("schema") != "grand-bruxelles-road-registered-cell-crosswalk-v1" or crosswalk.get("destination_readiness") != "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY": raise RuntimeError("crosswalk readiness widened")
        _closed(crosswalk, "crosswalk")
        if crosswalk.get("coverage_semantic_sha256") != coverage.get("semantic_sha256") or crosswalk.get("road_semantic_sha256") != coverage.get("road_semantic_sha256"): raise RuntimeError("crosswalk is not bound to reviewed coverage semantics")
        candidate_by_grid = {c.get("grid_cell_id"): c for c in coverage.get("candidates") or []}
        for row in crosswalk.get("rows") or []:
            rid = row.get("road_osm_id"); cid = row.get("cell_id"); gid = row.get("grid_cell_id")
            if rid not in runtime_ids or cid not in cells_by_id: raise RuntimeError("crosswalk membership drift")
            candidate = candidate_by_grid.get(gid)
            if not candidate or rid not in (candidate.get("road_ids") or []) or candidate.get("bbox") != cells_by_id[cid]: raise RuntimeError("crosswalk spatial evidence drift")
        external_frame = True

    native_frame = all(item["frame_proven"] for item in source_frames)
    status = BOUND_STATUS if external_frame else ("READY_FOR_DETERMINISTIC_SPATIAL_CROSSWALK_REVIEW" if native_frame else HOLD_STATUS)
    return {"schema":"grand-bruxelles-road-registered-cell-frame-audit-v1","status":status,"road_source_document_count":len(documents),"indexed_road_count":road_count,"registered_cell_count":len(entries),"registered_cell_crs":TARGET_CRS,"source_frames":source_frames,"road_cell_crosswalk_present":crosswalk_present,"external_coverage_frame_bound":external_frame,"road_crosswalk_authorized":False,"runtime_mount_authorized":False,"rendered_geometry_authorized":False,"collision_authorized":False,"safe_spawn_authorized":False,"jouable_promotion_authorized":False}


def main():
    p=argparse.ArgumentParser(); p.add_argument("--road-index",required=True); p.add_argument("--cell-index",required=True); p.add_argument("--crosswalk",required=True); p.add_argument("--coverage"); p.add_argument("--report"); a=p.parse_args()
    report=audit(Path(a.road_index),Path(a.cell_index),Path(a.crosswalk),Path(a.coverage) if a.coverage else None)
    if a.report: Path(a.report).write_text(json.dumps(report,indent=2,sort_keys=True)+"\n",encoding="utf-8")
    print(f"ROAD_REGISTERED_CELL_FRAME_AUDIT_OK status={report['status']} roads={report['indexed_road_count']} cells={report['registered_cell_count']} crosswalk={str(report['road_cell_crosswalk_present']).lower()}")

if __name__ == "__main__": main()
