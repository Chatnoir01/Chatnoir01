#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,math
from pathlib import Path
SCHEMA='grand-bruxelles-civ1-lowerleg-local-dynamic-sweep-v1'; SAMPLE_COUNT=121; CYCLE=120; MATERIAL=12
CAPS=[round(x*0.25,2) for x in range(1,81)]
def vec(v,label):
    if not isinstance(v,list) or len(v)!=3: raise ValueError(f'invalid {label}')
    o=[float(x) for x in v]
    if not all(math.isfinite(x) for x in o): raise ValueError(f'non-finite {label}')
    return o
def quat(v,label):
    if not isinstance(v,list) or len(v)!=4: raise ValueError(f'invalid {label}')
    q=[float(x) for x in v]
    if not all(math.isfinite(x) for x in q): raise ValueError(f'non-finite {label}')
    n=math.sqrt(sum(x*x for x in q))
    if n<=1e-12: raise ValueError(f'degenerate {label}')
    return [x/n for x in q]
def mat(q):
    x,y,z,w=q
    return [[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
def mmul(a,b): return [[sum(a[r][k]*b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]
def mul(m,v): return [sum(m[r][c]*v[c] for c in range(3)) for r in range(3)]
def tr(m): return [[m[c][r] for c in range(3)] for r in range(3)]
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def add(a,b): return [a[i]+b[i] for i in range(3)]
def norm(v): return math.sqrt(sum(x*x for x in v))
def eye(): return [[1.,0.,0.],[0.,1.,0.],[0.,0.,1.]]
def axis_angle(m):
    c=max(-1.,min(1.,(m[0][0]+m[1][1]+m[2][2]-1.)/2.)); a=math.acos(c)
    if a<1e-10: return ([1.,0.,0.],0.)
    s=2.*math.sin(a)
    if abs(s)<1e-8: raise ValueError('near-pi local delta unsupported')
    axis=[(m[2][1]-m[1][2])/s,(m[0][2]-m[2][0])/s,(m[1][0]-m[0][1])/s]
    n=norm(axis)
    if n<=1e-10: raise ValueError('degenerate local delta axis')
    return ([x/n for x in axis],a)
def rot(axis,a):
    x,y,z=axis; c=math.cos(a); s=math.sin(a); t=1-c
    return [[t*x*x+c,t*x*y-s*z,t*x*z+s*y],[t*x*y+s*z,t*y*y+c,t*y*z-s*x],[t*x*z-s*y,t*y*z+s*x,t*z*z+c]]
def limited_delta(source_local,target_local,cap_deg):
    d=mmul(source_local,tr(target_local)); axis,a=axis_angle(d); cap=math.radians(float(cap_deg))
    return eye() if a==0 else rot(axis,min(a,cap))
def bone(s,b,side):
    try:return s['bones'][b][side]
    except (KeyError,TypeError) as e: raise ValueError(f'missing {b} {side}') from e
def state(s,side):
    up=bone(s,'RightUpperLeg',side); lo=bone(s,'RightLowerLeg',side); ft=bone(s,'RightFoot',side); hips=bone(s,'Hips',side)
    UR=mat(quat(up.get('model_rotation_xyzw'),f'UpperLeg {side} rotation')); LR=mat(quat(lo.get('model_rotation_xyzw'),f'LowerLeg {side} rotation'))
    loo=vec(lo.get('model_origin'),f'LowerLeg {side} origin'); fto=vec(ft.get('model_origin'),f'Foot {side} origin'); ho=vec(hips.get('model_origin'),f'Hips {side} origin')
    local=mmul(tr(UR),LR); link=sub(fto,loo); rest=mul(tr(LR),link)
    if norm(sub(mul(LR,rest),link))>1e-7: raise ValueError('kinematic closure drift')
    return {'UR':UR,'local':local,'rest':rest,'lo':loo,'foot':fto,'hips':ho}
def mean_rest(states):
    vals=[states['target'][i]['rest'] for i in range(CYCLE)]; r=[sum(v[k] for v in vals)/CYCLE for k in range(3)]
    if max(norm(sub(v,r)) for v in vals)>2e-5: raise ValueError('target rest drift')
    return r
def circ(t,s):
    d=t-s
    while d>CYCLE//2:d-=CYCLE
    while d<-CYCLE//2:d+=CYCLE
    return d
def minidx(seq): return min(range(CYCLE),key=lambda i:seq[i][1])
def support(seq,c): return [seq[(c+d)%CYCLE] for d in (-2,-1,0,1,2)]
def vr(seq): return max(p[1] for p in seq)-min(p[1] for p in seq)
def ht(seq): return sum(math.hypot(seq[i][0]-seq[i-1][0],seq[i][2]-seq[i-1][2]) for i in range(1,len(seq)))
def candidate_seq(states,rest,cap):
    out=[]
    for i in range(CYCLE):
        corr=limited_delta(states['source'][i]['local'],states['target'][i]['local'],cap)
        local=mmul(corr,states['target'][i]['local']); LR=mmul(states['target'][i]['UR'],local)
        p=add(states['target'][i]['lo'],mul(LR,rest)); out.append(sub(p,states['target'][i]['hips']))
    return out
def analyze(p):
    if p.get('rotation_enabled') is not True or p.get('position_enabled') is not False or p.get('scale_enabled') is not False: raise ValueError('rotation-only probe required')
    samples=p.get('model_space_samples')
    if not isinstance(samples,list) or len(samples)!=SAMPLE_COUNT: raise ValueError('expected 121 model_space_samples')
    for i,s in enumerate(samples):
        if s.get('sample_index')!=i: raise ValueError('sample index drift')
    states={side:{i:state(samples[i],side) for i in range(CYCLE)} for side in ('source','target')}; rest=mean_rest(states)
    src=[sub(states['source'][i]['foot'],states['source'][i]['hips']) for i in range(CYCLE)]; base=[sub(states['target'][i]['foot'],states['target'][i]['hips']) for i in range(CYCLE)]
    si=minidx(src); bi=minidx(base); bp=circ(bi,si); bs=support(base,si); bv=vr(bs); bh=ht(bs); rows=[]
    for cap in CAPS:
        seq=candidate_seq(states,rest,cap); phase=circ(minidx(seq),si); sup=support(seq,si); vertical=vr(sup); horizontal=ht(sup)
        phase_ok=abs(phase)<abs(bp) and abs(phase)<=MATERIAL; vok=vertical<=bv+1e-9; hok=horizontal<=bh+1e-9
        rows.append({'cap_degrees':cap,'phase_delta_samples':phase,'vertical_range_m':vertical,'horizontal_travel_m':horizontal,'phase_gate_pass':phase_ok,'vertical_no_regression':vok,'horizontal_no_regression':hok,'viable':phase_ok and vok and hok})
    viable=[r for r in rows if r['viable']]; best=min(rows,key=lambda r:(0 if r['viable'] else 1,abs(r['phase_delta_samples']),max(0,r['horizontal_travel_m']-bh),max(0,r['vertical_range_m']-bv),r['cap_degrees']))
    return {'schema':SCHEMA,'diagnostic_only':True,'runtime_authorized':False,'visual_approval_claimed':False,'grounding_verified':False,'temporal_resampling_used':False,'foot_link_rest_preserved':True,'correction_space':'RightUpperLeg-local/bone-space time-varying bounded delta','source_vertical_min_sample':si,'baseline_vertical_min_sample':bi,'baseline_phase_delta_samples':bp,'baseline_vertical_range_m':bv,'baseline_horizontal_travel_m':bh,'tested_cap_count':len(rows),'viable_cap_count':len(viable),'viable_caps_degrees':[r['cap_degrees'] for r in viable],'best':best,'rows':rows,'family_viable':bool(viable),'verdict':'AMELIORER_LOWERLEG_LOCAL_DYNAMIC_FAMILY' if viable else 'JETER_LOWERLEG_LOCAL_DYNAMIC_FAMILY'}
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('native_json'); ap.add_argument('output_json'); a=ap.parse_args(); r=analyze(json.loads(Path(a.native_json).read_text())); Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n'); b=r['best']; print('CIV1_LOWERLEG_LOCAL_DYNAMIC_SWEEP_OK '+f"baseline_phase={r['baseline_phase_delta_samples']} viable={r['viable_cap_count']}/{r['tested_cap_count']} best_cap_deg={b['cap_degrees']:.2f} best_phase={b['phase_delta_samples']} vertical={r['baseline_vertical_range_m']:.6f}->{b['vertical_range_m']:.6f} horizontal={r['baseline_horizontal_travel_m']:.6f}->{b['horizontal_travel_m']:.6f} verdict={r['verdict']}")
if __name__=='__main__': main()
