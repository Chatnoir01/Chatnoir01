#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

from pyproj import Transformer


def canonical_json(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def segment_bbox_intersects(a, b, bbox):
    """Return True only when segment AB intersects the closed axis-aligned bbox.

    This uses Liang-Barsky clipping rather than comparing segment and cell bounding
    boxes. A bbox-overlap-only test is fail-open for diagonal segments whose extent
    overlaps the cell while the segment itself passes completely outside it.
    """
    minx, miny, maxx, maxy = map(float, bbox)
    x0, y0 = map(float, a)
    x1, y1 = map(float, b)
    assert minx <= maxx and miny <= maxy, "Invalid target bbox"

    dx = x1 - x0
    dy = y1 - y0
    p = (-dx, dx, -dy, dy)
    q = (x0 - minx, maxx - x0, y0 - miny, maxy - y0)
    t0 = 0.0
    t1 = 1.0

    for pi, qi in zip(p, q):
        if pi == 0.0:
            if qi < 0.0:
                return False
            continue
        r = qi / pi
        if pi < 0.0:
            if r > t1:
                return False
            if r > t0:
                t0 = r
        else:
            if r < t0:
                return False
            if r < t1:
                t1 = r
    return t0 <= t1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--contract", required=True)
    ap.add_argument("--raw-overpass", required=True)
    ap.add_argument("--acquired-at", required=True)
    ap.add_argument("--query", required=True)
    ap.add_argument("--endpoint-used", required=True)
    ap.add_argument("--output", required=True)
    args = ap.parse_args()

    contract = json.loads(Path(args.contract).read_text())
    assert contract["schema"] == "grand-bruxelles-osm-road-extension-acquisition-v2"
    assert contract["target"]["crs"] == "EPSG:31370"
    assert contract["source"]["license"] == "ODbL-1.0"
    status = contract["status"]
    assert status in {"MEASUREMENT_PENDING", "LOCKED_SOURCE_ONLY_ARTIFACT"}, f"Unsupported acquisition lifecycle status: {status}"
    if status == "LOCKED_SOURCE_ONLY_ARTIFACT":
        evidence = contract.get("locked_evidence")
        assert isinstance(evidence, dict) and evidence, "Locked phase requires locked_evidence"
        assert isinstance(evidence.get("artifact_id"), int) and evidence["artifact_id"] > 0
        assert isinstance(evidence.get("semantic_sha256"), str) and len(evidence["semantic_sha256"]) == 64
    assert all(v is False for v in contract["authorization"].values())
    endpoints = contract["source"].get("endpoints") or [contract["source"]["endpoint"]]
    assert args.endpoint_used in endpoints, "Acquisition endpoint is not contract-authorized"

    raw_path = Path(args.raw_overpass)
    raw_bytes = raw_path.read_bytes()
    raw = json.loads(raw_bytes)
    elements = raw.get("elements")
    assert isinstance(elements, list) and elements, "Overpass returned no elements"

    nodes = {}
    ways = []
    for el in elements:
        et = el.get("type")
        if et == "node":
            nid = int(el["id"])
            lat = float(el["lat"])
            lon = float(el["lon"])
            assert -90 <= lat <= 90 and -180 <= lon <= 180
            nodes[nid] = (lon, lat)
        elif et == "way" and isinstance(el.get("tags"), dict) and el["tags"].get("highway"):
            refs = [int(v) for v in el.get("nodes", [])]
            if len(refs) >= 2:
                ways.append({"id": int(el["id"]), "nodes": refs, "tags": dict(el["tags"])})

    assert ways, "No highway ways returned"
    referenced = {nid for way in ways for nid in way["nodes"]}
    missing = sorted(referenced - set(nodes))
    assert not missing, f"Missing referenced nodes: {missing[:10]}"

    transformer = Transformer.from_crs("EPSG:4326", "EPSG:31370", always_xy=True)
    bbox = [float(v) for v in contract["target"]["bbox"]]
    intersecting = []
    canonical_ways = []
    point_count = 0
    projected_points = []

    for way in sorted(ways, key=lambda w: w["id"]):
        coords_wgs84 = [nodes[nid] for nid in way["nodes"]]
        coords_l72 = [transformer.transform(lon, lat) for lon, lat in coords_wgs84]
        point_count += len(coords_l72)
        projected_points.extend(coords_l72)
        hits = sum(segment_bbox_intersects(a, b, bbox) for a, b in zip(coords_l72, coords_l72[1:]))
        if hits:
            intersecting.append({"osm_way_id": way["id"], "segment_bbox_hits": hits})
        canonical_ways.append({
            "osm_way_id": way["id"],
            "tags": dict(sorted(way["tags"].items())),
            "nodes": [{"id": nid, "lon": nodes[nid][0], "lat": nodes[nid][1]} for nid in way["nodes"]],
        })

    assert intersecting, "Acquisition does not intersect target Lambert72 cell"
    xs = [p[0] for p in projected_points]
    ys = [p[1] for p in projected_points]
    lambert_bbox = [min(xs), min(ys), max(xs), max(ys)]

    semantic_payload = {"target": contract["target"], "ways": canonical_ways, "intersecting": intersecting}
    semantic_sha = sha256_bytes(canonical_json(semantic_payload))
    measurement = {
        "schema": "grand-bruxelles-osm-road-extension-measurement-v2",
        "campaign_id": contract["campaign_id"],
        "production_base_sha": contract["production_base_sha"],
        "status": "MEASURED_SOURCE_ONLY_UNMERGED",
        "source": {
            "provider": contract["source"]["provider"],
            "endpoint": args.endpoint_used,
            "authorized_endpoints": endpoints,
            "license": contract["source"]["license"],
            "attribution": contract["source"]["attribution"],
            "acquired_at_utc": args.acquired_at,
            "overpass_query": args.query,
            "raw_bytes": len(raw_bytes),
            "raw_sha256": sha256_bytes(raw_bytes),
        },
        "target": contract["target"],
        "accounting": {
            "highway_way_count": len(canonical_ways),
            "referenced_node_count": len(referenced),
            "way_point_count": point_count,
            "target_intersecting_way_count": len(intersecting),
            "target_intersecting_way_ids": [v["osm_way_id"] for v in intersecting],
            "lambert72_bbox": lambert_bbox,
        },
        "predecessor": contract["predecessor"],
        "semantic_sha256": semantic_sha,
        "authorization": contract["authorization"],
    }
    assert all(v is False for v in measurement["authorization"].values())
    if status == "LOCKED_SOURCE_ONLY_ARTIFACT":
        evidence = contract["locked_evidence"]
        assert measurement["semantic_sha256"] == evidence["semantic_sha256"], "Locked semantic digest drift"
        assert measurement["source"]["raw_sha256"] == evidence["raw_sha256"], "Locked raw payload drift"
        assert measurement["source"]["raw_bytes"] == evidence["raw_bytes"], "Locked raw byte count drift"
    Path(args.output).write_text(json.dumps(measurement, ensure_ascii=False, indent=2) + "\n")
    print(f"OSM_ROAD_EXTENSION_MEASURED_SOURCE_ONLY ways={measurement['accounting']['highway_way_count']} intersecting={measurement['accounting']['target_intersecting_way_count']} semantic={semantic_sha} endpoint={args.endpoint_used}")


if __name__ == "__main__":
    main()
