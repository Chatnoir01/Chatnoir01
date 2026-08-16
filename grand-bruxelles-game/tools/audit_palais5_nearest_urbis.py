#!/usr/bin/env python3
"""Audit the UrbIS geometry around the semantic location of Brussels Expo Palais 5.

OSM way 143816182 is used only to locate the named hall. Paradigm UrbIS remains
the authoritative geometry source. A containing UrbIS polygon is *not* promoted
to a Palais 5 hero footprint merely because it contains the locator: campus-scale
geometry is explicitly flagged for finer authoritative resolution.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

BUILDINGS = Path("data/urbis/laeken_jette/buildings.game.json")
HEIGHTS = Path("data/urbis/laeken_jette/building_heights_dsm.game.json")
OVERRIDES = Path("data/urbis/laeken_jette/building_height_landmark_overrides.game.json")
OUTPUT = Path("data/sources/laeken_jette/palais5_nearest_urbis_audit.json")

PALAIS5_LOCAL_X = -87.23317646887153
PALAIS5_LOCAL_Z = -7056.078922991641
OSM_LAT = 50.89969
OSM_LON = 4.33721
OSM_WAY_ID = 143816182

# Safety gate only: these limits are deliberately broad and are NOT claimed
# architectural dimensions for Palais 5. Their role is to reject a campus/block
# polygon as a single-hall hero footprint. Any rejected candidate must be resolved
# using finer authoritative geometry or a separately documented lawful source.
HERO_SCREEN_MAX_MAJOR_SPAN_M = 500.0
HERO_SCREEN_MAX_MINOR_SPAN_M = 300.0
HERO_SCREEN_MAX_OUTER_AREA_M2 = 100000.0


def ring_points(ring):
    return [(float(p[0]), float(p[1])) for p in ring if isinstance(p, list) and len(p) >= 2]


def point_in_ring(x, z, ring):
    pts = ring_points(ring)
    if len(pts) < 3:
        return False
    inside = False
    xj, zj = pts[-1]
    for xi, zi in pts:
        if ((zi > z) != (zj > z)):
            cross_x = (xj - xi) * (z - zi) / ((zj - zi) + 1e-20) + xi
            if x < cross_x:
                inside = not inside
        xj, zj = xi, zi
    return inside


def point_in_polygon(x, z, polygon):
    if not polygon or not point_in_ring(x, z, polygon[0]):
        return False
    return not any(point_in_ring(x, z, hole) for hole in polygon[1:])


def segment_distance(px, pz, ax, az, bx, bz):
    dx, dz = bx-ax, bz-az
    denom = dx*dx + dz*dz
    if denom <= 1e-12:
        return math.hypot(px-ax, pz-az)
    t = max(0.0, min(1.0, ((px-ax)*dx + (pz-az)*dz) / denom))
    qx, qz = ax+t*dx, az+t*dz
    return math.hypot(px-qx, pz-qz)


def polygon_boundary_distance(x, z, polygon):
    if point_in_polygon(x, z, polygon):
        return 0.0
    best = float("inf")
    for ring in polygon:
        pts = ring_points(ring)
        for i in range(len(pts)-1):
            best = min(best, segment_distance(x, z, *pts[i], *pts[i+1]))
    return best


def polygon_stats(polygon):
    pts = ring_points(polygon[0]) if polygon else []
    if not pts:
        return None
    if pts[0] == pts[-1]:
        pts = pts[:-1]
    xs=[p[0] for p in pts]; zs=[p[1] for p in pts]
    cx=sum(xs)/len(xs); cz=sum(zs)/len(zs)
    centered=[(x-cx,z-cz) for x,z in pts]
    xx=sum(x*x for x,_ in centered)/len(centered)
    zz=sum(z*z for _,z in centered)/len(centered)
    xz=sum(x*z for x,z in centered)/len(centered)
    angle=0.5*math.atan2(2*xz,xx-zz)
    axis=(math.cos(angle), math.sin(angle)); side=(-axis[1],axis[0])
    major=[x*axis[0]+z*axis[1] for x,z in centered]
    minor=[x*side[0]+z*side[1] for x,z in centered]
    area=0.0
    for i in range(len(pts)):
        x1,z1=pts[i]; x2,z2=pts[(i+1)%len(pts)]
        area += x1*z2-x2*z1
    return {
        "centroid_x":cx,"centroid_z":cz,
        "min_x":min(xs),"max_x":max(xs),"min_z":min(zs),"max_z":max(zs),
        "outer_area_m2":abs(area)*0.5,
        "pca_angle_rad":angle,"pca_angle_deg":math.degrees(angle),
        "major_span_m":max(major)-min(major),"minor_span_m":max(minor)-min(minor),
        "locator_inside":point_in_polygon(PALAIS5_LOCAL_X,PALAIS5_LOCAL_Z,polygon),
        "locator_boundary_distance_m":polygon_boundary_distance(PALAIS5_LOCAL_X,PALAIS5_LOCAL_Z,polygon),
        "locator_centroid_distance_m":math.hypot(cx-PALAIS5_LOCAL_X,cz-PALAIS5_LOCAL_Z),
    }


def iter_feature_polygons(geometry):
    kind=geometry.get("type")
    coords=geometry.get("coordinates",[])
    if kind=="Polygon":
        yield 0, coords
    elif kind=="MultiPolygon":
        for index,polygon in enumerate(coords):
            yield index,polygon


def hero_screen(candidate):
    if candidate is None:
        return {
            "passes": False,
            "reason": "no_single_containing_urbis_component",
        }
    failures=[]
    if candidate["major_span_m"] > HERO_SCREEN_MAX_MAJOR_SPAN_M:
        failures.append("major_span_exceeds_single_hall_screen")
    if candidate["minor_span_m"] > HERO_SCREEN_MAX_MINOR_SPAN_M:
        failures.append("minor_span_exceeds_single_hall_screen")
    if candidate["outer_area_m2"] > HERO_SCREEN_MAX_OUTER_AREA_M2:
        failures.append("outer_area_exceeds_single_hall_screen")
    return {
        "passes": not failures,
        "reason": "candidate_requires_finer_authoritative_resolution" if failures else "candidate_passes_broad_scale_screen",
        "failed_checks": failures,
        "screen_limits": {
            "max_major_span_m": HERO_SCREEN_MAX_MAJOR_SPAN_M,
            "max_minor_span_m": HERO_SCREEN_MAX_MINOR_SPAN_M,
            "max_outer_area_m2": HERO_SCREEN_MAX_OUTER_AREA_M2,
            "meaning": "anti-false-positive guard only; not claimed Palais 5 dimensions",
        },
    }


def main() -> int:
    buildings=json.loads(BUILDINGS.read_text(encoding="utf-8"))
    heights=json.loads(HEIGHTS.read_text(encoding="utf-8"))
    overrides=json.loads(OVERRIDES.read_text(encoding="utf-8")) if OVERRIDES.exists() else {"overrides":{}}
    features=buildings.get("features",[]); records=heights.get("records",[])
    if len(features)!=len(records): raise SystemExit("building/height record mismatch")

    feature_candidates=[]
    component_candidates=[]
    for feature_index,(feature,record) in enumerate(zip(features,records)):
        if not isinstance(feature,dict): continue
        props=feature.get("properties") or {}
        feature_area=float(props.get("AREA") or 0.0)
        if feature_area < 300.0: continue
        geometry=feature.get("geometry") or {}
        local_components=[]
        for component_index,polygon in iter_feature_polygons(geometry):
            stats=polygon_stats(polygon)
            if stats is None or stats["locator_boundary_distance_m"]>250.0:
                continue
            component={
                "feature_index":feature_index,
                "component_index":component_index,
                "inspire_id":props.get("INSPIRE_ID"),
                "block_id":props.get("BLOCK_ID"),
                "feature_area_m2":feature_area,
                **{k:round(v,3) if isinstance(v,float) else v for k,v in stats.items()},
            }
            local_components.append(component)
            component_candidates.append(component)
        if local_components:
            inspire=str(props.get("INSPIRE_ID") or "")
            raw_height=record.get("height_m") if isinstance(record,dict) else None
            override=(overrides.get("overrides") or {}).get(inspire)
            effective=(override or {}).get("height_m",raw_height) if isinstance(override,dict) else raw_height
            nearest=min(local_components,key=lambda c:(c["locator_boundary_distance_m"],c["locator_centroid_distance_m"]))
            feature_candidates.append({
                "feature_index":feature_index,"inspire_id":inspire,"block_id":props.get("BLOCK_ID"),
                "feature_area_m2":feature_area,"raw_height_m":raw_height,
                "height_quality":record.get("quality") if isinstance(record,dict) else None,
                "effective_height_m":effective,
                "nearest_component_index":nearest["component_index"],
                "nearest_component_boundary_distance_m":nearest["locator_boundary_distance_m"],
            })

    component_candidates.sort(key=lambda c:(not c["locator_inside"],c["locator_boundary_distance_m"],c["locator_centroid_distance_m"],-c["outer_area_m2"]))
    feature_candidates.sort(key=lambda c:(c["nearest_component_boundary_distance_m"],-c["feature_area_m2"]))
    containing=[c for c in component_candidates if c["locator_inside"]]
    selected=containing[0] if len(containing)==1 else None
    if selected is not None:
        record=records[selected["feature_index"]]
        props=features[selected["feature_index"]].get("properties") or {}
        inspire=str(props.get("INSPIRE_ID") or "")
        override=(overrides.get("overrides") or {}).get(inspire)
        selected["raw_height_m"]=record.get("height_m") if isinstance(record,dict) else None
        selected["height_quality"]=record.get("quality") if isinstance(record,dict) else None
        selected["effective_height_m"]=(override or {}).get("height_m",selected["raw_height_m"]) if isinstance(override,dict) else selected["raw_height_m"]

    screen=hero_screen(selected)
    resolution_status="resolved_to_urbis_component" if screen["passes"] else "needs_finer_authoritative_geometry"
    out={
        "schema":3,
        "semantic_locator":{
            "source":"OpenStreetMap","osm_way_id":OSM_WAY_ID,
            "latitude":OSM_LAT,"longitude":OSM_LON,
            "local_x":PALAIS5_LOCAL_X,"local_z":PALAIS5_LOCAL_Z,
        },
        "geometry_source":"Paradigm UrbIS Buildings WFS",
        "feature_candidate_count":len(feature_candidates),
        "component_candidate_count":len(component_candidates),
        "containing_component_count":len(containing),
        "selected_component_if_unambiguous":selected,
        "hero_footprint_screen":screen,
        "resolution_status":resolution_status,
        "nearest_components":component_candidates[:20],
        "nearby_features":feature_candidates[:12],
        "policy":"OSM supplies identity/location only. A containing UrbIS component is retained as evidence but is not promoted to Palais 5 hero geometry when the broad anti-false-positive scale screen indicates campus/block geometry. Seek finer authoritative geometry or a separately documented lawful source; never invent a footprint.",
    }
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    OUTPUT.write_text(json.dumps(out,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print("PALAIS5_COMPONENT_AUDIT_OK",json.dumps({"containing":len(containing),"resolution_status":resolution_status,"screen":screen},ensure_ascii=False))
    return 0

if __name__=="__main__": raise SystemExit(main())
