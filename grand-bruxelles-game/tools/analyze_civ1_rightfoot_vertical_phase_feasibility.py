#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,math
from pathlib import Path
SCHEMA='grand-bruxelles-civ1-rightfoot-vertical-phase-feasibility-v1'; SAMPLE_COUNT=121; CYCLE=120; MATERIAL=12
SHIFTS=list(range(-60,61))
def vec(v,label):
    if not isinstance(v,list) or len(v)!=3: raise ValueError(f'invalid {label}')
    out=[float(x) for x in v]
    if not all(math.isfinite(x) for x in out): raise ValueError(f'non-finite {label}')
    return out
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def bone(s,b,side):
    try:return s['bones'][b][side]
    except (KeyError,TypeError) as e: raise ValueError(f'missing {b} {side}') from e
def foot_rel(s,side):
    f=vec(bone(s,'RightFoot',side).get('model_origin'),f'RightFoot {side} origin')
    h=vec(bone(s,'Hips',side).get('model_origin'),f'Hips {side} origin')
    return sub(f,h)
def circ(t,s):
    d=t-s
    while d>CYCLE//2:d-=CYCLE
    while d<-CYCLE//2:d+=CYCLE
    return d
def minidx(seq): return min(range(CYCLE),key=lambda i:seq[i][1])
def support(seq,c): return [seq[(c+d)%CYCLE] for d in (-2,-1,0,1,2)]
def vr(seq): return max(p[1] for p in seq)-min(p[1] for p in seq)
def ht(seq): return sum(math.hypot(seq[i][0]-seq[i-1][0],seq[i][2]-seq[i-1][2]) for i in range(1,len(seq)))
def shifted_vertical(base,shift): return [[base[i][0],base[(i+shift)%CYCLE][1],base[i][2]] for i in range(CYCLE)]
def analyze(p):
    if p.get('rotation_enabled') is not True or p.get('position_enabled') is not False or p.get('scale_enabled') is not False: raise ValueError('rotation-only probe required')
    samples=p.get('model_space_samples')
    if not isinstance(samples,list) or len(samples)!=SAMPLE_COUNT: raise ValueError('expected 121 model_space_samples')
    for i,s in enumerate(samples):
        if s.get('sample_index')!=i: raise ValueError('sample index drift')
    src=[foot_rel(samples[i],'source') for i in range(CYCLE)]; base=[foot_rel(samples[i],'target') for i in range(CYCLE)]
    si=minidx(src); bi=minidx(base); bp=circ(bi,si); bs=support(base,si); bv=vr(bs); bh=ht(bs); rows=[]
    for shift in SHIFTS:
        seq=shifted_vertical(base,shift); phase=circ(minidx(seq),si); sup=support(seq,si); vertical=vr(sup); horizontal=ht(sup)
        horizontal_exact=abs(horizontal-bh)<=1e-12; phase_ok=abs(phase)<abs(bp) and abs(phase)<=MATERIAL; vok=vertical<=bv+1e-9
        rows.append({'vertical_shift_samples':shift,'phase_delta_samples':phase,'vertical_range_m':vertical,'horizontal_travel_m':horizontal,'horizontal_preserved_exactly':horizontal_exact,'phase_gate_pass':phase_ok,'vertical_no_regression':vok,'viable':phase_ok and vok and horizontal_exact})
    viable=[r for r in rows if r['viable']]; best=min(rows,key=lambda r:(0 if r['viable'] else 1,abs(r['phase_delta_samples']),max(0,r['vertical_range_m']-bv),abs(r['vertical_shift_samples'])))
    return {'schema':SCHEMA,'diagnostic_only':True,'runtime_authorized':False,'visual_approval_claimed':False,'grounding_verified':False,'feasibility_oracle_only':True,'production_candidate':False,'source_vertical_min_sample':si,'baseline_vertical_min_sample':bi,'baseline_phase_delta_samples':bp,'baseline_vertical_range_m':bv,'baseline_horizontal_travel_m':bh,'tested_shift_count':len(rows),'viable_shift_count':len(viable),'viable_shifts_samples':[r['vertical_shift_samples'] for r in viable],'best':best,'rows':rows,'family_feasible':bool(viable),'verdict':'VERTICAL_PHASE_FEASIBLE_WITH_HORIZONTAL_FROZEN' if viable else 'VERTICAL_PHASE_NOT_FEASIBLE_WITH_HORIZONTAL_FROZEN'}
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('native_json'); ap.add_argument('output_json'); a=ap.parse_args(); r=analyze(json.loads(Path(a.native_json).read_text())); Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n'); b=r['best']; print('CIV1_RIGHTFOOT_VERTICAL_PHASE_FEASIBILITY_OK '+f"baseline_phase={r['baseline_phase_delta_samples']} viable={r['viable_shift_count']}/{r['tested_shift_count']} best_shift={b['vertical_shift_samples']} best_phase={b['phase_delta_samples']} vertical={r['baseline_vertical_range_m']:.6f}->{b['vertical_range_m']:.6f} horizontal={r['baseline_horizontal_travel_m']:.6f}->{b['horizontal_travel_m']:.6f} verdict={r['verdict']}")
if __name__=='__main__': main()
