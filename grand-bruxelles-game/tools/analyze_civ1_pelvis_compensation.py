#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,math
from pathlib import Path
SCHEMA='grand-bruxelles-civ1-pelvis-compensation-v1'; N=121; CYCLE=120; MATERIAL=12
SHIFTS=range(-60,61); CAPS_MM=range(0,61,5); GRID_MM=range(-60,61)
def vec(v,label):
    if not isinstance(v,list) or len(v)!=3: raise ValueError(f'invalid {label}')
    out=[float(x) for x in v]
    if not all(math.isfinite(x) for x in out): raise ValueError(f'non-finite {label}')
    return out
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def dist(a,b): return math.sqrt(sum((a[i]-b[i])**2 for i in range(3)))
def bone(s,b,side):
    try:return s['bones'][b][side]
    except (KeyError,TypeError) as e: raise ValueError(f'missing {b} {side}') from e
def origin(s,b,side): return vec(bone(s,b,side).get('model_origin'),f'{b} {side} origin')
def rel(s,b,side): return sub(origin(s,b,side),origin(s,'Hips',side))
def circ(t,s):
    d=t-s
    while d>CYCLE//2:d-=CYCLE
    while d<-CYCLE//2:d+=CYCLE
    return d
def minidx(seq): return min(range(CYCLE),key=lambda i:seq[i][1])
def support(seq,c): return [seq[(c+d)%CYCLE] for d in (-2,-1,0,1,2)]
def vr(seq): return max(p[1] for p in seq)-min(p[1] for p in seq)
def ht(seq): return sum(math.hypot(seq[i][0]-seq[i-1][0],seq[i][2]-seq[i-1][2]) for i in range(1,len(seq)))
def _allowed_dys(samples,seq,cap_mm):
    allowed=[]
    for i,s in enumerate(samples[:CYCLE]):
        hips=origin(s,'Hips','target'); rf=origin(s,'RightFoot','target'); lf=origin(s,'LeftFoot','target')
        rh=origin(s,'RightUpperLeg','target'); rk=origin(s,'RightLowerLeg','target'); lh=origin(s,'LeftUpperLeg','target'); lk=origin(s,'LeftLowerLeg','target')
        rr=dist(rh,rk)+dist(rk,rf); lr=dist(lh,lk)+dist(lk,lf); goal=[rf[0],hips[1]+seq[i][1],rf[2]]
        row=[]
        for mm in GRID_MM:
            if abs(mm)>cap_mm: continue
            dy=mm/1000.0; rh2=[rh[0],rh[1]+dy,rh[2]]; lh2=[lh[0],lh[1]+dy,lh[2]]
            if dist(rh2,goal)<=rr+1e-6 and dist(lh2,lf)<=lr+1e-6: row.append(mm)
        allowed.append(row)
    return allowed
def _smooth_path(allowed,max_step_m):
    if any(not r for r in allowed): return None
    step_mm=max(0,int(math.floor(max_step_m*1000.0+1e-9)))
    costs={mm:(abs(mm),[mm]) for mm in allowed[0]}
    for i in range(1,CYCLE):
        nxt={}
        for cur in allowed[i]:
            choices=[(cost+abs(cur),path+[cur]) for prev,(cost,path) in costs.items() if abs(cur-prev)<=step_mm]
            if choices: nxt[cur]=min(choices,key=lambda x:x[0])
        costs=nxt
        if not costs: return None
    return [x/1000.0 for x in min(costs.values(),key=lambda x:x[0])[1]]
def analyze(p):
    if p.get('rotation_enabled') is not True or p.get('position_enabled') is not False or p.get('scale_enabled') is not False: raise ValueError('rotation-only probe required')
    samples=p.get('model_space_samples')
    if not isinstance(samples,list) or len(samples)!=N: raise ValueError('expected 121 model_space_samples')
    for i,s in enumerate(samples):
        if s.get('sample_index')!=i: raise ValueError('sample index drift')
    for i in range(CYCLE):
        for b in ('Hips','RightUpperLeg','RightLowerLeg','RightFoot','LeftUpperLeg','LeftLowerLeg','LeftFoot'): origin(samples[i],b,'target')
        origin(samples[i],'RightFoot','source'); origin(samples[i],'Hips','source')
    src=[rel(samples[i],'RightFoot','source') for i in range(CYCLE)]; base=[rel(samples[i],'RightFoot','target') for i in range(CYCLE)]
    si=minidx(src); bi=minidx(base); bp=circ(bi,si); bs=support(base,si); bv=vr(bs); bh=ht(bs)
    src_hips_y=[origin(samples[i],'Hips','source')[1] for i in range(CYCLE)]
    source_pelvis_range=max(src_hips_y)-min(src_hips_y)
    source_pelvis_step=max(abs(src_hips_y[i]-src_hips_y[i-1]) for i in range(1,CYCLE))
    rows=[]
    for shift in SHIFTS:
        seq=[[base[i][0],base[(i+shift)%CYCLE][1],base[i][2]] for i in range(CYCLE)]
        phase=circ(minidx(seq),si); sup=support(seq,si); vertical=vr(sup); horizontal=ht(sup)
        phase_ok=abs(phase)<abs(bp) and abs(phase)<=MATERIAL; vok=vertical<=bv+1e-9; hok=horizontal<=bh+1e-12
        for cap_mm in CAPS_MM:
            path=None
            if phase_ok and vok and hok: path=_smooth_path(_allowed_dys(samples,seq,cap_mm),source_pelvis_step)
            reachable=path is not None
            max_abs=max((abs(x) for x in (path or [])),default=0.0)
            step=max((abs(path[i]-path[i-1]) for i in range(1,CYCLE)),default=0.0) if path else 0.0
            pelvis_ok=reachable and max_abs<=source_pelvis_range+1e-12 and step<=source_pelvis_step+1e-12
            viable=phase_ok and vok and hok and pelvis_ok
            rows.append({'vertical_shift_samples':shift,'pelvis_cap_mm':cap_mm,'phase_delta_samples':phase,'vertical_range_m':vertical,'horizontal_travel_m':horizontal,'max_abs_pelvis_delta_m':max_abs,'max_pelvis_step_m':step,'two_leg_reachable':reachable,'pelvis_bounds_pass':pelvis_ok,'phase_gate_pass':phase_ok,'vertical_no_regression':vok,'horizontal_no_regression':hok,'viable':viable})
    viable=[r for r in rows if r['viable']]
    best=min(rows,key=lambda r:(0 if r['viable'] else 1,0 if r['phase_gate_pass'] else 1,abs(r['phase_delta_samples']),0 if r['two_leg_reachable'] else 1,r['max_abs_pelvis_delta_m']))
    return {'schema':SCHEMA,'diagnostic_only':True,'runtime_authorized':False,'visual_approval_claimed':False,'grounding_verified':False,'source_vertical_min_sample':si,'baseline_vertical_min_sample':bi,'baseline_phase_delta_samples':bp,'baseline_vertical_range_m':bv,'baseline_horizontal_travel_m':bh,'source_pelvis_vertical_range_m':source_pelvis_range,'source_pelvis_max_step_m':source_pelvis_step,'tested_candidate_count':len(rows),'viable_candidate_count':len(viable),'best':best,'rows':rows,'verdict':'AMELIORER_BOUNDED_PELVIS_COMPENSATION' if viable else 'JETER_BOUNDED_PELVIS_COMPENSATION_FAMILY'}
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('native_json'); ap.add_argument('output_json'); a=ap.parse_args(); r=analyze(json.loads(Path(a.native_json).read_text())); Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n'); b=r['best']; print('CIV1_PELVIS_COMPENSATION_OK '+f"baseline_phase={r['baseline_phase_delta_samples']} viable={r['viable_candidate_count']}/{r['tested_candidate_count']} best_shift={b['vertical_shift_samples']} cap_mm={b['pelvis_cap_mm']} best_phase={b['phase_delta_samples']} max_pelvis_m={b['max_abs_pelvis_delta_m']:.3f} step_m={b['max_pelvis_step_m']:.3f} verdict={r['verdict']}")
if __name__=='__main__': main()
