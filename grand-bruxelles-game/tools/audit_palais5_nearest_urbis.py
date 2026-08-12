#!/usr/bin/env python3
"""Audit large UrbIS building footprints nearest the OSM Palace 5 centre.

Semantic locator: OpenStreetMap way 143816182, centre 50.89969 N, 4.33721 E.
That point is preconverted to the Grand Bruxelles local frame so this diagnostic
has no network dependency. Geometry candidates remain authoritative UrbIS data.
"""

from __future__ import annotations

import json
import math
from pathlib import Path

BUILDINGS = Path("data/urbis/laeken_jette/buildings.game.json")
HEIGHTS = Path("data/urbis/laeken_jette/building_heights_dsm.game.json")
OVERRIDES = Path("data/urbis/laeken_jette/building_height_landmark_overrides.game.json")
OUTPUT = Path("data/sources/laeken_jette/palais5_nearest_urbis_audit.json")

# OSM way 143816182 centre, EPSG:31370 transformed then converted to game-local.
PALAIS5_LOCAL_X = -87.23317646887153
PALAIS5_LOCAL_Z = -7056.078922991641
OSM_LAT = 50.89969
OSM_LON = 4.33721
OSM_WAY_ID = 143816182


def iter_positions(value):
    if isinstance(value, list):
        if len(value) >= 2 and isinstance(value[0], (int, float)) and isinstance(value[1], (int, float)):
            yield float(value[0]), float(value[1])
        else:
            for child in value:
                yield from iter_positions(child)


def stats(feature: dict) -> dict | None:
    pts = list(iter_positions((feature.get("geometry") or {}).get("coordinates", [])))
    if not pts:
        return None
    xs=[p[0] for p in pts]; zs=[p[1] for p in pts]
    cx=sum(xs)/len(xs); cz=sum(zs)/len(zs)
    minx,maxx,minz,maxz=min(xs),max(xs),min(zs),max(zs)
    nearest_x=min(max(PALAIS5_LOCAL_X,minx),maxx)
    nearest_z=min(max(PALAIS5_LOCAL_Z,minz),maxz)
    bbox_distance=math.hypot(nearest_x-PALAIS5_LOCAL_X,nearest_z-PALAIS5_LOCAL_Z)
    centroid_distance=math.hypot(cx-PALAIS5_LOCAL_X,cz-PALAIS5_LOCAL_Z)

    centered=[(x-cx,z-cz) for x,z in pts]
    xx=sum(x*x for x,_ in centered)/len(centered)
    zz=sum(z*z for _,z in centered)/len(centered)
    xz=sum(x*z for x,z in centered)/len(centered)
    angle=0.5*math.atan2(2*xz,xx-zz)
    axis=(math.cos(angle),math.sin(angle)); side=(-axis[1],axis[0])
    major=[x*axis[0]+z*axis[1] for x,z in centered]
    minor=[x*side[0]+z*side[1] for x,z in centered]
    return {
        "centroid_x":cx,"centroid_z":cz,
        "min_x":minx,"max_x":maxx,"min_z":minz,"max_z":maxz,
        "bbox_distance_to_locator_m":bbox_distance,
        "centroid_distance_to_locator_m":centroid_distance,
        "pca_angle_deg":math.degrees(angle),
        "major_span_m":max(major)-min(major),
        "minor_span_m":max(minor)-min(minor),
    }


def main() -> int:
    buildings=json.loads(BUILDINGS.read_text(encoding="utf-8"))
    heights=json.loads(HEIGHTS.read_text(encoding="utf-8"))
    overrides=json.loads(OVERRIDES.read_text(encoding="utf-8")) if OVERRIDES.exists() else {"overrides":{}}
    features=buildings.get("features",[]); records=heights.get("records",[])
    if len(features)!=len(records): raise SystemExit("building/height record mismatch")

    candidates=[]
    for index,(feature,record) in enumerate(zip(features,records)):
        if not isinstance(feature,dict): continue
        props=feature.get("properties") or {}
        area=float(props.get("AREA") or 0.0)
        if area < 300.0: continue
        s=stats(feature)
        if s is None or s["bbox_distance_to_locator_m"] > 250.0: continue
        inspire=str(props.get("INSPIRE_ID") or "")
        raw_height=record.get("height_m") if isinstance(record,dict) else None
        override=(overrides.get("overrides") or {}).get(inspire)
        effective_height=(override or {}).get("height_m",raw_height) if isinstance(override,dict) else raw_height
        candidates.append({
            "feature_index":index,
            "inspire_id":inspire,
            "block_id":props.get("BLOCK_ID"),
            "area_m2":area,
            "raw_height_m":raw_height,
            "height_quality":record.get("quality") if isinstance(record,dict) else None,
            "effective_height_m":effective_height,
            **{k:round(v,3) for k,v in s.items()},
        })
    candidates.sort(key=lambda c:(c["bbox_distance_to_locator_m"],c["centroid_distance_to_locator_m"],-c["area_m2"]))

    # No automatic semantic claim yet. Emit a strong candidate only when the
    # locator lies inside/very near a substantial footprint and its scale is
    # compatible with a major exhibition hall.
    strong=[c for c in candidates if c["bbox_distance_to_locator_m"] <= 12.0 and c["area_m2"] >= 3000.0 and c["major_span_m"] >= 60.0]
    selected=strong[0] if len(strong)==1 else None
    out={
        "schema":1,
        "semantic_locator":{
            "source":"OpenStreetMap",
            "osm_way_id":OSM_WAY_ID,
            "latitude":OSM_LAT,"longitude":OSM_LON,
            "local_x":PALAIS5_LOCAL_X,"local_z":PALAIS5_LOCAL_Z,
        },
        "geometry_source":"Paradigm UrbIS Buildings WFS",
        "candidate_count":len(candidates),
        "nearest_candidates":candidates[:20],
        "strong_candidate_count":len(strong),
        "selected_if_unambiguous":selected,
        "policy":"OSM supplies identity/location only. A hero model may use an UrbIS footprint only when this audit yields one unambiguous major-hall candidate; otherwise keep investigating rather than guessing.",
    }
    OUTPUT.parent.mkdir(parents=True,exist_ok=True)
    OUTPUT.write_text(json.dumps(out,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print("PALAIS5_NEAREST_URBIS_AUDIT_OK",json.dumps({"candidates":len(candidates),"strong":len(strong),"selected":selected},ensure_ascii=False))
    return 0

if __name__=="__main__": raise SystemExit(main())
