#!/usr/bin/env python3
"""Fail-closed Grand-Place UrbIS building -> official address crosswalk.

Evidence-only helper for the phase after complete contour coverage. It does not
assign heritage identities by proximity. An address point is attached to a
LoD2 owner only when the official UrbIS AddressNumbers point falls inside one
and only one official GROUNDSURFACE triangle after the repository's persisted
Lambert72->world transform is applied.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import time
import urllib.parse
import urllib.request
from pathlib import Path

WFS = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
TYPE_NAME = "urbisvector:AddressNumbers"
CRS = "EPSG:31370"
SOURCE_SCHEMA = "grand-bruxelles-urbis-context-mesh-v1"
OUTPUT_SCHEMA = "grand-bruxelles-grand-place-address-crosswalk-v1"
PACKAGE_SHA256 = "cf8449d1a62b0e47aafe6d715ff6a2739f5c48f6d75995f7f418305a5d6cf3d2"
BOUNDARY_EPSILON_M = 0.05
QUERY_MARGIN_M = 5.0


def _read(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


def _source_bbox(data: dict) -> tuple[float, float, float, float]:
    for container in (data.get("evidence", {}), data.get("source", {}), data):
        raw = container.get("source_bbox_xy") or container.get("bbox_xy")
        if isinstance(raw, list) and len(raw) == 4 and all(isinstance(v, (int, float)) for v in raw):
            return tuple(float(v) for v in raw)
    raise ValueError("source_bbox_xy unavailable")


def _world_transform(paving: dict):
    tr = paving["transform"]
    lo = tr["lambert72_origin"]
    wo = tr["world_origin"]
    if len(lo) != 2 or len(wo) != 2:
        raise ValueError("paving Lambert72/world transform invalid")

    def convert(x: float, y: float) -> tuple[float, float]:
        return x - float(lo[0]) + float(wo[0]), -(y - float(lo[1])) + float(wo[1])

    return convert


def _point_in_triangle(px: float, pz: float, tri: list, eps: float) -> bool:
    ax, az = float(tri[0][0]), float(tri[0][2])
    bx, bz = float(tri[1][0]), float(tri[1][2])
    cx, cz = float(tri[2][0]), float(tri[2][2])
    v0x, v0z = cx - ax, cz - az
    v1x, v1z = bx - ax, bz - az
    v2x, v2z = px - ax, pz - az
    den = v0x * v1z - v1x * v0z
    if abs(den) < 1e-12:
        return False
    u = (v2x * v1z - v1x * v2z) / den
    v = (v0x * v2z - v2x * v0z) / den
    # Convert the metre boundary tolerance to a conservative barycentric
    # tolerance using the longest edge; never broadens beyond eps metres.
    edges = (
        math.hypot(bx - ax, bz - az),
        math.hypot(cx - bx, cz - bz),
        math.hypot(ax - cx, az - cz),
    )
    scale = max(max(edges), 1e-9)
    t = eps / scale
    return u >= -t and v >= -t and u + v <= 1.0 + t


def _ground_triangles(data: dict) -> list[list]:
    out = []
    for face in data.get("faces", []):
        if face.get("type") != "GROUNDSURFACE":
            continue
        for tri in face.get("triangles", []):
            if isinstance(tri, list) and len(tri) == 3:
                out.append(tri)
    return out


def _fetch_json(url: str, attempts: int = 4) -> tuple[bytes, dict]:
    error = None
    for attempt in range(attempts):
        try:
            request = urllib.request.Request(url, headers={"User-Agent": "Grand-Bruxelles-Source-QA/1"})
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
            return raw, json.loads(raw)
        except Exception as exc:  # pragma: no cover - network gate
            error = exc
            if attempt + 1 < attempts:
                time.sleep(2 ** attempt)
    raise RuntimeError(f"UrbIS AddressNumbers request failed after {attempts} attempts: {error}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", default="grand-bruxelles-game")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    root = Path(args.repo_root)
    lod2_dir = root / "data/urbis/grand_place_lod2"
    paving_path = root / "data/visual/grand_place_granite_paving.json"
    files = sorted(lod2_dir.glob("*.game.json"), key=lambda p: int(p.name.split(".")[0]))
    if len(files) != 25:
        raise SystemExit(f"expected 25 Grand-Place LoD2 owners, got {len(files)}")

    owners: dict[str, dict] = {}
    bboxes = []
    for path in files:
        owner_id = path.name.split(".")[0]
        data = _read(path)
        if data.get("schema") != SOURCE_SCHEMA:
            raise SystemExit(f"schema mismatch for {owner_id}")
        source = data.get("source", {})
        if source.get("building_2d_id") != f"https://databrussels.be/id/building/{owner_id}":
            raise SystemExit(f"building identity mismatch for {owner_id}")
        if source.get("package_sha256") != PACKAGE_SHA256 or source.get("crs") != CRS:
            raise SystemExit(f"source provenance mismatch for {owner_id}")
        if data.get("runtime_approved") is not False:
            raise SystemExit(f"source owner unexpectedly runtime-approved: {owner_id}")
        ground = _ground_triangles(data)
        if not ground:
            raise SystemExit(f"no official GROUNDSURFACE triangles for {owner_id}")
        owners[owner_id] = {"data": data, "ground": ground}
        bboxes.append(_source_bbox(data))

    minx = min(b[0] for b in bboxes) - QUERY_MARGIN_M
    miny = min(b[1] for b in bboxes) - QUERY_MARGIN_M
    maxx = max(b[2] for b in bboxes) + QUERY_MARGIN_M
    maxy = max(b[3] for b in bboxes) + QUERY_MARGIN_M

    params = {
        "service": "WFS",
        "version": "2.0.0",
        "request": "GetFeature",
        "typeNames": TYPE_NAME,
        "outputFormat": "application/json",
        "srsName": CRS,
        "bbox": f"{minx:.3f},{miny:.3f},{maxx:.3f},{maxy:.3f},{CRS}",
    }
    url = WFS + "?" + urllib.parse.urlencode(params)
    raw, response = _fetch_json(url)
    if response.get("type") != "FeatureCollection":
        raise SystemExit("AddressNumbers response is not a GeoJSON FeatureCollection")

    paving = _read(paving_path)
    if paving.get("source", {}).get("feature_id") != "https://databrussels.be/id/streetsurface/42405":
        raise SystemExit("Grand-Place paving transform source drifted")
    to_world = _world_transform(paving)

    address_rows = []
    owner_to_addresses = {owner_id: [] for owner_id in owners}
    ambiguous = []
    contained_count = 0

    features = response.get("features", [])
    features.sort(key=lambda f: str(f.get("properties", {}).get("INSPIRE_ID", f.get("id", ""))))
    for feature in features:
        geom = feature.get("geometry") or {}
        if geom.get("type") != "Point":
            continue
        coords = geom.get("coordinates") or []
        if len(coords) < 2:
            continue
        sx, sy = float(coords[0]), float(coords[1])
        wx, wz = to_world(sx, sy)
        matches = []
        for owner_id, item in owners.items():
            if any(_point_in_triangle(wx, wz, tri, BOUNDARY_EPSILON_M) for tri in item["ground"]):
                matches.append(owner_id)
        matches.sort(key=int)
        props = feature.get("properties") or {}
        row = {
            "address_id": str(props.get("INSPIRE_ID", feature.get("id", ""))),
            "police_number": props.get("POLICENUM"),
            "street_name_fr": props.get("STRNAMEFRE"),
            "street_name_nl": props.get("STRNAMEDUT"),
            "municipality_fr": props.get("MUNNAMEFRE"),
            "municipality_nl": props.get("MUNNAMEDUT"),
            "source_xy_epsg31370": [sx, sy],
            "world_xz": [wx, wz],
            "containing_owner_ids": matches,
            "status": "exact_unique" if len(matches) == 1 else ("ambiguous" if len(matches) > 1 else "outside"),
        }
        address_rows.append(row)
        if len(matches) == 1:
            contained_count += 1
            owner_to_addresses[matches[0]].append(row["address_id"])
        elif len(matches) > 1:
            ambiguous.append(row["address_id"])

    resolved_owners = []
    unresolved_owners = []
    for owner_id in sorted(owners, key=int):
        ids = sorted(set(owner_to_addresses[owner_id]))
        if ids:
            resolved_owners.append({"building_id": owner_id, "address_ids": ids, "status": "source_containment_only"})
        else:
            unresolved_owners.append(owner_id)

    report = {
        "schema": OUTPUT_SCHEMA,
        "status": "evidence_only",
        "runtime_authorized": False,
        "semantic_identity_authorized": False,
        "method": "official AddressNumbers point contained in exactly one official LoD2 GROUNDSURFACE; no nearest-neighbour fallback",
        "boundary_epsilon_m": BOUNDARY_EPSILON_M,
        "query_margin_m": QUERY_MARGIN_M,
        "source": {
            "provider": "Paradigm / Brussels-Capital Region",
            "wfs": WFS,
            "layer": TYPE_NAME,
            "crs": CRS,
            "query_bbox_epsg31370": [minx, miny, maxx, maxy],
            "response_sha256": hashlib.sha256(raw).hexdigest(),
        },
        "building_source": {
            "owner_count": len(owners),
            "package_sha256": PACKAGE_SHA256,
        },
        "counts": {
            "address_points_returned": len(address_rows),
            "exact_unique_containments": contained_count,
            "resolved_owner_count": len(resolved_owners),
            "unresolved_owner_count": len(unresolved_owners),
            "ambiguous_address_count": len(ambiguous),
        },
        "resolved_owners": resolved_owners,
        "unresolved_owner_ids": unresolved_owners,
        "ambiguous_address_ids": ambiguous,
        "addresses": address_rows,
        "hard_rules": {
            "nearest_neighbour_allowed": False,
            "ambiguous_match_authorizes_identity": False,
            "missing_match_authorizes_identity": False,
            "heritage_name_assignment_in_this_step": False,
        },
    }
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(
        "GRAND_PLACE_ADDRESS_CROSSWALK_OK: "
        f"owners={len(owners)} resolved={len(resolved_owners)} unresolved={len(unresolved_owners)} "
        f"addresses={len(address_rows)} unique={contained_count} ambiguous={len(ambiguous)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
