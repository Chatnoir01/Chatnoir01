#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

ROAD_INDEX_FORMAT = "grand-bruxelles-road-runtime-index-v1"
CELL_INDEX_SCHEMA = "grand-bruxelles-registered-cell-manifest-index-v1"
TARGET_CRS = "EPSG:31370"
FRAME_FORMULA = "E=origin_easting_m+x;N=origin_northing_m-z"
HOLD_STATUS = "HOLD_UNPROVEN_ROAD_TO_LAMBERT72_FRAME"
BOUND_STATUS = "CROSSWALK_FRAME_EVIDENCE_BOUND"
LEGACY_READINESS = "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY"
CORRECTED_READINESS = "CORRECTED_FRAME_ROAD_CELL_CROSSWALK_EVIDENCE_ONLY"
CLOSED_CROSSWALK_READINESS = {LEGACY_READINESS, CORRECTED_READINESS}


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
    return Path(*parts[: parts.index("grand-bruxelles-game") + 1])


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


def _closed(doc, label):
    for key, value in (doc or {}).items():
        if key.endswith("_authorized") and value is not False:
            raise RuntimeError(f"{label} authorization widened: {key}")


def _segment_intersects_rect(p0, p1, bbox):
    x0, z0 = float(p0[0]), float(p0[1])
    x1, z1 = float(p1[0]), float(p1[1])
    xmin, zmin, xmax, zmax = map(float, bbox)
    dx, dz = x1 - x0, z1 - z0
    p = (-dx, dx, -dz, dz)
    q = (x0 - xmin, xmax - x0, z0 - zmin, zmax - z0)
    u1, u2 = 0.0, 1.0
    for pi, qi in zip(p, q):
        if abs(pi) < 1e-15:
            if qi < 0.0:
                return False
            continue
        t = qi / pi
        if pi < 0.0:
            if t > u2:
                return False
            u1 = max(u1, t)
        else:
            if t < u1:
                return False
            u2 = min(u2, t)
    return u1 <= u2


def _local_to_lambert(point, east, north):
    return [east + float(point[0]), north - float(point[1])]


def _corrected_frame_hits(repo_root, contract_path, crosswalk, cells_by_id, doc_shas):
    contract = load_json(Path(contract_path))
    if contract.get("schema") != "grand-bruxelles-osm-road-frame-correction-impact-v2":
        raise RuntimeError("corrected-frame impact contract schema drifted")
    if contract.get("status") != "LOCKED_IMPACT_MEASUREMENT_EVIDENCE_ONLY":
        raise RuntimeError("corrected-frame impact contract is not locked evidence")
    _closed(contract.get("authorization"), "corrected-frame impact")

    source_desc = contract.get("source") or {}
    source_path = _resolve_source(repo_root, source_desc.get("path"))
    source_sha = source_desc.get("sha256")
    if source_sha not in doc_shas or source_sha != crosswalk.get("corrected_frame_source_sha256"):
        raise RuntimeError("corrected-frame source SHA is not bound to runtime/crosswalk evidence")
    if sha256_file(source_path) != source_sha:
        raise RuntimeError("corrected-frame source SHA drift")
    source = load_json(source_path)
    if source.get("format") != "grand-bruxelles-osm-v1":
        raise RuntimeError("corrected-frame source format drifted")
    if source.get("source") != source_desc.get("provider") or source.get("license") != "ODbL-1.0" or source_desc.get("license") != "ODbL-1.0":
        raise RuntimeError("corrected-frame source provenance drifted")

    frame_desc = contract.get("frame_review") or {}
    frame_path = _resolve_source(repo_root, frame_desc.get("path"))
    frame_review = load_json(frame_path)
    if frame_review.get("review_semantic_sha256") != frame_desc.get("review_semantic_sha256"):
        raise RuntimeError("corrected-frame review semantic drift")
    candidate = frame_review.get("candidate_frame") or {}
    if candidate.get("crs") != TARGET_CRS or frame_desc.get("crs") != TARGET_CRS:
        raise RuntimeError("corrected-frame CRS drifted")
    if candidate.get("formula") != FRAME_FORMULA or frame_desc.get("formula") != FRAME_FORMULA:
        raise RuntimeError("corrected-frame formula drifted")
    east = frame_desc.get("origin_easting_m")
    north = frame_desc.get("origin_northing_m")
    if float(candidate.get("origin_easting_m")) != float(east) or float(candidate.get("origin_northing_m")) != float(north):
        raise RuntimeError("corrected-frame origin drifted")
    _closed(frame_review.get("authorization"), "corrected-frame review")

    registered = contract.get("registered_cell_index") or {}
    if registered.get("schema") != CELL_INDEX_SCHEMA or int(registered.get("registered_cell_count", -1)) != len(cells_by_id):
        raise RuntimeError("corrected-frame registered-cell evidence drifted")
    if crosswalk.get("registered_cell_index_semantic_sha256") != registered.get("semantic_sha256"):
        raise RuntimeError("corrected-frame registered-cell semantic drifted")

    roads = {}
    for road in source.get("roads") or []:
        if not isinstance(road, dict):
            continue
        rid = int(road.get("osm_id", 0))
        points = road.get("points") or []
        if rid <= 0 or len(points) < 2:
            continue
        roads[rid] = points

    hits_by_road = {}
    for rid, local_points in roads.items():
        points = [_local_to_lambert(point, east, north) for point in local_points]
        hits = []
        for cell_id, bbox in cells_by_id.items():
            if any(_segment_intersects_rect(points[i], points[i + 1], bbox) for i in range(len(points) - 1)):
                hits.append(cell_id)
        hits_by_road[rid] = sorted(hits)

    return hits_by_road


def audit(
    road_index_path: Path,
    cell_index_path: Path,
    crosswalk_path: Path,
    coverage_path: Path | None = None,
    corrected_frame_contract_path: Path | None = None,
):
    road_index_path = Path(road_index_path)
    cell_index_path = Path(cell_index_path)
    crosswalk_path = Path(crosswalk_path)
    road_index = load_json(road_index_path)
    cell_index = load_json(cell_index_path)
    if road_index.get("format") != ROAD_INDEX_FORMAT or road_index.get("source_lookup_only") is not True:
        raise RuntimeError("road index widened or unsupported")
    auth = road_index.get("authorization") or {}
    if auth.get("source_lookup_only") is not True:
        raise RuntimeError("road source lookup authorization missing")
    _closed(auth, "road")
    if cell_index.get("schema") != CELL_INDEX_SCHEMA or cell_index.get("destination_readiness") != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise RuntimeError("registered-cell index widened or unsupported")
    _closed(cell_index, "registered-cell")
    entries = cell_index.get("entries") or []
    if not entries:
        raise RuntimeError("registered-cell index is empty")
    if int(cell_index.get("registered_cell_count", -1)) != len(entries):
        raise RuntimeError("registered-cell accounting drifted")
    cells_by_id = {}
    for entry in entries:
        if entry.get("crs") != TARGET_CRS:
            raise RuntimeError("registered-cell CRS drifted")
        bbox = entry.get("bbox")
        if not isinstance(bbox, list) or len(bbox) != 4:
            raise RuntimeError("registered-cell bbox missing")
        cells_by_id[entry.get("cell_id")] = bbox

    repo_root = _repo_root(road_index_path)
    documents = road_index.get("documents") or []
    if not documents:
        raise RuntimeError("road source index is empty")
    road_count = 0
    source_frames = []
    runtime_ids = set()
    doc_shas = set()
    for descriptor in documents:
        source_path = _resolve_source(repo_root, descriptor.get("path"))
        expected_sha = descriptor.get("sha256")
        if not isinstance(expected_sha, str) or len(expected_sha) != 64:
            raise RuntimeError("road source SHA-256 missing")
        if sha256_file(source_path) != expected_sha:
            raise RuntimeError(f"road source SHA drift: {source_path}")
        doc_shas.add(expected_sha)
        source = load_json(source_path)
        if source.get("license") != "ODbL-1.0":
            raise RuntimeError("road source ODbL provenance drifted")
        roads = source.get("roads") or []
        indexed_ids = descriptor.get("road_ids") or []
        source_ids = {int(r.get("osm_id", 0)) for r in roads if isinstance(r, dict)}
        if not indexed_ids or any(int(rid) not in source_ids for rid in indexed_ids):
            raise RuntimeError("indexed road absent from pinned source")
        runtime_ids.update(int(rid) for rid in indexed_ids)
        road_count += len(indexed_ids)
        origin = source.get("origin") or {}
        explicit_crs = source.get("crs")
        transform = source.get("coordinate_transform")
        if not isinstance(origin.get("lat"), (int, float)) or not isinstance(origin.get("lon"), (int, float)):
            raise RuntimeError("local road origin missing")
        native = explicit_crs == TARGET_CRS or (
            isinstance(transform, dict)
            and transform.get("target_crs") == TARGET_CRS
            and bool(transform.get("method"))
        )
        source_frames.append({
            "path": descriptor.get("path"),
            "sha256": expected_sha,
            "origin": {"lat": origin["lat"], "lon": origin["lon"]},
            "explicit_crs": explicit_crs,
            "coordinate_transform_present": isinstance(transform, dict),
            "frame_proven": native,
        })

    crosswalk_present = crosswalk_path.exists()
    external_frame = False
    spatial_basis = None
    if crosswalk_present:
        if coverage_path is None:
            raise RuntimeError("explicit road-cell crosswalk requires reviewed coverage-frame evidence")
        coverage = load_json(Path(coverage_path))
        crosswalk = load_json(crosswalk_path)
        if coverage.get("schema") != "grand-bruxelles-road-cell-coverage-candidates-v2" or coverage.get("status") != "DISCOVERED_SOURCE_ONLY":
            raise RuntimeError("coverage evidence widened")
        _closed(coverage, "coverage")
        frame = coverage.get("frame") or {}
        if frame.get("crs") != TARGET_CRS or frame.get("formula") != FRAME_FORMULA:
            raise RuntimeError("coverage Lambert72 frame contract drifted")
        if coverage.get("road_source_sha256") not in doc_shas:
            raise RuntimeError("coverage source SHA is not bound to runtime road descriptor")
        readiness = crosswalk.get("destination_readiness")
        if crosswalk.get("schema") != "grand-bruxelles-road-registered-cell-crosswalk-v1" or readiness not in CLOSED_CROSSWALK_READINESS:
            raise RuntimeError("crosswalk readiness widened")
        _closed(crosswalk, "crosswalk")
        if crosswalk.get("coverage_semantic_sha256") != coverage.get("semantic_sha256") or crosswalk.get("road_semantic_sha256") != coverage.get("road_semantic_sha256"):
            raise RuntimeError("crosswalk is not bound to reviewed coverage semantics")

        rows = crosswalk.get("rows") or []
        for row in rows:
            rid = row.get("road_osm_id")
            cid = row.get("cell_id")
            if rid not in runtime_ids or cid not in cells_by_id:
                raise RuntimeError("crosswalk membership drift")

        if readiness == LEGACY_READINESS:
            candidate_by_grid = {c.get("grid_cell_id"): c for c in coverage.get("candidates") or []}
            for row in rows:
                rid = row.get("road_osm_id")
                cid = row.get("cell_id")
                gid = row.get("grid_cell_id")
                candidate = candidate_by_grid.get(gid)
                if not candidate or rid not in (candidate.get("road_ids") or []) or candidate.get("bbox") != cells_by_id[cid]:
                    raise RuntimeError("crosswalk spatial evidence drift")
            spatial_basis = "legacy_reviewed_coverage"
        else:
            if corrected_frame_contract_path is None:
                raise RuntimeError("corrected-frame crosswalk requires locked corrected-frame source evidence")
            hits_by_road = _corrected_frame_hits(
                repo_root,
                Path(corrected_frame_contract_path),
                crosswalk,
                cells_by_id,
                doc_shas,
            )
            for row in rows:
                rid = int(row.get("road_osm_id"))
                expected_cell = row.get("cell_id")
                hits = hits_by_road.get(rid)
                if hits != [expected_cell]:
                    raise RuntimeError("corrected-frame crosswalk spatial evidence drift")
            excluded = {int(rid) for rid in (crosswalk.get("excluded_multicell_road_ids") or [])}
            row_ids = {int(row.get("road_osm_id")) for row in rows}
            if excluded & row_ids:
                raise RuntimeError("corrected-frame HOLD road leaked into unique crosswalk")
            for rid in excluded:
                if len(hits_by_road.get(rid) or []) <= 1:
                    raise RuntimeError("corrected-frame HOLD road is no longer multicell")
            spatial_basis = "locked_corrected_source_geometry"
        external_frame = True

    native_frame = all(item["frame_proven"] for item in source_frames)
    status = BOUND_STATUS if external_frame else (
        "READY_FOR_DETERMINISTIC_SPATIAL_CROSSWALK_REVIEW" if native_frame else HOLD_STATUS
    )
    return {
        "schema": "grand-bruxelles-road-registered-cell-frame-audit-v1",
        "status": status,
        "road_source_document_count": len(documents),
        "indexed_road_count": road_count,
        "registered_cell_count": len(entries),
        "registered_cell_crs": TARGET_CRS,
        "source_frames": source_frames,
        "road_cell_crosswalk_present": crosswalk_present,
        "external_coverage_frame_bound": external_frame,
        "spatial_evidence_basis": spatial_basis,
        "road_crosswalk_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--road-index", required=True)
    p.add_argument("--cell-index", required=True)
    p.add_argument("--crosswalk", required=True)
    p.add_argument("--coverage")
    p.add_argument("--corrected-frame-contract")
    p.add_argument("--report")
    a = p.parse_args()
    report = audit(
        Path(a.road_index),
        Path(a.cell_index),
        Path(a.crosswalk),
        Path(a.coverage) if a.coverage else None,
        Path(a.corrected_frame_contract) if a.corrected_frame_contract else None,
    )
    if a.report:
        Path(a.report).write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        f"ROAD_REGISTERED_CELL_FRAME_AUDIT_OK status={report['status']} "
        f"roads={report['indexed_road_count']} cells={report['registered_cell_count']} "
        f"crosswalk={str(report['road_cell_crosswalk_present']).lower()} "
        f"spatial_basis={report['spatial_evidence_basis']}"
    )


if __name__ == "__main__":
    main()
