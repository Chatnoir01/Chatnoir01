#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,math
from pathlib import Path
SCHEMA='grand-bruxelles-civ1-foot-frame-preserving-map-v1'; WINDOW=(78,79); REF_SAMPLE=78

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
    x,y,z,w=q
    return [[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],[2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],[2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
def _mul(m,v): return [sum(m[r][c]*v[c] for c in range(3)) for r in range(3)]
def _tr(m): return [[m[c][r] for c in range(3)] for r in range(3)]
def _sub(a,b): return [a[i]-b[i] for i in range(3)]
def _norm(v): return math.sqrt(sum(x*x for x in v))
def _scale(v,s): return [x*s for x in v]
def _bone(s,b,side):
    try:return s['bones'][b][side]
    except (KeyError,TypeError) as e: raise ValueError(f'missing {b} {side}') from e

def _state(s,prefix,side):
    lo=_bone(s,prefix+'LowerLeg',side); ft=_bone(s,prefix+'Foot',side)
    lo_o=_vec(lo.get('model_origin'),f'{prefix}LowerLeg {side} origin'); ft_o=_vec(ft.get('model_origin'),f'{prefix}Foot {side} origin')
    R=_mat(_quat(lo.get('model_rotation_xyzw'),f'{prefix}LowerLeg {side} rotation'))
    link=_sub(ft_o,lo_o); rest=_mul(_tr(R),link)
    if _norm(_sub(_mul(R,rest),link))>1e-8: raise ValueError('kinematic closure drift')
    return {'R':R,'rest':rest,'link':link}

def _mean_rest(states,side):
    vals=[states[side][i]['rest'] for i in WINDOW]
    r=[sum(v[k] for v in vals)/len(vals) for k in range(3)]
    if max(_norm(_sub(v,r)) for v in vals)>1e-6: raise ValueError(f'{side} rest drift')
    return r

def _delta_y(states, side, rest):
    ys=[_mul(states[side][i]['R'],rest)[1] for i in WINDOW]
    return ys[1]-ys[0]

def _leg(samples,prefix):
    states={side:{i:_state(samples[i],prefix,side) for i in WINDOW} for side in ('source','target')}
    rs=_mean_rest(states,'source'); rt=_mean_rest(states,'target')
    target_len=_norm(rt)
    if target_len<=1e-9: raise ValueError('degenerate target limb length')
    model_dir=_mul(states['source'][REF_SAMPLE]['R'],rs)
    mapped=_mul(_tr(states['target'][REF_SAMPLE]['R']),model_dir)
    mapped_len=_norm(mapped)
    if mapped_len<=1e-9: raise ValueError('degenerate mapped rest')
    cand=_scale(mapped,target_len/mapped_len)
    if abs(_norm(cand)-target_len)>1e-9: raise ValueError('target length preservation drift')
    src=_delta_y(states,'source',rs); baseline=_delta_y(states,'target',rt); candidate=_delta_y(states,'target',cand)
    return {'reference_sample':REF_SAMPLE,'source_rest_local_m':rs,'target_rest_local_m':rt,'candidate_rest_local_m':cand,'source_length_m':_norm(rs),'target_length_m':target_len,'candidate_length_m':_norm(cand),'source_link_y_delta_m':src,'baseline_target_link_y_delta_m':baseline,'baseline_error_delta_m':baseline-src,'candidate_link_y_delta_m':candidate,'candidate_error_delta_m':candidate-src,'improvement_abs_m':abs(baseline-src)-abs(candidate-src)}

def analyze(p):
    if p.get('rotation_enabled') is not True or p.get('position_enabled') is not False or p.get('scale_enabled') is not False: raise ValueError('rotation-only probe required')
    samples=p.get('model_space_samples')
    if not isinstance(samples,list) or len(samples)<=79: raise ValueError('insufficient model_space_samples')
    for i in WINDOW:
        if samples[i].get('sample_index')!=i: raise ValueError('sample index drift')
    right=_leg(samples,'Right'); left=_leg(samples,'Left')
    if right['improvement_abs_m']<=0: raise ValueError('frame-preserving map did not improve RightFoot transition')
    return {'schema':SCHEMA,'diagnostic_only':True,'window':list(WINDOW),'reference_sample':REF_SAMPLE,'right_foot':right,'left_foot_control':left,'runtime_authorized':False,'grounding_verified':False,'foot_slide_verified':False,'visual_approval_claimed':False,'verdict':'AMELIORER_FRAME_PRESERVING_MAP_TRANSITION_ONLY'}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('native_json');ap.add_argument('output_json');a=ap.parse_args();r=analyze(json.loads(Path(a.native_json).read_text()));Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n')
    q=r['right_foot'];print('CIV1_FOOT_FRAME_PRESERVING_MAP_OK '+f"baseline_mm={q['baseline_error_delta_m']*1000:.3f} candidate_mm={q['candidate_error_delta_m']*1000:.3f} improvement_mm={q['improvement_abs_m']*1000:.3f} target_len_m={q['target_length_m']:.9f}")
if __name__=='__main__':main()
