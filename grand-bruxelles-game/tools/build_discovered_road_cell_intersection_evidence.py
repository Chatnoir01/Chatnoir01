#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-discovered-road-cell-intersection-evidence-v1"
TARGET_CRS = "EPSG:31370"
FRAME_FORMULA = "E=origin_easting_m+x;N=origin_northing_m-z"


def canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def sha256_json(value: Any) -> str:
    return hashlib.sha256(canonical_json(value).encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def is_sha256(value: Any) -> bool:
    text = str(value or "").lower()
    return len(text) == 64 and all(ch in "0123456789abcdef" for ch in text)


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise SystemExit(f"DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: invalid JSON {path}") from exc
    if not isinstance(value, dict):
        raise SystemExit(f"DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: invalid object {path}")
    return value


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def require_closed(mapping: dict[str, Any], label: str) -> None:
    for key, value in mapping.items():
        if key.endswith("_authorized") and value is not False:
            raise SystemExit(f"DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: {label} opened {key}")


def segment_intersects_rect(p0: list[float], p1: list[float], bbox: list[float]) -> bool:
    x0, y0 = float(p0[0]), float(p0[1])
    x1, y1 = float(p1[0]), float(p1[1])
    xmin, ymin, xmax, ymax = map(float, bbox)
    dx, dy = x1 - x0, y1 - y0
    p = (-dx, dx, -dy, dy)
    q = (x0 - xmin, xmax - x0, y0 - ymin, ymax - y0)
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


def _root_from_source(source_path: Path) -> Path:
    resolved = source_path.resolve()
    for parent in [resolved.parent, *resolved.parents]:
        if parent.name == "grand-bruxelles-game":
            return parent
    raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: source outside grand-bruxelles-game")


def _build_frontier(root: Path):
    tool = load_module(root / "tools/build_road_acquisition_frontier.py", "road_acquisition_frontier_for_intersections")
    return tool.build_frontier(
        root / "data/osm",
        root / "data/provenance/brussels_road_destination_readiness_catalog.json",
        root / "tools/build_road_destination_catalog.py",
        root / "tools/build_road_destination_provenance_binding.py",
        root / "tools/build_road_municipality_coverage_audit.py",
    )


def _locked_frame(source_path: Path, frame_path: Path, cell_index_path: Path):
    frame = load_json(frame_path)
    if frame.get("schema") != "grand-bruxelles-osm-road-frame-correction-impact-v2" or frame.get("status") != "LOCKED_IMPACT_MEASUREMENT_EVIDENCE_ONLY":
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: frame contract drift")
    require_closed(frame.get("authorization") or {}, "frame")
    source_desc = frame.get("source") or {}
    if source_desc.get("path") != "data/osm/vertical_slice_01.game.json" or source_desc.get("license") != "ODbL-1.0":
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: source provenance drift")
    if not is_sha256(source_desc.get("sha256")) or sha256_file(source_path) != source_desc.get("sha256"):
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: source document sha drift")
    desc = frame.get("frame_review") or {}
    if desc.get("crs") != TARGET_CRS or desc.get("formula") != FRAME_FORMULA:
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: corrected frame drift")
    east = float(desc.get("origin_easting_m"))
    north = float(desc.get("origin_northing_m"))
    cells_desc = frame.get("registered_cell_index") or {}
    cells = load_json(cell_index_path)
    if cells.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1" or cells.get("destination_readiness") != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: cell index drift")
    require_closed(cells, "cell index")
    if cells_desc.get("semantic_sha256") != cells.get("semantic_sha256") or int(cells_desc.get("registered_cell_count", -1)) != int(cells.get("registered_cell_count", -2)):
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: frame/cell semantic drift")
    return frame, cells, east, north


def _cell_rows(root: Path, cells: dict[str, Any]) -> list[dict[str, Any]]:
    result = []
    entries = cells.get("entries") or []
    if len(entries) != int(cells.get("registered_cell_count", -1)):
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: cell accounting drift")
    for entry in entries:
        if entry.get("crs") != TARGET_CRS:
            raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: cell CRS drift")
        bbox = entry.get("bbox")
        manifest_path = str(entry.get("manifest_path") or "")
        manifest_sha = str(entry.get("manifest_sha256") or "").lower()
        if not isinstance(bbox, list) or len(bbox) != 4 or not manifest_path.startswith("data/cell_manifests/") or not is_sha256(manifest_sha):
            raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: cell manifest identity drift")
        manifest = root / manifest_path
        if not manifest.is_file() or sha256_file(manifest) != manifest_sha:
            raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: cell manifest sha drift")
        result.append({"cell_id": entry.get("cell_id"), "crs": TARGET_CRS, "bbox": bbox, "manifest_path": manifest_path, "manifest_sha256": manifest_sha})
    return sorted(result, key=lambda row: str(row["cell_id"]))


def _build_unchecked(source_path: Path, frame_path: Path, cell_index_path: Path) -> dict[str, Any]:
    source_path, frame_path, cell_index_path = map(Path, (source_path, frame_path, cell_index_path))
    root = _root_from_source(source_path)
    frontier = _build_frontier(root)
    frame, cells, east, north = _locked_frame(source_path, frame_path, cell_index_path)
    source = load_json(source_path)
    if source.get("format") != "grand-bruxelles-osm-v1" or source.get("license") != "ODbL-1.0":
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: source format/provenance drift")
    roads = {int(row["osm_id"]): row for row in source.get("roads") or [] if isinstance(row, dict) and int(row.get("osm_id", 0)) > 0}
    cell_rows = _cell_rows(root, cells)

    candidates = []
    for candidate in frontier.get("candidates") or []:
        rid = int(candidate.get("road_osm_id", 0))
        road = roads.get(rid)
        if not road:
            raise SystemExit(f"DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: missing source road {rid}")
        points = road.get("points") or []
        if len(points) < 2:
            raise SystemExit(f"DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: invalid source geometry {rid}")
        lambert = [[east + float(point[0]), north - float(point[1])] for point in points]
        hits = []
        for cell in cell_rows:
            if any(segment_intersects_rect(lambert[i], lambert[i + 1], cell["bbox"]) for i in range(len(lambert) - 1)):
                hits.append({k: cell[k] for k in ("cell_id", "crs", "bbox", "manifest_path", "manifest_sha256")})
        candidates.append({
            "road_osm_id": rid,
            "name": candidate.get("name", ""),
            "state": "DISCOVERED",
            "source_geometry_sha256": candidate.get("source_geometry_sha256"),
            "source_document_sha256": candidate.get("source_document_sha256"),
            "intersection_count": len(hits),
            "intersections": hits,
            "cell_id": None,
            "municipalities": None,
            "proposed_municipality_niscodes": None,
            "registration_ready": False,
        })
    candidates.sort(key=lambda row: row["road_osm_id"])
    payload = {
        "format": FORMAT,
        "source_crs": TARGET_CRS,
        "frame_formula": FRAME_FORMULA,
        "frame_origin_easting_m": east,
        "frame_origin_northing_m": north,
        "source_document_sha256": frame["source"]["sha256"],
        "source_frontier_sha256": frontier["frontier_sha256"],
        "registered_cell_index_semantic_sha256": cells["semantic_sha256"],
        "candidate_count": len(candidates),
        "candidate_road_osm_ids": [row["road_osm_id"] for row in candidates],
        "zero_intersection_count": sum(row["intersection_count"] == 0 for row in candidates),
        "unique_intersection_count": sum(row["intersection_count"] == 1 for row in candidates),
        "multicell_intersection_count": sum(row["intersection_count"] > 1 for row in candidates),
        "candidates": candidates,
        "assignment_authorized": False,
        "municipality_inference_authorized": False,
        "source_registration_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_mount_authorized": False,
        "render_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_authorized": False,
    }
    payload["evidence_sha256"] = sha256_json(payload)
    return payload


def validate_structure(evidence: dict[str, Any]) -> None:
    if evidence.get("format") != FORMAT or evidence.get("source_crs") != TARGET_CRS or evidence.get("frame_formula") != FRAME_FORMULA:
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: evidence format/frame drift")
    for key in ("assignment_authorized", "municipality_inference_authorized", "source_registration_authorized", "road_cell_mapping_authorized", "runtime_mount_authorized", "render_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_authorized"):
        if evidence.get(key) is not False:
            raise SystemExit(f"DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: assignment authorization opened: {key}")
    candidates = evidence.get("candidates")
    if not isinstance(candidates, list) or len(candidates) != int(evidence.get("candidate_count", -1)):
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: candidate accounting drift")
    ids = [row.get("road_osm_id") for row in candidates]
    if ids != sorted(set(ids)) or ids != evidence.get("candidate_road_osm_ids"):
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: candidate identity drift")
    for row in candidates:
        if row.get("state") != "DISCOVERED" or row.get("registration_ready") is not False:
            raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: candidate state drift")
        if row.get("cell_id") is not None or row.get("municipalities") is not None or row.get("proposed_municipality_niscodes") is not None:
            raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: municipality inference leaked")
        hits = row.get("intersections")
        if not isinstance(hits, list) or len(hits) != int(row.get("intersection_count", -1)):
            raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: intersection accounting drift")
        if hits != sorted(hits, key=lambda hit: str(hit.get("cell_id"))):
            raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: intersection ordering drift")
        for hit in hits:
            if hit.get("crs") != TARGET_CRS or not str(hit.get("manifest_path") or "").startswith("data/cell_manifests/") or not is_sha256(hit.get("manifest_sha256")):
                raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: cell intersection identity drift")
    if int(evidence.get("zero_intersection_count", -1)) != sum(row["intersection_count"] == 0 for row in candidates) or int(evidence.get("unique_intersection_count", -1)) != sum(row["intersection_count"] == 1 for row in candidates) or int(evidence.get("multicell_intersection_count", -1)) != sum(row["intersection_count"] > 1 for row in candidates):
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: intersection summary drift")
    unsigned = dict(evidence)
    stored = unsigned.pop("evidence_sha256", None)
    if not is_sha256(stored) or stored != sha256_json(unsigned):
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: evidence sha drift")


def build_evidence(source_path: Path, frame_path: Path, cell_index_path: Path) -> dict[str, Any]:
    evidence = _build_unchecked(source_path, frame_path, cell_index_path)
    validate_structure(evidence)
    return evidence


def validate_evidence(evidence: dict[str, Any], source_path: Path, frame_path: Path, cell_index_path: Path) -> None:
    validate_structure(evidence)
    expected = _build_unchecked(source_path, frame_path, cell_index_path)
    if canonical_json(evidence) != canonical_json(expected):
        raise SystemExit("DISCOVERED_ROAD_CELL_INTERSECTION_FAIL: source binding drift")


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--source", type=Path, default=Path("data/osm/vertical_slice_01.game.json"))
    p.add_argument("--frame", type=Path, default=Path("data/qa/osm_road_frame_correction_impact.contract.json"))
    p.add_argument("--cells", type=Path, default=Path("data/provenance/brussels_registered_cell_manifest_index.json"))
    p.add_argument("--output", type=Path, required=True)
    a = p.parse_args()
    evidence = build_evidence(a.source, a.frame, a.cells)
    validate_evidence(evidence, a.source, a.frame, a.cells)
    a.output.parent.mkdir(parents=True, exist_ok=True)
    a.output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"DISCOVERED_ROAD_CELL_INTERSECTION_GREEN: candidates={evidence['candidate_count']} zero={evidence['zero_intersection_count']} unique={evidence['unique_intersection_count']} multicell={evidence['multicell_intersection_count']} sha256={evidence['evidence_sha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
