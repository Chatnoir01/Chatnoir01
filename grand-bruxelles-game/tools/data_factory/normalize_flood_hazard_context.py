#!/usr/bin/env python3
"""Normalize official Brussels flood-hazard GeoJSON as indicative environmental context.

The source is modeled hazard, not an observed flood event and not regulatory truth. Geometry
and source properties are preserved without movement, simplification, or automatic gameplay use.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

FORMAT = "grand-bruxelles-flood-hazard-context-v1"


def sha256_file(path: Path) -> str:
    h=hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda:f.read(1024*1024),b""):
            h.update(chunk)
    return h.hexdigest()


def load_geojson(path: Path) -> dict[str,Any]:
    value=json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value,dict) or value.get("type")!="FeatureCollection" or not isinstance(value.get("features"),list):
        raise SystemExit(f"flood context gate failed: invalid FeatureCollection {path}")
    return value


def main() -> int:
    parser=argparse.ArgumentParser()
    parser.add_argument("--layer",type=Path,action="append",required=True)
    parser.add_argument("--output",type=Path,required=True)
    parser.add_argument("--license",required=True)
    parser.add_argument("--attribution",default="Source: Bruxelles Environnement / Leefmilieu Brussel")
    parser.add_argument("--crs",default="EPSG:31370")
    parser.add_argument("--min-features",type=int,default=1)
    args=parser.parse_args()

    layers=[]; total=0
    for path in args.layer:
        doc=load_geojson(path)
        features=[]
        for index,feature in enumerate(doc["features"]):
            if not isinstance(feature,dict) or not isinstance(feature.get("geometry"),dict):
                continue
            props=feature.get("properties") if isinstance(feature.get("properties"),dict) else {}
            features.append({
                "source_feature_id":feature.get("id") if feature.get("id") not in (None,"") else f"{path.name}:{index}",
                "geometry":feature["geometry"],
                "source_properties":props,
            })
        total+=len(features)
        layers.append({"file":path.name,"sha256":sha256_file(path),"source_feature_count":len(doc["features"]),"normalized_feature_count":len(features),"features":features})
    if total<args.min_features:
        raise SystemExit(f"flood context gate failed: {total} < {args.min_features}")

    output={
        "format":FORMAT,
        "source":{
            "publisher":"Brussels Environment",
            "dataset_version":"Flood hazard 2025",
            "license":args.license,
            "attribution":args.attribution,
            "crs":args.crs,
            "semantic_status":"indicative modeled hazard; no regulatory value",
            "layers":layers,
        },
        "stats":{"layer_count":len(layers),"feature_count":total},
        "runtime_authorized":False,
        "production_authorized":False,
        "semantic_rules":[
            "Modeled hazard is not an observed flood event.",
            "Absence of mapped hazard does not prove absence of future flooding.",
            "Source geometry and attributes are preserved; no geometry is moved or invented.",
            "This evidence cannot automatically spawn water, damage, closures, missions, or JOUABLE promotion.",
            "Any future gameplay mapping requires a separately reviewed scenario contract."
        ]
    }
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(output,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(f"FLOOD_HAZARD_CONTEXT_OK: {len(layers)} layers, {total} features -> {args.output}")
    return 0


if __name__=="__main__":
    raise SystemExit(main())
