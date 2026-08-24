#!/usr/bin/env python3
"""Measure official municipality coverage for the locked Grand-Place road cell.

Evidence/preflight only. This tool does not register a cell and cannot authorize
road mapping, runtime mounting, rendering, collision, safe spawn or JOUABLE.
GeoServer transport FIDs and raw response bytes are forensic evidence only; the
semantic lock uses stable official municipality identifiers and spatial results.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from shapely.geometry import box, shape as shapely_shape

WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
WFS_LAYER = "urbisvector:Municipalities"
CRS = "EPSG:31370"
USER_AGENT = "Grand-Bruxelles-Road-Cell-Municipality-Preflight/2.0"
TARGET_CELL_ID = "E148000_N170000"
TARGET_ANCHOR_ID = "grand_place"
EXPECTED_CANDIDATE_SEMANTIC_SHA256 = "88c3ed3e73edddb009f4afa3ea831e7febac2fbcebe763b90eb32954ea8f03e3"
EXPECTED_ROAD_SOURCE_SHA256 = "a96123a6098c2a94dcef2622b6ea099c831f426e1ebfeb28a2edda74675c2493"
CLOSED_RAILS = (
    "registration_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)


def http_get(url: str, timeout: int = 90, retries: int = 4) -> bytes:
    last: Exception | None = None
    for attempt in range(retries):
        request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = response.read()
                if not payload:
                    raise RuntimeError("official municipality WFS returned empty payload")
                return payload
        except (urllib.error.URLError, TimeoutError, RuntimeError) as exc:
            last = exc
            if attempt + 1 < retries:
                time.sleep(min(2 ** (attempt + 1), 8))
    raise RuntimeError(f"municipality WFS download failed: {last}")


def fetch_official_municipalities() -> tuple[dict[str, Any], str, str]:
    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": WFS_LAYER,
        "outputFormat": "application/json",
        "srsName": CRS,
    }
    url = WFS_URL + "?" + urllib.parse.urlencode(params)
    raw = http_get(url)
    raw_digest = hashlib.sha256(raw).hexdigest()
    try:
        payload = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"official municipality WFS is not valid UTF-8 JSON: {exc}") from exc
    if payload.get("type") != "FeatureCollection":
        raise RuntimeError("official municipality WFS is not a FeatureCollection")
    features = payload.get("features")
    if not isinstance(features, list) or len(features) != 19:
        raise RuntimeError(f"expected 19 official municipalities, got {0 if not isinstance(features, list) else len(features)}")
    return payload, url, raw_digest


def _require_closed_rails(node: dict[str, Any], context: str) -> None:
    for key in CLOSED_RAILS:
        if node.get(key) is not False:
            raise RuntimeError(f"{context}: authorization rail {key} must remain false")


def validate_candidate_lock(payload: dict[str, Any]) -> dict[str, Any]:
    if payload.get("schema") != "grand-bruxelles-road-cell-coverage-candidates-v1":
        raise RuntimeError("candidate lock schema drift")
    if payload.get("status") != "DISCOVERED_SOURCE_ONLY":
        raise RuntimeError("candidate lock must remain DISCOVERED_SOURCE_ONLY")
    if payload.get("semantic_sha256") != EXPECTED_CANDIDATE_SEMANTIC_SHA256:
        raise RuntimeError("candidate semantic SHA drift")
    if payload.get("road_source_sha256") != EXPECTED_ROAD_SOURCE_SHA256:
        raise RuntimeError("road source SHA drift")
    if int(payload.get("candidate_cell_count", -1)) != 8:
        raise RuntimeError("candidate cell count drift")
    _require_closed_rails(payload, "candidate lock")

    candidates = payload.get("candidates")
    if not isinstance(candidates, list):
        raise RuntimeError("candidate list missing")
    matches = [candidate for candidate in candidates if candidate.get("grid_cell_id") == TARGET_CELL_ID]
    if len(matches) != 1:
        raise RuntimeError(f"expected exactly one {TARGET_CELL_ID} candidate, got {len(matches)}")
    candidate = matches[0]
    _require_closed_rails(candidate, TARGET_CELL_ID)
    if candidate.get("corridor_anchor_ids") != [TARGET_ANCHOR_ID]:
        raise RuntimeError("Grand-Place anchor identity drift")
    if [float(v) for v in candidate.get("bbox", [])] != [148000.0, 170000.0, 148500.0, 170500.0]:
        raise RuntimeError("Grand-Place candidate bbox drift")
    if int(candidate.get("road_count", -1)) != 2:
        raise RuntimeError("Grand-Place road count drift")
    if [int(value) for value in candidate.get("road_ids", [])] != [13842686, 684214770]:
        raise RuntimeError("Grand-Place road IDs drift")
    if int(candidate.get("point_hits", -1)) != 9 or int(candidate.get("segment_hits", -1)) != 7:
        raise RuntimeError("Grand-Place road hit accounting drift")
    return candidate


def _identity(feature: dict[str, Any]) -> dict[str, Any]:
    props = feature.get("properties") or {}
    scalar = {
        str(key): value
        for key, value in sorted(props.items(), key=lambda item: str(item[0]))
        if value is None or isinstance(value, (str, int, float, bool))
    }
    inspire_id = str(scalar.get("INSPIRE_ID") or "").strip()
    niscode = str(scalar.get("NISCODE") or "").strip()
    transport_feature_id = str(feature.get("id") or "").strip()
    stable_id = inspire_id or (f"NIS:{niscode}" if niscode else transport_feature_id)
    if not stable_id:
        raise RuntimeError("municipality feature has no stable or transport identity")
    return {
        "municipality_id": stable_id,
        "municipality_niscode": niscode or None,
        "transport_feature_id": transport_feature_id or None,
        "properties": scalar,
    }


def analyze_municipality_coverage(cell_bbox: list[float], feature_collection: dict[str, Any]) -> dict[str, Any]:
    if len(cell_bbox) != 4 or not all(math.isfinite(float(value)) for value in cell_bbox):
        raise RuntimeError("invalid candidate bbox")
    min_x, min_y, max_x, max_y = map(float, cell_bbox)
    if not (min_x < max_x and min_y < max_y):
        raise RuntimeError("invalid candidate bbox ordering")
    cell = box(min_x, min_y, max_x, max_y)
    cell_area = float(cell.area)
    if cell_area <= 0.0:
        raise RuntimeError("candidate cell has zero area")

    features = feature_collection.get("features")
    if not isinstance(features, list) or not features:
        raise RuntimeError("municipality FeatureCollection is empty")

    intersections: list[dict[str, Any]] = []
    transport_ids: dict[str, str | None] = {}
    for feature in features:
        geometry_payload = feature.get("geometry")
        if not isinstance(geometry_payload, dict):
            raise RuntimeError("municipality feature missing geometry")
        geometry = shapely_shape(geometry_payload)
        if geometry.is_empty or not geometry.is_valid:
            raise RuntimeError(f"municipality geometry invalid/empty: {feature.get('id')}")
        overlap = geometry.intersection(cell)
        area = float(overlap.area)
        if area <= 1e-6:
            continue
        identity = _identity(feature)
        stable_id = identity["municipality_id"]
        if stable_id in transport_ids:
            raise RuntimeError(f"duplicate municipality stable identity: {stable_id}")
        transport_ids[stable_id] = identity["transport_feature_id"]
        intersections.append(
            {
                "municipality_id": stable_id,
                "properties": identity["properties"],
                "intersection_area_m2": area,
                "coverage_ratio": area / cell_area,
                "covers_entire_cell": bool(geometry.covers(cell)),
            }
        )

    intersections.sort(key=lambda item: (-item["intersection_area_m2"], item["municipality_id"]))
    total_ratio = sum(float(item["coverage_ratio"]) for item in intersections)
    if not intersections:
        status = "HOLD_MUNICIPALITY_UNRESOLVED"
        municipality_id = None
        municipality_niscode = None
        coverage_ratio = 0.0
    elif len(intersections) == 1 and intersections[0]["covers_entire_cell"] and abs(intersections[0]["coverage_ratio"] - 1.0) <= 1e-9:
        status = "MUNICIPALITY_PROVEN_SINGLE"
        municipality_id = intersections[0]["municipality_id"]
        municipality_niscode = str(intersections[0]["properties"].get("NISCODE") or "") or None
        coverage_ratio = float(intersections[0]["coverage_ratio"])
    else:
        status = "HOLD_MUNICIPALITY_BOUNDARY_CELL"
        municipality_id = None
        municipality_niscode = None
        coverage_ratio = max(float(item["coverage_ratio"]) for item in intersections)

    return {
        "status": status,
        "cell_area_m2": cell_area,
        "intersection_coverage_sum": total_ratio,
        "municipality_id": municipality_id,
        "municipality_niscode": municipality_niscode,
        "coverage_ratio": coverage_ratio,
        "intersections": intersections,
        "transport_feature_ids": transport_ids,
        "registration_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }


def _semantic_basis(result: dict[str, Any]) -> dict[str, Any]:
    basis = copy.deepcopy(result)
    basis["municipality_source"].pop("raw_payload_sha256", None)
    basis["municipality_coverage"].pop("transport_feature_ids", None)
    basis.pop("semantic_sha256", None)
    return basis


def run(candidate_path: Path, output_path: Path) -> dict[str, Any]:
    payload = json.loads(candidate_path.read_text(encoding="utf-8"))
    candidate = validate_candidate_lock(payload)
    municipalities, source_url, raw_source_sha256 = fetch_official_municipalities()
    analysis = analyze_municipality_coverage([float(v) for v in candidate["bbox"]], municipalities)
    result = {
        "schema": "grand-bruxelles-road-cell-municipality-preflight-v2",
        "status": analysis["status"],
        "candidate_source": {
            "path": str(candidate_path).replace("\\", "/"),
            "semantic_sha256": EXPECTED_CANDIDATE_SEMANTIC_SHA256,
            "road_source_sha256": EXPECTED_ROAD_SOURCE_SHA256,
        },
        "cell": {
            "grid_cell_id": TARGET_CELL_ID,
            "bbox": [float(v) for v in candidate["bbox"]],
            "anchor_id": TARGET_ANCHOR_ID,
            "road_count": int(candidate["road_count"]),
            "road_ids": [int(v) for v in candidate["road_ids"]],
            "point_hits": int(candidate["point_hits"]),
            "segment_hits": int(candidate["segment_hits"]),
        },
        "municipality_source": {
            "provider": "Paradigm / Brussels-Capital Region",
            "service": "UrbIS vector WFS",
            "layer": WFS_LAYER,
            "crs": CRS,
            "url": source_url,
            "feature_count": len(municipalities["features"]),
            "raw_payload_sha256": raw_source_sha256,
        },
        "municipality_coverage": analysis,
        "registration_authorized": False,
        "road_cell_mapping_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }
    canonical = json.dumps(_semantic_basis(result), ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    result["semantic_sha256"] = hashlib.sha256(canonical).hexdigest()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        "ROAD_CELL_MUNICIPALITY_PREFLIGHT_OK: "
        f"cell={TARGET_CELL_ID} status={result['status']} "
        f"intersections={len(analysis['intersections'])} sha256={result['semantic_sha256']} "
        f"raw_wfs_sha256={raw_source_sha256}"
    )
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    run(args.candidate, args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
