#!/usr/bin/env python3
from __future__ import annotations

import argparse, json, math, statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SIDEWALKS = ROOT / "data/urbis/bourse_official_sidewalks.game.json"
SPACING = 0.10


def dist_point_seg(p,a,b):
    vx,vy=b[0]-a[0],b[1]-a[1]; wx,wy=p[0]-a[0],p[1]-a[1]
    vv=vx*vx+vy*vy
    if vv <= 1e-18: return math.hypot(wx,wy)
    t=max(0.0,min(1.0,(wx*vx+wy*vy)/vv)); q=(a[0]+t*vx,a[1]+t*vy)
    return math.hypot(p[0]-q[0],p[1]-q[1])


def min_boundary_dist(p,rings):
    return min(dist_point_seg(p,ring[i],ring[i+1]) for ring in rings for i in range(len(ring)-1))


def samples(lines):
    out=[]
    for line in lines:
        for i in range(len(line)-1):
            a,b=line[i],line[i+1]; length=math.hypot(b[0]-a[0],b[1]-a[1])
            n=max(1,int(math.ceil(length/SPACING)))
            for k in range(n):
                t=(k+0.5)/n; out.append([a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1])])
    return out


def percentile(values,q):
    if not values: return None
    s=sorted(values); pos=(len(s)-1)*q; lo=int(math.floor(pos)); hi=int(math.ceil(pos))
    if lo==hi: return s[lo]
    return s[lo]*(hi-pos)+s[hi]*(pos-lo)


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('--probe',type=Path,required=True); ap.add_argument('--output',type=Path,required=True); a=ap.parse_args()
    probe=json.loads(a.probe.read_text()); sw=json.loads(SIDEWALKS.read_text())
    ring_by_id={str(x['source_id']):x['source_rings_epsg31370'][0] for x in sw.get('sidewalks',[]) if x.get('source_rings_epsg31370')}
    metrics=[]; all_d=[]
    for f in probe.get('sidewalk_intersecting_target_features',[]):
        ids=f.get('intersects_sidewalk_source_ids',[]); rings=[ring_by_id[x] for x in ids if x in ring_by_id]
        pts=samples(f.get('source_lines_epsg31370',[])); ds=[min_boundary_dist(p,rings) for p in pts] if rings else []
        all_d.extend(ds)
        metrics.append({
            'feature_id':f.get('feature_id'),'topo_types':f.get('target_topo_types'),'sidewalk_ids':ids,
            'sample_spacing_m':SPACING,'sample_count':len(ds),
            'distance_to_committed_sidewalk_boundary_m':{
                'min':min(ds) if ds else None,'median':statistics.median(ds) if ds else None,'p95':percentile(ds,.95),'max':max(ds) if ds else None,
            },
            'sample_ratio_within_0_02m':sum(x<=.02 for x in ds)/len(ds) if ds else 0.0,
            'sample_ratio_within_0_05m':sum(x<=.05 for x in ds)/len(ds) if ds else 0.0,
            'sample_ratio_within_0_10m':sum(x<=.10 for x in ds)/len(ds) if ds else 0.0,
            'sample_ratio_within_0_25m':sum(x<=.25 for x in ds)/len(ds) if ds else 0.0,
            'estimated_boundary_overlap_length_within_0_10m_m':sum(x<=.10 for x in ds)*SPACING,
        })
    out={
        'schema':'grand-bruxelles-bourse-a1-curb-boundary-overlap-v1','probe_schema':probe.get('schema'),
        'accepted_feature_count':len(metrics),'sample_spacing_m':SPACING,'feature_metrics':metrics,
        'aggregate':{
            'sample_count':len(all_d),'median_distance_m':statistics.median(all_d) if all_d else None,'p95_distance_m':percentile(all_d,.95),
            'sample_ratio_within_0_02m':sum(x<=.02 for x in all_d)/len(all_d) if all_d else 0.0,
            'sample_ratio_within_0_05m':sum(x<=.05 for x in all_d)/len(all_d) if all_d else 0.0,
            'sample_ratio_within_0_10m':sum(x<=.10 for x in all_d)/len(all_d) if all_d else 0.0,
            'estimated_boundary_overlap_length_within_0_10m_m':sum(x<=.10 for x in all_d)*SPACING,
        },
        'interpretation_guard':'distance measures coincidence with already-shipped sidewalk polygon boundaries only; it does not prove curb height or visual impact',
        'physical_curb_height_supported':False,'vertical_extrusion_allowed':False,'runtime_approved':False,'realism_complete':False,
    }
    a.output.parent.mkdir(parents=True,exist_ok=True); a.output.write_text(json.dumps(out,indent=2)+'\n')
    ag=out['aggregate']; print('BOURSE_A1_CURB_BOUNDARY_OVERLAP',f"features={len(metrics)}",f"samples={ag['sample_count']}",f"median_m={ag['median_distance_m']:.4f}",f"p95_m={ag['p95_distance_m']:.4f}",f"within_0.10={ag['sample_ratio_within_0_10m']:.4f}",f"overlap_m={ag['estimated_boundary_overlap_length_within_0_10m_m']:.1f}")
    return 0 if metrics else 1

if __name__=='__main__': raise SystemExit(main())
