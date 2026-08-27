#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def canonical_sha256(obj) -> str:
    payload = json.dumps(obj, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def semantic_identity_basis(result):
    """Return the stable engineering identity, excluding continuity-only metadata."""
    basis = dict(result)
    basis.pop("semantic_sha256", None)
    basis.pop("production_base_sha", None)
    return basis


def segment_intersects_rect(p0, p1, bbox):
    x0, z0 = float(p0[0]), float(p0[1])
    x1, z1 = float(p1[0]), float(p1[1])
    xmin, zmin, xmax, zmax = map(float, bbox)
    dx = x1 - x0
    dz = z1 - z0
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


def local_to_lambert(point, east, north):
    return [east + float(point[0]), north - float(point[1])]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contract", required=True)
    ap.add_argument("--repo-root", default=".")
    ap.add_argument("--live-main-sha", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    root = Path(args.repo_root).resolve()
    contract = load_json(root / args.contract)
    assert contract["schema"] == "grand-bruxelles-osm-road-frame-correction-impact-v2"
    assert contract["status"] in {"MEASUREMENT_PENDING", "LOCKED_IMPACT_MEASUREMENT_EVIDENCE_ONLY"}
    assert contract["production_base_sha"] == args.live_main_sha
    assert contract["semantic_identity_policy"] == {
        "canonical_json": "sort_keys_compact_utf8",
        "exclude_continuity_fields": ["production_base_sha"],
        "artifact_semantic_retained_for_forensics": True,
    }
    assert all(v is False for v in contract["authorization"].values())

    source_path = root / contract["source"]["path"]
    assert sha256_file(source_path) == contract["source"]["sha256"]
    source = load_json(source_path)
    assert source["format"] == "grand-bruxelles-osm-v1"
    assert source["source"] == contract["source"]["provider"]
    assert source["license"] == contract["source"]["license"]

    frame = load_json(root / contract["frame_review"]["path"])
    assert frame["review_semantic_sha256"] == contract["frame_review"]["review_semantic_sha256"]
    candidate = frame["candidate_frame"]
    assert candidate["crs"] == contract["frame_review"]["crs"]
    assert float(candidate["origin_easting_m"]) == contract["frame_review"]["origin_easting_m"]
    assert float(candidate["origin_northing_m"]) == contract["frame_review"]["origin_northing_m"]
    assert candidate["formula"] == contract["frame_review"]["formula"]
    assert frame["authorization"]["production_frame_update_authorized"] is False

    index = load_json(root / contract["registered_cell_index"]["path"])
    assert index["schema"] == contract["registered_cell_index"]["schema"]
    assert index["semantic_sha256"] == contract["registered_cell_index"]["semantic_sha256"]
    assert index["registered_cell_count"] == contract["registered_cell_index"]["registered_cell_count"]
    assert len(index["entries"]) == index["registered_cell_count"]
    assert all(e["crs"] == "EPSG:31370" and e["evidence_only"] is True for e in index["entries"])
    for key in ["road_crosswalk_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"]:
        assert index[key] is False

    current = load_json(root / contract["current_crosswalk"]["path"])
    assert current["destination_readiness"] == contract["current_crosswalk"]["destination_readiness"]
    assert current["road_semantic_sha256"] == contract["current_crosswalk"]["road_semantic_sha256"]
    assert current["registered_cell_index_semantic_sha256"] == contract["current_crosswalk"]["registered_cell_index_semantic_sha256"]
    for key in ["road_cell_mapping_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"]:
        assert current[key] is False

    boxes = {e["cell_id"]: e["bbox"] for e in index["entries"]}
    east = contract["frame_review"]["origin_easting_m"]
    north = contract["frame_review"]["origin_northing_m"]

    candidate_rows = []
    multicell_rows = []
    no_overlap = []
    for road in source["roads"]:
        road_id = int(road["osm_id"])
        points = [local_to_lambert(p, east, north) for p in road["points"]]
        hit_cells = []
        for cell_id, bbox in boxes.items():
            if any(segment_intersects_rect(points[i], points[i + 1], bbox) for i in range(len(points) - 1)):
                hit_cells.append(cell_id)
        hit_cells.sort()
        row = {"road_osm_id": road_id, "name": road.get("name", ""), "hit_cells": hit_cells}
        if len(hit_cells) == 1:
            candidate_rows.append({"road_osm_id": road_id, "cell_id": hit_cells[0], "name": road.get("name", "")})
        elif len(hit_cells) > 1:
            multicell_rows.append(row)
        else:
            no_overlap.append(road_id)

    candidate_rows.sort(key=lambda r: r["road_osm_id"])
    multicell_rows.sort(key=lambda r: r["road_osm_id"])
    no_overlap.sort()

    current_map = {int(r["road_osm_id"]): r["cell_id"] for r in current["rows"]}
    candidate_map = {int(r["road_osm_id"]): r["cell_id"] for r in candidate_rows}
    retained = sorted(r for r, c in candidate_map.items() if current_map.get(r) == c)
    changed = sorted(
        (
            {"road_osm_id": r, "current_cell_id": current_map[r], "candidate_cell_id": c}
            for r, c in candidate_map.items()
            if r in current_map and current_map[r] != c
        ),
        key=lambda x: x["road_osm_id"],
    )
    newly_mappable = sorted(r for r in candidate_map if r not in current_map)
    no_longer_mappable = sorted(r for r in current_map if r not in candidate_map)

    cell_counts = {}
    for row in candidate_rows:
        cell_counts[row["cell_id"]] = cell_counts.get(row["cell_id"], 0) + 1

    result = {
        "schema": "grand-bruxelles-osm-road-frame-correction-impact-measurement-v1",
        "status": "MEASURED_FRAME_CORRECTION_IMPACT_EVIDENCE_ONLY",
        "production_base_sha": args.live_main_sha,
        "source_sha256": contract["source"]["sha256"],
        "source_license": contract["source"]["license"],
        "candidate_frame": {
            "crs": "EPSG:31370",
            "origin_easting_m": east,
            "origin_northing_m": north,
            "formula": contract["frame_review"]["formula"],
            "review_semantic_sha256": contract["frame_review"]["review_semantic_sha256"],
        },
        "accounting": {
            "source_road_count": len(source["roads"]),
            "registered_cell_count": len(boxes),
            "current_mapped_road_count": len(current_map),
            "candidate_unique_mapped_road_count": len(candidate_rows),
            "candidate_multicell_road_count": len(multicell_rows),
            "candidate_no_registered_overlap_count": len(no_overlap),
            "retained_mapping_count": len(retained),
            "changed_mapping_count": len(changed),
            "newly_mappable_count": len(newly_mappable),
            "no_longer_mappable_count": len(no_longer_mappable),
            "candidate_cell_counts": dict(sorted(cell_counts.items())),
        },
        "candidate_unique_rows": candidate_rows,
        "candidate_multicell_rows": multicell_rows,
        "mapping_delta": {
            "retained_road_ids": retained,
            "changed": changed,
            "newly_mappable_road_ids": newly_mappable,
            "no_longer_mappable_road_ids": no_longer_mappable,
        },
        "authorization": dict(contract["authorization"]),
    }
    result["semantic_sha256"] = canonical_sha256(semantic_identity_basis(result))

    if contract["status"] == "LOCKED_IMPACT_MEASUREMENT_EVIDENCE_ONLY":
        locked = contract["locked_evidence"]
        assert result["semantic_sha256"] == locked["stable_semantic_sha256"]
        assert result["accounting"] == locked["accounting"]

    Path(args.output).write_text(json.dumps(result, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8")
    print(
        "OSM_ROAD_FRAME_CORRECTION_IMPACT_MEASURED "
        f"unique={len(candidate_rows)} multicell={len(multicell_rows)} "
        f"changed={len(changed)} new={len(newly_mappable)} lost={len(no_longer_mappable)} "
        f"semantic={result['semantic_sha256']} locked={contract['status'].startswith('LOCKED_')}"
    )


if __name__ == "__main__":
    main()
