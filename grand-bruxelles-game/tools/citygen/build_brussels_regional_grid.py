#!/usr/bin/env python3
"""Build the canonical 500 m target grid for the Brussels-Capital Region.

The source of truth is the official UrbIS Municipalities WFS layer in EPSG:31370.
Cells are aligned globally in Lambert72 and deduplicated across municipality
boundaries. This tool only defines target work cells; it never mutates game runtime.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import unicodedata
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

CRS = "EPSG:31370"
WFS_URL = "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs"
LAYER = "urbisvector:Municipalities"
USER_AGENT = "Grand-Bruxelles-Game/1.0 (+https://github.com/Chatnoir01/Chatnoir01)"
EXPECTED_MUNICIPALITIES = 19


def digest(value: Any) -> str:
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def _slug(value: object) -> str:
    text = unicodedata.normalize("NFKD", str(value))
    text = "".join(c for c in text if not unicodedata.combining(c)).casefold()
    text = re.sub(r"[^a-z0-9]+", "-", text).strip("-")
    return text


def _municipality_id(feature: dict[str, Any], fallback: str) -> str:
    candidates = []
    for value in (feature.get("properties") or {}).values():
        if not isinstance(value, str) or value.startswith("http"):
            continue
        slug = _slug(value)
        if len(slug) >= 3 and any(c.isalpha() for c in slug):
            candidates.append(slug)
    return min(candidates, key=lambda x: (len(x), x)) if candidates else fallback


def fetch_official(output: Path) -> Path:
    params = {
        "service": "WFS", "version": "2.0.0", "request": "GetFeature",
        "typeNames": LAYER, "outputFormat": "application/json", "srsName": CRS,
    }
    req = urllib.request.Request(WFS_URL + "?" + urllib.parse.urlencode(params), headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=90) as response:
        payload = json.loads(response.read().decode("utf-8"))
    if payload.get("type") != "FeatureCollection":
        raise RuntimeError("unexpected UrbIS municipality payload")
    features = payload.get("features") or []
    if len(features) != EXPECTED_MUNICIPALITIES:
        raise RuntimeError(f"expected {EXPECTED_MUNICIPALITIES} official municipalities, got {len(features)}")
    stable = {
        "type": "FeatureCollection",
        "crs": {"type": "name", "properties": {"name": CRS}},
        "source": {"authority": "Paradigm / Brussels-Capital Region", "service": WFS_URL, "layer": LAYER, "crs": CRS},
        "features": [],
    }
    for feature in features:
        f = dict(feature)
        f.pop("id", None)
        stable["features"].append(f)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(stable, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return output


def _rings(geometry: dict[str, Any]) -> list[list[list[tuple[float, float]]]]:
    kind = geometry.get("type")
    coords = geometry.get("coordinates") or []
    raw_polys = [coords] if kind == "Polygon" else coords if kind == "MultiPolygon" else []
    polygons = []
    for raw_poly in raw_polys:
        poly = []
        for raw_ring in raw_poly if isinstance(raw_poly, list) else []:
            ring = []
            for p in raw_ring if isinstance(raw_ring, list) else []:
                if isinstance(p, list) and len(p) >= 2 and all(isinstance(v, (int, float)) for v in p[:2]):
                    point = (float(p[0]), float(p[1]))
                    if not ring or point != ring[-1]:
                        ring.append(point)
            if len(ring) >= 4:
                if ring[0] == ring[-1]:
                    ring.pop()
                if len(ring) >= 3:
                    poly.append(ring)
        if poly:
            polygons.append(poly)
    return polygons


def _point_in_ring(point: tuple[float, float], ring: list[tuple[float, float]]) -> bool:
    x, y = point
    inside = False
    for i, a in enumerate(ring):
        b = ring[(i + 1) % len(ring)]
        ax, ay = a; bx, by = b
        cross = (x-ax)*(by-ay) - (y-ay)*(bx-ax)
        if abs(cross) < 1e-8 and min(ax,bx)-1e-8 <= x <= max(ax,bx)+1e-8 and min(ay,by)-1e-8 <= y <= max(ay,by)+1e-8:
            return True
        if (ay > y) != (by > y):
            hit_x = (bx-ax)*(y-ay)/(by-ay) + ax
            if x < hit_x:
                inside = not inside
    return inside


def _point_in_polygon(point: tuple[float, float], poly: list[list[tuple[float, float]]]) -> bool:
    return bool(poly and _point_in_ring(point, poly[0]) and not any(_point_in_ring(point, hole) for hole in poly[1:]))


def _orient(a, b, c):
    v = (b[1]-a[1])*(c[0]-b[0]) - (b[0]-a[0])*(c[1]-b[1])
    return 0 if abs(v) < 1e-8 else (1 if v > 0 else 2)


def _on(p, a, b):
    return min(a[0],b[0])-1e-8 <= p[0] <= max(a[0],b[0])+1e-8 and min(a[1],b[1])-1e-8 <= p[1] <= max(a[1],b[1])+1e-8


def _segments(a, b, c, d):
    o1,o2,o3,o4 = _orient(a,b,c),_orient(a,b,d),_orient(c,d,a),_orient(c,d,b)
    if o1 != o2 and o3 != o4: return True
    return (o1 == 0 and _on(c,a,b)) or (o2 == 0 and _on(d,a,b)) or (o3 == 0 and _on(a,c,d)) or (o4 == 0 and _on(b,c,d))


def _intersects(bbox: tuple[float,float,float,float], poly: list[list[tuple[float,float]]]) -> bool:
    minx,miny,maxx,maxy = bbox
    points = [p for ring in poly for p in ring]
    if not points: return False
    if max(p[0] for p in points) < minx or min(p[0] for p in points) > maxx or max(p[1] for p in points) < miny or min(p[1] for p in points) > maxy: return False
    if any(minx <= p[0] <= maxx and miny <= p[1] <= maxy for p in points): return True
    corners=[(minx,miny),(maxx,miny),(maxx,maxy),(minx,maxy),((minx+maxx)/2,(miny+maxy)/2)]
    if any(_point_in_polygon(p, poly) for p in corners): return True
    edges=[((minx,miny),(maxx,miny)),((maxx,miny),(maxx,maxy)),((maxx,maxy),(minx,maxy)),((minx,maxy),(minx,miny))]
    for ring in poly:
        for i,a in enumerate(ring):
            b=ring[(i+1)%len(ring)]
            if any(_segments(a,b,c,d) for c,d in edges): return True
    return False


def _cell_id(e: float, n: float, size: float) -> str:
    def token(v):
        return str(int(round(v))) if math.isclose(v, round(v), abs_tol=1e-8) else (f"{v:.3f}".rstrip("0").rstrip(".").replace(".", "p"))
    return f"bxl-e{token(e)}-n{token(n)}-s{token(size)}"


def _load_features(boundary_dir: Path) -> list[tuple[str, dict[str, Any]]]:
    out=[]
    files=sorted(boundary_dir.glob("*.geojson"))
    if not files:
        raise ValueError("no official boundary GeoJSON files found")
    for path in files:
        payload=json.loads(path.read_text(encoding="utf-8"))
        crs=((payload.get("crs") or {}).get("properties") or {}).get("name")
        if crs != CRS:
            raise ValueError(f"boundary must declare {CRS}: {path}")
        for idx, feature in enumerate(payload.get("features") or []):
            polygons=_rings(feature.get("geometry") or {})
            if not polygons: continue
            points=[p for poly in polygons for ring in poly for p in ring]
            if min(min(p) for p in points) < 10000:
                raise ValueError(f"boundary coordinates do not look like {CRS}: {path}")
            out.append((_municipality_id(feature, f"{path.stem}-{idx}"), feature))
    if not out:
        raise ValueError("official boundaries contain no polygon features")
    return out


def build_regional_grid(boundary_dir: Path, cell_size: float = 500.0) -> dict[str, Any]:
    if cell_size <= 0: raise ValueError("cell size must be positive")
    cells: dict[str, dict[str, Any]] = {}
    features=_load_features(boundary_dir)
    municipalities=set()
    for municipality, feature in features:
        municipalities.add(municipality)
        for poly in _rings(feature.get("geometry") or {}):
            points=[p for ring in poly for p in ring]
            start_e=math.floor(min(p[0] for p in points)/cell_size)*cell_size
            start_n=math.floor(min(p[1] for p in points)/cell_size)*cell_size
            end_e=math.ceil(max(p[0] for p in points)/cell_size)*cell_size
            end_n=math.ceil(max(p[1] for p in points)/cell_size)*cell_size
            e=start_e
            while e < end_e:
                n=start_n
                while n < end_n:
                    bbox=(e,n,e+cell_size,n+cell_size)
                    if _intersects(bbox, poly):
                        cid=_cell_id(e,n,cell_size)
                        row=cells.setdefault(cid,{"cell_id":cid,"bbox":[e,n,e+cell_size,n+cell_size],"municipalities":[]})
                        if municipality not in row["municipalities"]: row["municipalities"].append(municipality)
                    n += cell_size
                e += cell_size
    ordered=[]
    for cid in sorted(cells):
        row=cells[cid]; row["municipalities"].sort(); ordered.append(row)
    result={"format":"grand-bruxelles-regional-target-grid-v1","authority":"UrbIS Municipalities official geometry","crs":CRS,"cell_size_m":cell_size,"summary":{"municipality_count":len(municipalities),"cell_count":len(ordered)},"cells":ordered}
    result["grid_digest"]=digest(result)
    return result


def main() -> int:
    ap=argparse.ArgumentParser()
    ap.add_argument("--boundary-dir", type=Path, required=True)
    ap.add_argument("--fetch-official", action="store_true")
    ap.add_argument("--output", type=Path, required=True)
    ap.add_argument("--cell-size", type=float, default=500.0)
    args=ap.parse_args()
    if args.fetch_official:
        fetch_official(args.boundary_dir / "urbis_municipalities.geojson")
    grid=build_regional_grid(args.boundary_dir,args.cell_size)
    if args.fetch_official and grid["summary"]["municipality_count"] != EXPECTED_MUNICIPALITIES:
        raise SystemExit(f"official grid must contain {EXPECTED_MUNICIPALITIES} municipalities")
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(grid,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"BRUSSELS_REGIONAL_GRID_OK municipalities={grid['summary']['municipality_count']} cells={grid['summary']['cell_count']} digest={grid['grid_digest']}")
    return 0

if __name__ == "__main__": raise SystemExit(main())
