#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,math
from pathlib import Path
SCHEMA='grand-bruxelles-civ1-foot-frame-full-cycle-v1'; SAMPLE_COUNT=121; CYCLE=120; REF=78; MATERIAL=12

def _vec(v,label):
    if not isinstance(v,list) or len(v)!=3: raise ValueError(f'invalid {label}')
    o=[float(x) for x in v]
    if not all(math.isfinite(x) for x in o): raise ValueError(f'non-finite {label}')
    return o

def _quat(v,label):
    if not isinstance(v,list) or len(v)!=4: raise ValueError(f'invalid {label}')
    q=[float(x) for x in v]
    if not all(math.isfinite(x) for x in q): raise ValueError(f'non-finite {label}')
    n=math.sqrt(sum(x*x for x in q))
    if n<=1e-12: raise ValueError(f'degenerate {label}')
    return [x/n for x in q]
def _mat(q):
    x,y,z,w=q; return [[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
def _mul(m,v): return [sum(m[r][c]*v[c] for c in range(3)) for r in range(3)]
def _tr(m): return [[m[c][r] for c in range(3)] for r in range(3)]
def _sub(a,b): return [a[i]-b[i] for i in range(3)]
def _add(a,b): return [a[i]+b[i] for i in range(3)]
def _scale(v,s): return [x*s for x in v]
def _norm(v): return math.sqrt(sum(x*x for x in v))
def _bone(s,b,side):
    try:return s['bones'][b][side]
    except (KeyError,TypeError) as e: raise ValueError(f'missing {b} {side}') from e
def _state(s,prefix,side):
    lo=_bone(s,prefix+'LowerLeg',side); ft=_bone(s,prefix+'Foot',side); hips=_bone(s,'Hips',side)
    lo_o=_vec(lo.get('model_origin'),f'{prefix}LowerLeg {side} origin'); ft_o=_vec(ft.get('model_origin'),f'{prefix}Foot {side} origin'); hips_o=_vec(hips.get('model_origin'),f'Hips {side} origin')
    R=_mat(_quat(lo.get('model_rotation_xyzw'),f'{prefix}LowerLeg {side} rotation')); link=_sub(ft_o,lo_o); rest=_mul(_tr(R),link)
    if _norm(_sub(_mul(R,rest),link))>1e-7: raise ValueError('kinematic closure drift')
    return {'R':R,'rest':rest,'lo':lo_o,'foot':ft_o,'hips':hips_o}
def _mean_rest(states,side):
    vals=[states[side][i]['rest'] for i in range(CYCLE)]; r=[sum(v[k] for v in vals)/CYCLE for k in range(3)]
    if max(_norm(_sub(v,r)) for v in vals)>2e-5: raise ValueError(f'{side} rest drift')
    return r
def _circ(t,s):
    d=t-s
    while d>CYCLE//2:d-=CYCLE
    while d<-CYCLE//2:d+=CYCLE
    return d
def _minidx(seq): return min(range(CYCLE),key=lambda i:seq[i][1])
def _vr(seq): return max(p[1] for p in seq)-min(p[1] for p in seq)
def _ht(seq): return sum(math.hypot(seq[i][0]-seq[i-1][0],seq[i][2]-seq[i-1][2]) for i in range(1,len(seq)))
def _support(seq,center): return [seq[(center+d)%CYCLE] for d in (-2,-1,0,1,2)]
def analyze(p):
    if p.get('rotation_enabled') is not True or p.get('position_enabled') is not False or p.get('scale_enabled') is not False: raise ValueError('rotation-only probe required')
    samples=p.get('model_space_samples')
    if not isinstance(samples,list) or len(samples)!=SAMPLE_COUNT: raise ValueError('expected 121 model_space_samples')
    for i,s in enumerate(samples):
        if s.get('sample_index')!=i: raise ValueError('sample index drift')
    states={side:{i:_state(samples[i],'Right',side) for i in range(CYCLE)} for side in ('source','target')}
    rs=_mean_rest(states,'source'); rt=_mean_rest(states,'target'); target_len=_norm(rt)
    if target_len<=1e-9: raise ValueError('degenerate target limb length')
    model_dir=_mul(states['source'][REF]['R'],rs); mapped=_mul(_tr(states['target'][REF]['R']),model_dir); ml=_norm(mapped)
    if ml<=1e-9: raise ValueError('degenerate mapped rest')
    cand=_scale(mapped,target_len/ml)
    src=[_sub(states['source'][i]['foot'],states['source'][i]['hips']) for i in range(CYCLE)]
    base=[_sub(states['target'][i]['foot'],states['target'][i]['hips']) for i in range(CYCLE)]
    candidate=[_sub(_add(states['target'][i]['lo'],_mul(states['target'][i]['R'],cand)),states['target'][i]['hips']) for i in range(CYCLE)]
    si,bi,ci=_minidx(src),_minidx(base),_minidx(candidate); bp,cp=_circ(bi,si),_circ(ci,si)
    bs=_support(base,si); cs=_support(candidate,si); ss=_support(src,si)
    metrics={'source_vertical_range_m':_vr(ss),'baseline_vertical_range_m':_vr(bs),'candidate_vertical_range_m':_vr(cs),'source_horizontal_travel_m':_ht(ss),'baseline_horizontal_travel_m':_ht(bs),'candidate_horizontal_travel_m':_ht(cs)}
    phase_ok=abs(cp)<abs(bp) and abs(cp)<=MATERIAL; vertical_ok=metrics['candidate_vertical_range_m']<=metrics['baseline_vertical_range_m']+1e-9; horizontal_ok=metrics['candidate_horizontal_travel_m']<=metrics['baseline_horizontal_travel_m']+1e-9
    passed=phase_ok and vertical_ok and horizontal_ok
    return {'schema':SCHEMA,'diagnostic_only':True,'reference_sample':REF,'source_rest_local_m':rs,'target_rest_local_m':rt,'candidate_rest_local_m':cand,'target_length_m':target_len,'candidate_length_m':_norm(cand),'source_vertical_min_sample':si,'baseline_vertical_min_sample':bi,'candidate_vertical_min_sample':ci,'baseline_phase_delta_samples':bp,'candidate_phase_delta_samples':cp,'material_phase_threshold_samples':MATERIAL,'support_samples':[(si+d)%CYCLE for d in (-2,-1,0,1,2)],'metrics':metrics,'phase_gate_pass':phase_ok,'vertical_no_regression':vertical_ok,'horizontal_no_regression':horizontal_ok,'full_cycle_gate_pass':passed,'grounding_verified':False,'foot_slide_verified':bool(horizontal_ok),'runtime_authorized':False,'visual_approval_claimed':False,'verdict':'AMELIORER_FULL_CYCLE_REQUIRES_PLAYER_VIEW' if passed else 'JETER_FRAME_PRESERVING_FULL_CYCLE'}
def main():
    ap=argparse.ArgumentParser();ap.add_argument('native_json');ap.add_argument('output_json');a=ap.parse_args();r=analyze(json.loads(Path(a.native_json).read_text()));Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n');m=r['metrics'];print('CIV1_FOOT_FRAME_FULL_CYCLE_OK '+f"phase={r['baseline_phase_delta_samples']}->{r['candidate_phase_delta_samples']} vertical={m['baseline_vertical_range_m']:.6f}->{m['candidate_vertical_range_m']:.6f} horizontal={m['baseline_horizontal_travel_m']:.6f}->{m['candidate_horizontal_travel_m']:.6f} verdict={r['verdict']}")
if __name__=='__main__':main()
