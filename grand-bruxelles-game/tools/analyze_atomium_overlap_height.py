#!/usr/bin/env python3
"""Analyze the exact DSM-DTM distribution for the suspicious Atomium-neighbor footprint.

Requires local DSM/DTM TIFFs for tile 148176. This script is diagnostic only and
writes a compact report with low/high percentiles and 1m histogram bins.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path

import numpy as np
from osgeo import gdal

TARGET_INSPIRE_ID = "https://databrussels.be/id/building/1637983"
ORIGIN_E = 147868.29422791934
ORIGIN_N = 169538.62414926197


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--buildings", type=Path, required=True)
    p.add_argument("--dsm", type=Path, required=True)
    p.add_argument("--dtm", type=Path, required=True)
    p.add_argument("--output", type=Path, required=True)
    return p.parse_args()


def load_raster(path: Path):
    ds = gdal.Open(str(path), gdal.GA_ReadOnly)
    if ds is None:
        raise RuntimeError(path)
    return ds.GetRasterBand(1).ReadAsArray().astype(np.float32), ds.GetGeoTransform()


def point_in_ring(xs: np.ndarray, ys: np.ndarray, ring: list) -> np.ndarray:
    pts = [(float(p[0]) + ORIGIN_E, ORIGIN_N - float(p[1])) for p in ring if isinstance(p, list) and len(p) >= 2]
    inside = np.zeros(xs.shape, dtype=bool)
    xj, yj = pts[-1]
    for xi, yi in pts:
        crossing = ((yi > ys) != (yj > ys)) & (xs < ((xj - xi) * (ys - yi) / ((yj - yi) + 1e-20) + xi))
        inside ^= crossing
        xj, yj = xi, yi
    return inside


def geometry_mask(xs, ys, geometry):
    kind = geometry.get("type")
    coords = geometry.get("coordinates", [])
    polys = [coords] if kind == "Polygon" else coords if kind == "MultiPolygon" else []
    mask = np.zeros(xs.shape, dtype=bool)
    for poly in polys:
        if not poly:
            continue
        m = point_in_ring(xs, ys, poly[0])
        for hole in poly[1:]:
            m &= ~point_in_ring(xs, ys, hole)
        mask |= m
    return mask


def main() -> int:
    args = parse_args()
    doc = json.loads(args.buildings.read_text(encoding="utf-8"))
    target = None
    target_index = None
    for i, feature in enumerate(doc.get("features", [])):
        props = feature.get("properties") or {}
        if props.get("INSPIRE_ID") == TARGET_INSPIRE_ID:
            target = feature
            target_index = i
            break
    if target is None:
        raise SystemExit("target building not found")

    dsm, dsm_gt = load_raster(args.dsm)
    dtm, dtm_gt = load_raster(args.dtm)
    if dsm.shape != dtm.shape or any(abs(a-b) > 1e-9 for a,b in zip(dsm_gt, dtm_gt)):
        raise SystemExit("raster grids differ")

    # Build pixel-centre grid only over target envelope for efficiency.
    coords = list(target["geometry"].get("coordinates", []))
    def iter_pts(v):
        if isinstance(v, list):
            if len(v) >= 2 and isinstance(v[0], (int,float)) and isinstance(v[1], (int,float)):
                yield float(v[0]) + ORIGIN_E, ORIGIN_N - float(v[1])
            else:
                for c in v: yield from iter_pts(c)
    pts = list(iter_pts(coords))
    minx,miny,maxx,maxy = min(p[0] for p in pts),min(p[1] for p in pts),max(p[0] for p in pts),max(p[1] for p in pts)
    px = dsm_gt[1]
    py = abs(dsm_gt[5])
    col0=max(0,int(math.floor((minx-dsm_gt[0])/px))-2); col1=min(dsm.shape[1],int(math.ceil((maxx-dsm_gt[0])/px))+2)
    row0=max(0,int(math.floor((dsm_gt[3]-maxy)/py))-2); row1=min(dsm.shape[0],int(math.ceil((dsm_gt[3]-miny)/py))+2)
    xvals=dsm_gt[0]+(np.arange(col0,col1)+0.5)*px
    yvals=dsm_gt[3]+(np.arange(row0,row1)+0.5)*dsm_gt[5]
    xs,ys=np.meshgrid(xvals,yvals)
    mask=geometry_mask(xs,ys,target["geometry"])
    dsmw=dsm[row0:row1,col0:col1]
    dtmw=dtm[row0:row1,col0:col1]
    diff=dsmw-dtmw
    valid=mask & np.isfinite(diff) & np.isfinite(dsmw) & np.isfinite(dtmw) & (dsmw>-1e20) & (dtmw>-1e20) & (diff>=0) & (diff<=120)
    vals=diff[valid]
    if vals.size < 100:
        raise SystemExit(f"too few target samples: {vals.size}")

    percentiles = {str(q): round(float(np.percentile(vals,q)),3) for q in [1,5,10,15,20,25,30,35,40,45,50,55,60,65,70,75,80,85,90,95,99]}
    lo=max(0,int(math.floor(float(vals.min())))); hi=min(120,int(math.ceil(float(vals.max()))))
    hist=[]
    for start in range(lo,hi):
        count=int(((vals>=start)&(vals<start+1)).sum())
        if count:
            hist.append({"bin_m":[start,start+1],"count":count,"share":round(count/int(vals.size),5)})
    peaks=sorted(hist,key=lambda x:(-x['count'],x['bin_m'][0]))[:12]

    # Lower-mode candidate: strongest histogram bin below 20m, plus samples in a
    # +/-2m band around it. This does not automatically become a runtime override.
    lower_bins=[h for h in hist if h['bin_m'][0] < 20]
    lower_peak=max(lower_bins,key=lambda x:x['count']) if lower_bins else None
    lower_cluster=None
    if lower_peak:
        centre=lower_peak['bin_m'][0]+0.5
        cluster=vals[(vals>=max(0,centre-2.5))&(vals<=centre+2.5)]
        if cluster.size:
            lower_cluster={
                "peak_bin_m":lower_peak['bin_m'],
                "sample_count":int(cluster.size),
                "share":round(int(cluster.size)/int(vals.size),5),
                "median_m":round(float(np.median(cluster)),3),
                "p75_m":round(float(np.percentile(cluster,75)),3),
            }

    out={
        "schema":1,
        "target_inspire_id":TARGET_INSPIRE_ID,
        "feature_index":target_index,
        "source_raster_resolution_m":abs(float(px)),
        "sample_count":int(vals.size),
        "min_m":round(float(vals.min()),3),
        "max_m":round(float(vals.max()),3),
        "mean_m":round(float(vals.mean()),3),
        "percentiles_m":percentiles,
        "top_histogram_peaks_1m":peaks,
        "lower_surface_cluster_candidate":lower_cluster,
        "histogram_1m":hist,
        "decision_policy":"Diagnostic only. Runtime correction requires a clear lower roof cluster and the existing landmark-contamination evidence; no arbitrary manual height is allowed.",
    }
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(out,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    print("ATOMIUM_OVERLAP_DSM_AUDIT_OK",json.dumps({k:out[k] for k in ('sample_count','min_m','max_m','percentiles_m','lower_surface_cluster_candidate')},ensure_ascii=False))
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
