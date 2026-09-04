#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,math
from pathlib import Path

SCHEMA='grand-bruxelles-civ1-lowerleg-basis-sweep-v1'
SAMPLE_COUNT=121
CYCLE=120
MATERIAL=12


def vec(v,label):
    if not isinstance(v,list) or len(v)!=3: raise ValueError(f'invalid {label}')
    out=[float(x) for x in v]
    if not all(math.isfinite(x) for x in out): raise ValueError(f'non-finite {label}')
    return out


def quat(v,label):
    if not isinstance(v,list) or len(v)!=4: raise ValueError(f'invalid {label}')
    q=[float(x) for x in v]
    if not all(math.isfinite(x) for x in q): raise ValueError(f'non-finite {label}')
    n=math.sqrt(sum(x*x for x in q))
    if n<=1e-12: raise ValueError(f'degenerate {label}')
    return [x/n for x in q]


def mat(q):
    x,y,z,w=q
    return [[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
            [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
            [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]


def mmul(a,b): return [[sum(a[r][k]*b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]
def mul(m,v): return [sum(m[r][c]*v[c] for c in range(3)) for r in range(3)]
def tr(m): return [[m[c][r] for c in range(3)] for r in range(3)]
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def add(a,b): return [a[i]+b[i] for i in range(3)]
def norm(v): return math.sqrt(sum(x*x for x in v))

def bone(s,b,side):
    try:return s['bones'][b][side]
    except (KeyError,TypeError) as e: raise ValueError(f'missing {b} {side}') from e


def state(s,side):
    lo=bone(s,'RightLowerLeg',side); ft=bone(s,'RightFoot',side); hips=bone(s,'Hips',side)
    loo=vec(lo.get('model_origin'),f'LowerLeg {side} origin')
    fto=vec(ft.get('model_origin'),f'Foot {side} origin')
    hipso=vec(hips.get('model_origin'),f'Hips {side} origin')
    R=mat(quat(lo.get('model_rotation_xyzw'),f'LowerLeg {side} rotation'))
    link=sub(fto,loo); rest=mul(tr(R),link)
    if norm(sub(mul(R,rest),link))>1e-7: raise ValueError('kinematic closure drift')
    return {'R':R,'rest':rest,'lo':loo,'foot':fto,'hips':hipso}


def mean_rest(states,side):
    vals=[states[side][i]['rest'] for i in range(CYCLE)]
    r=[sum(v[k] for v in vals)/CYCLE for k in range(3)]
    if max(norm(sub(v,r)) for v in vals)>2e-5: raise ValueError(f'{side} rest drift')
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


def candidate_seq(states,rest,anchor):
    corr=mmul(states['source'][anchor]['R'],tr(states['target'][anchor]['R']))
    out=[]
    for i in range(CYCLE):
        R=mmul(corr,states['target'][i]['R'])
        p=add(states['target'][i]['lo'],mul(R,rest))
        out.append(sub(p,states['target'][i]['hips']))
    return out


def analyze(p):
    if p.get('rotation_enabled') is not True or p.get('position_enabled') is not False or p.get('scale_enabled') is not False:
        raise ValueError('rotation-only probe required')
    samples=p.get('model_space_samples')
    if not isinstance(samples,list) or len(samples)!=SAMPLE_COUNT: raise ValueError('expected 121 model_space_samples')
    for i,s in enumerate(samples):
        if s.get('sample_index')!=i: raise ValueError('sample index drift')
    states={side:{i:state(samples[i],side) for i in range(CYCLE)} for side in ('source','target')}
    rest=mean_rest(states,'target')
    src=[sub(states['source'][i]['foot'],states['source'][i]['hips']) for i in range(CYCLE)]
    base=[sub(states['target'][i]['foot'],states['target'][i]['hips']) for i in range(CYCLE)]
    si=minidx(src); bi=minidx(base); bp=circ(bi,si)
    bs=support(base,si); bv=vr(bs); bh=ht(bs)
    rows=[]
    for anchor in range(CYCLE):
        seq=candidate_seq(states,rest,anchor)
        phase=circ(minidx(seq),si); sup=support(seq,si)
        vertical=vr(sup); horizontal=ht(sup)
        phase_ok=abs(phase)<abs(bp) and abs(phase)<=MATERIAL
        vertical_ok=vertical<=bv+1e-9; horizontal_ok=horizontal<=bh+1e-9
        rows.append({'anchor_sample':anchor,'phase_delta_samples':phase,'vertical_range_m':vertical,'horizontal_travel_m':horizontal,'phase_gate_pass':phase_ok,'vertical_no_regression':vertical_ok,'horizontal_no_regression':horizontal_ok,'viable':phase_ok and vertical_ok and horizontal_ok})
    viable=[r for r in rows if r['viable']]
    best=min(rows,key=lambda r:(0 if r['viable'] else 1,abs(r['phase_delta_samples']),max(0,r['horizontal_travel_m']-bh),max(0,r['vertical_range_m']-bv),r['anchor_sample']))
    return {'schema':SCHEMA,'diagnostic_only':True,'runtime_authorized':False,'visual_approval_claimed':False,'grounding_verified':False,'temporal_resampling_used':False,'foot_link_rest_preserved':True,'target_rest_local_m':rest,'source_vertical_min_sample':si,'baseline_vertical_min_sample':bi,'baseline_phase_delta_samples':bp,'material_phase_threshold_samples':MATERIAL,'baseline_vertical_range_m':bv,'baseline_horizontal_travel_m':bh,'tested_anchor_count':len(rows),'viable_anchor_count':len(viable),'viable_anchors':[r['anchor_sample'] for r in viable],'best':best,'rows':rows,'family_viable':bool(viable),'verdict':'AMELIORER_LOWERLEG_STATIC_BASIS_FAMILY' if viable else 'JETER_LOWERLEG_STATIC_BASIS_FAMILY'}


def main():
    ap=argparse.ArgumentParser(); ap.add_argument('native_json'); ap.add_argument('output_json'); a=ap.parse_args()
    r=analyze(json.loads(Path(a.native_json).read_text()))
    Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n')
    b=r['best']
    print('CIV1_LOWERLEG_BASIS_SWEEP_OK '+f"baseline_phase={r['baseline_phase_delta_samples']} viable={r['viable_anchor_count']}/{r['tested_anchor_count']} best_anchor={b['anchor_sample']} best_phase={b['phase_delta_samples']} vertical={r['baseline_vertical_range_m']:.6f}->{b['vertical_range_m']:.6f} horizontal={r['baseline_horizontal_travel_m']:.6f}->{b['horizontal_travel_m']:.6f} verdict={r['verdict']}")


if __name__=='__main__': main()
