#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math
from pathlib import Path
CYCLE=120; N=121; MATERIAL=12; EPS=1e-9; MIN_MARGIN_MM=2; MAX_SHIFT=60
MAX_KNEE_CORRECTION_STEP_M=0.06; MAX_JOINT_STEP_RAD=math.radians(12.0)
def v3(v,label='vec'):
    if not isinstance(v,list) or len(v)!=3: raise ValueError(f'invalid {label}')
    o=[float(x) for x in v]
    if not all(math.isfinite(x) for x in o): raise ValueError(f'non-finite {label}')
    return o
def add(a,b): return [a[i]+b[i] for i in range(3)]
def sub(a,b): return [a[i]-b[i] for i in range(3)]
def mul(a,s): return [x*s for x in a]
def dot(a,b): return sum(a[i]*b[i] for i in range(3))
def cross(a,b): return [a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0]]
def norm(a): return math.sqrt(dot(a,a))
def unit(a):
    n=norm(a)
    if n<EPS: raise ValueError('zero vector')
    return mul(a,1.0/n)
def dist(a,b): return norm(sub(a,b))
def clamp(x,a,b): return max(a,min(b,x))
def quat_from_to(a,b):
    a=unit(a); b=unit(b); d=clamp(dot(a,b),-1.0,1.0)
    if d>1.0-1e-12:return [0.0,0.0,0.0,1.0]
    if d<-1.0+1e-12:
        axis=cross(a,[1,0,0]); axis=axis if norm(axis)>=EPS else cross(a,[0,1,0]); axis=unit(axis); return [axis[0],axis[1],axis[2],0.0]
    c=cross(a,b); s=math.sqrt((1.0+d)*2.0); q=[c[0]/s,c[1]/s,c[2]/s,s*0.5]; qn=math.sqrt(sum(x*x for x in q)); return [x/qn for x in q]
def qangle(q): return 2.0*math.acos(clamp(abs(q[3]),-1.0,1.0))
def fixed_reachable(hip,goal,l1,l2,tol=1e-7):
    d=dist(hip,goal); return l1>=EPS and l2>=EPS and d>=EPS and d<=l1+l2+tol and d>=abs(l1-l2)-tol
def solve_fixed(hip,knee_ref,foot_ref,goal,l1,l2):
    d=dist(hip,goal)
    if not fixed_reachable(hip,goal,l1,l2): raise ValueError('unreachable fixed-length target')
    axis=unit(sub(goal,hip)); a=(l1*l1-l2*l2+d*d)/(2*d); h=math.sqrt(max(0.0,l1*l1-a*a)); center=add(hip,mul(axis,a))
    relv=sub(knee_ref,center); bend=sub(relv,mul(axis,dot(relv,axis)))
    if norm(bend)<EPS:
        bend=cross(axis,[0,1,0]); bend=bend if norm(bend)>=EPS else cross(axis,[1,0,0])
    bend=unit(bend); k1=add(center,mul(bend,h)); k2=sub(center,mul(bend,h)); knee=k1 if dist(k1,knee_ref)<=dist(k2,knee_ref) else k2
    uq=quat_from_to(sub(knee_ref,hip),sub(knee,hip)); lq=quat_from_to(sub(foot_ref,knee_ref),sub(goal,knee))
    return {'knee':knee,'knee_ref':knee_ref,'upper_angle_rad':qangle(uq),'lower_angle_rad':qangle(lq),'upper_length_error_m':abs(dist(hip,knee)-l1),'lower_length_error_m':abs(dist(knee,goal)-l2)}
def correction_continuity(solutions):
    offs=[sub(x['knee'],x['knee_ref']) for x in solutions]; ks=[]; js=[]
    for i in range(CYCLE):
        prev=(i-1)%CYCLE; ks.append(norm(sub(offs[i],offs[prev]))); js.append(max(abs(solutions[i]['upper_angle_rad']-solutions[prev]['upper_angle_rad']),abs(solutions[i]['lower_angle_rad']-solutions[prev]['lower_angle_rad'])))
    return max(ks),max(js)
def transition_ok(a,b,step_mm):
    if abs(a['mm']-b['mm'])>step_mm:return False
    for leg in ('right','left'):
        aa=a[leg]; bb=b[leg]
        ao=sub(aa['knee'],aa['knee_ref']); bo=sub(bb['knee'],bb['knee_ref'])
        if norm(sub(bo,ao))>MAX_KNEE_CORRECTION_STEP_M+1e-12:return False
        if max(abs(bb['upper_angle_rad']-aa['upper_angle_rad']),abs(bb['lower_angle_rad']-aa['lower_angle_rad']))>MAX_JOINT_STEP_RAD+1e-12:return False
    return True
def origin(s,b,side='target'): return v3(s['bones'][b][side]['model_origin'],f'{b}.{side}')
def rel(s,b,side='target'): return sub(origin(s,b,side),origin(s,'Hips',side))
def minidx(seq): return min(range(CYCLE),key=lambda i:seq[i][1])
def circ(t,s):
    d=t-s
    while d>60:d-=120
    while d<-60:d+=120
    return d
def support(seq,c): return [seq[(c+d)%CYCLE] for d in (-2,-1,0,1,2)]
def vr(seq): return max(x[1] for x in seq)-min(x[1] for x in seq)
def ht(seq): return sum(math.hypot(seq[i][0]-seq[i-1][0],seq[i][2]-seq[i-1][2]) for i in range(1,len(seq)))
def contact_gate(base,src_min,baseline_phase,baseline_v,baseline_h,shift):
    seq=[[base[i][0],base[(i+shift)%CYCLE][1],base[i][2]] for i in range(CYCLE)]; phase=circ(minidx(seq),src_min); sup=support(seq,src_min); vertical=vr(sup); horizontal=ht(sup)
    ok=abs(phase)<=MATERIAL and abs(phase)<abs(baseline_phase) and vertical<=baseline_v+1e-9 and horizontal<=baseline_h+1e-12
    return seq,{'shift_samples':shift,'phase_delta_samples':phase,'vertical_range_m':vertical,'horizontal_travel_m':horizontal,'contact_gate':ok}
def frame_state(s,goal,mm):
    dy=mm/1000.0; rf=origin(s,'RightFoot'); lf=origin(s,'LeftFoot'); rh=origin(s,'RightUpperLeg'); rk=origin(s,'RightLowerLeg'); lh=origin(s,'LeftUpperLeg'); lk=origin(s,'LeftLowerLeg')
    rl1,rl2=dist(rh,rk),dist(rk,rf); ll1,ll2=dist(lh,lk),dist(lk,lf)
    rhip=[rh[0],rh[1]+dy,rh[2]]; lhip=[lh[0],lh[1]+dy,lh[2]]
    if not fixed_reachable(rhip,goal,rl1,rl2,1e-6) or not fixed_reachable(lhip,lf,ll1,ll2,1e-6): return None
    return {'mm':mm,'right':solve_fixed(rhip,rk,rf,goal,rl1,rl2),'left':solve_fixed(lhip,lk,lf,lf,ll1,ll2)}
def state_rows(samples,seq,max_used_mm):
    rows=[]
    for i,s in enumerate(samples[:CYCLE]):
        hips=origin(s,'Hips'); rf=origin(s,'RightFoot'); goal=[rf[0],hips[1]+seq[i][1],rf[2]]; row={}
        for mm in range(-max_used_mm,max_used_mm+1):
            st=frame_state(s,goal,mm)
            if st is not None: row[mm]=st
        rows.append(row)
    return rows
def continuous_cycle(rows,step_mm):
    if any(not r for r in rows):return None
    max_cap=max(max(abs(x) for x in r) for r in rows)
    for cap in range(max_cap+1):
        starts=[m for m in rows[0] if abs(m)<=cap]
        for start in starts:
            reachable={start}; parents=[]
            for i in range(1,CYCLE):
                par={}; nxt=set()
                for mm,cur in rows[i].items():
                    if abs(mm)>cap:continue
                    for pm in range(mm-step_mm,mm+step_mm+1):
                        if pm in reachable and pm in rows[i-1] and transition_ok(rows[i-1][pm],cur,step_mm):
                            par[mm]=pm; nxt.add(mm); break
                parents.append(par); reachable=nxt
                if not reachable:break
            if not reachable:continue
            for end in reachable:
                if not transition_ok(rows[-1][end],rows[0][start],step_mm):continue
                path=[end]; cur=end
                for i in range(CYCLE-1,0,-1):
                    cur=parents[i-1][cur]; path.append(cur)
                return cap,list(reversed(path))
    return None
def path_metrics(rows,path):
    right=[rows[i][path[i]]['right'] for i in range(CYCLE)]; left=[rows[i][path[i]]['left'] for i in range(CYCLE)]
    max_len=max(max(x['upper_length_error_m'],x['lower_length_error_m']) for x in right+left); rk,rj=correction_continuity(right); lk,lj=correction_continuity(left)
    return {'right':right,'left':left,'max_len':max_len,'max_kstep':max(rk,lk),'max_jstep':max(rj,lj),'max_r':max(dist(x['knee'],x['knee_ref']) for x in right),'max_l':max(dist(x['knee'],x['knee_ref']) for x in left)}
def analyze(p):
    if p.get('rotation_enabled') is not True or p.get('position_enabled') is not False or p.get('scale_enabled') is not False: raise ValueError('rotation-only probe required')
    samples=p.get('model_space_samples')
    if not isinstance(samples,list) or len(samples)!=N: raise ValueError('expected 121 model_space_samples')
    for i,s in enumerate(samples):
        if s.get('sample_index')!=i: raise ValueError('sample index drift')
    src=[rel(samples[i],'RightFoot','source') for i in range(CYCLE)]; base=[rel(samples[i],'RightFoot') for i in range(CYCLE)]; si=minidx(src); baseline_phase=circ(minidx(base),si); bs=support(base,si); bv=vr(bs); bh=ht(bs)
    ys=[origin(samples[i],'Hips','source')[1] for i in range(CYCLE)]; source_step=max(abs(ys[i]-ys[i-1]) for i in range(1,CYCLE)); source_range=max(ys)-min(ys); step_mm=max(1,int(math.floor(source_step*1000+1e-9))); max_used=max(0,int(math.floor(source_range*1000+1e-9))-MIN_MARGIN_MM)
    evidence=[]; candidates=[]
    for shift in range(1,MAX_SHIFT+1):
        seq,e=contact_gate(base,si,baseline_phase,bv,bh,shift)
        if not e['contact_gate']:continue
        rows=state_rows(samples,seq,max_used); cycle=continuous_cycle(rows,step_mm); e['reachable_path']=all(bool(r) for r in rows); e['continuous_path']=cycle is not None; e['max_used_mm']=cycle[0] if cycle else None; evidence.append(e)
        if cycle is not None:
            used,path=cycle; candidates.append((used,abs(e['phase_delta_samples']),shift,seq,path,e,rows))
    if not candidates: raise ValueError('no fixed-length bilateral continuous cycle inside source pelvis envelope')
    used,_,shift,seq,pathmm,chosen,rows=min(candidates,key=lambda x:(x[0],x[1],x[2])); metrics=path_metrics(rows,pathmm)
    max_pstep=max(abs(pathmm[i]-pathmm[i-1]) for i in range(CYCLE))/1000.0
    physical=metrics['max_len']<=1e-7 and max_pstep<=source_step+1e-12 and (used+MIN_MARGIN_MM)/1000<=source_range+1e-12
    continuity=metrics['max_kstep']<=MAX_KNEE_CORRECTION_STEP_M and metrics['max_jstep']<=MAX_JOINT_STEP_RAD
    verdict='AMELIORER_FIXED_LENGTH_CONTINUOUS_CYCLE' if physical and continuity else 'JETER_FIXED_LENGTH_RECONSTRUCTION'
    return {'schema':'grand-bruxelles-civ1-fixed-length-reconstruction-v2','diagnostic_only':True,'runtime_authorized':False,'visual_approval_claimed':False,'grounding_verified':False,'baseline_phase_delta_samples':baseline_phase,'baseline_vertical_range_m':bv,'baseline_horizontal_travel_m':bh,'source_pelvis_range_m':source_range,'source_pelvis_max_step_m':source_step,'candidate':{'vertical_shift_samples':shift,'max_used_pelvis_mm':used,'required_cap_mm':used+MIN_MARGIN_MM},'contact_gated_shift_evidence':evidence,'pelvis_path_mm':pathmm,'phase_delta_samples':chosen['phase_delta_samples'],'vertical_range_m':chosen['vertical_range_m'],'horizontal_travel_m':chosen['horizontal_travel_m'],'max_bone_length_error_m':metrics['max_len'],'max_right_knee_displacement_m':metrics['max_r'],'max_left_knee_displacement_m':metrics['max_l'],'max_pelvis_step_m':max_pstep,'max_knee_correction_step_m':metrics['max_kstep'],'max_joint_step_rad':metrics['max_jstep'],'continuity_limits':{'max_knee_correction_step_m':MAX_KNEE_CORRECTION_STEP_M,'max_joint_step_rad':MAX_JOINT_STEP_RAD},'physical_envelope_pass':physical,'correction_continuity_pass':continuity,'verdict':verdict}
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('native_json'); ap.add_argument('output_json'); a=ap.parse_args(); r=analyze(json.loads(Path(a.native_json).read_text())); Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n'); c=r['candidate']; print('CIV1_FIXED_LENGTH_RECONSTRUCTION_OK '+f"shift={c['vertical_shift_samples']} used_mm={c['max_used_pelvis_mm']} phase={r['baseline_phase_delta_samples']}->{r['phase_delta_samples']} bone_error={r['max_bone_length_error_m']:.3e} knee_corr_step={r['max_knee_correction_step_m']:.6f} joint_step={r['max_joint_step_rad']:.6f} verdict={r['verdict']}")
if __name__=='__main__': main()
