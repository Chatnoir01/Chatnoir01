#!/usr/bin/env python3
from __future__ import annotations
import argparse, importlib.util, json, math
from pathlib import Path
CYCLE=120
EPS=1e-8

def load_previous(path:str):
    spec=importlib.util.spec_from_file_location('civ1_recon',path)
    if spec is None or spec.loader is None: raise ValueError('cannot load reconstruction module')
    m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def qfinite_unit(q):
    return isinstance(q,list) and len(q)==4 and all(math.isfinite(float(x)) for x in q) and abs(math.sqrt(sum(float(x)*float(x) for x in q))-1.0)<=1e-6

def rejected(summary, reason):
    return {
        'schema':'grand-bruxelles-civ1-skeleton-applyability-v2',
        'diagnostic_only':True,
        'runtime_authorized':False,
        'visual_approval_claimed':False,
        'source_reconstruction':summary,
        'frame_count':0,
        'frames':[],
        'rejection_reason':reason,
        'verdict':'JETER_SKELETON_APPLYABILITY',
    }

def analyze(payload, previous_module):
    summary=previous_module.analyze(payload)
    if summary.get('verdict')!='AMELIORER_BILATERAL_RECONSTRUCTION' or not summary.get('joint_continuity_pass'):
        return rejected(summary,'source reconstruction is not applyable')
    samples=payload['model_space_samples']; shift=int(summary['candidate']['vertical_shift_samples'])
    src=[previous_module.rel(samples[i],'RightFoot','source') for i in range(CYCLE)]
    base=[previous_module.rel(samples[i],'RightFoot') for i in range(CYCLE)]
    si=previous_module.minidx(src)
    seq,_=previous_module.contact_gate(base,si,summary['baseline_phase_delta_samples'],summary['baseline_vertical_range_m'],summary['baseline_horizontal_travel_m'],shift)
    used,pathmm=previous_module.minimal_path(samples,seq,int(summary['candidate']['max_used_pelvis_mm']),max(1,int(math.floor(summary['source_pelvis_max_step_m']*1000.0+1e-9))))
    if pathmm is None or used!=int(summary['candidate']['max_used_pelvis_mm']):
        return rejected(summary,'candidate path drift')
    frames=[]; max_qangle=0.0
    for i,s in enumerate(samples[:CYCLE]):
        dy=pathmm[i]/1000.0
        hips=previous_module.origin(s,'Hips'); rf=previous_module.origin(s,'RightFoot'); lf=previous_module.origin(s,'LeftFoot')
        rh=previous_module.origin(s,'RightUpperLeg'); rk=previous_module.origin(s,'RightLowerLeg'); lh=previous_module.origin(s,'LeftUpperLeg'); lk=previous_module.origin(s,'LeftLowerLeg')
        goal=[rf[0],hips[1]+seq[i][1],rf[2]]
        rs=previous_module.solve_two_bone([rh[0],rh[1]+dy,rh[2]],rk,rf,goal)
        ls=previous_module.solve_two_bone([lh[0],lh[1]+dy,lh[2]],lk,lf,lf)
        ru=previous_module.quat_from_to(previous_module.sub(rk,rh),previous_module.sub(rs['knee'],[rh[0],rh[1]+dy,rh[2]]))
        rl=previous_module.quat_from_to(previous_module.sub(rf,rk),previous_module.sub(goal,rs['knee']))
        lu=previous_module.quat_from_to(previous_module.sub(lk,lh),previous_module.sub(ls['knee'],[lh[0],lh[1]+dy,lh[2]]))
        ll=previous_module.quat_from_to(previous_module.sub(lf,lk),previous_module.sub(lf,ls['knee']))
        for q in (ru,rl,lu,ll):
            if not qfinite_unit(q):
                return rejected(summary,'non-unit apply quaternion')
            max_qangle=max(max_qangle,previous_module.qangle(q))
        frames.append({'sample_index':i,'pelvis_delta_y_m':dy,'right_upper_q':ru,'right_lower_q':rl,'left_upper_q':lu,'left_lower_q':ll})
    if len(frames)!=CYCLE:
        return rejected(summary,'incomplete application cycle')
    return {'schema':'grand-bruxelles-civ1-skeleton-applyability-v2','diagnostic_only':True,'runtime_authorized':False,'visual_approval_claimed':False,'source_reconstruction':summary,'frame_count':len(frames),'max_apply_quaternion_angle_rad':max_qangle,'frames':frames,'verdict':'AMELIORER_SKELETON_APPLYABILITY'}

def main():
    ap=argparse.ArgumentParser(); ap.add_argument('native_json'); ap.add_argument('reconstruction_module'); ap.add_argument('output_json'); a=ap.parse_args()
    p=json.loads(Path(a.native_json).read_text()); m=load_previous(a.reconstruction_module); r=analyze(p,m)
    Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n')
    if r['verdict']!='AMELIORER_SKELETON_APPLYABILITY':
        s=r['source_reconstruction']
        print('CIV1_SKELETON_APPLYABILITY_REJECTED '+f"reason={r['rejection_reason']} source_verdict={s.get('verdict')} physical={s.get('physical_envelope_pass')} continuity={s.get('joint_continuity_pass')} knee_step={s.get('max_knee_step_m')} joint_step={s.get('max_joint_step_rad')}")
        raise SystemExit(2)
    print(f"CIV1_SKELETON_APPLYABILITY_OK frames={r['frame_count']} max_q={r['max_apply_quaternion_angle_rad']:.6f} verdict={r['verdict']}")
if __name__=='__main__': main()
