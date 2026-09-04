#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, math
from pathlib import Path
CYCLE=120; N=121; MATERIAL=12; EPS=1e-9; MIN_MARGIN_MM=2; MAX_SHIFT=60
MAX_KNEE_STEP_M=0.06
MAX_JOINT_STEP_RAD=math.radians(12.0)

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
        axis=cross(a,[1,0,0])
        if norm(axis)<EPS:axis=cross(a,[0,1,0])
        axis=unit(axis); return [axis[0],axis[1],axis[2],0.0]
    c=cross(a,b); s=math.sqrt((1.0+d)*2.0); q=[c[0]/s,c[1]/s,c[2]/s,s*0.5]
    qn=math.sqrt(sum(x*x for x in q)); return [x/qn for x in q]
def qangle(q):return 2.0*math.acos(clamp(abs(q[3]),-1.0,1.0))
def two_bone_reachable(hip,knee,foot,goal,tol=1e-7):
    l1=dist(hip,knee);l2=dist(knee,foot);d=dist(hip,goal)
    return l1>=EPS and l2>=EPS and d>=EPS and d<=l1+l2+tol and d>=abs(l1-l2)-tol

def solve_two_bone(hip,knee,foot,goal):
    l1=dist(hip,knee);l2=dist(knee,foot);d=dist(hip,goal)
    if not two_bone_reachable(hip,knee,foot,goal):raise ValueError('unreachable two-bone target')
    axis=unit(sub(goal,hip)); a=(l1*l1-l2*l2+d*d)/(2*d); h=math.sqrt(max(0.0,l1*l1-a*a)); center=add(hip,mul(axis,a))
    relv=sub(knee,center); bend=sub(relv,mul(axis,dot(relv,axis)))
    if norm(bend)<EPS:
        bend=cross(axis,[0,1,0])
        if norm(bend)<EPS:bend=cross(axis,[1,0,0])
    bend=unit(bend); k1=add(center,mul(bend,h)); k2=sub(center,mul(bend,h)); solved=k1 if dist(k1,knee)<=dist(k2,knee) else k2
    uq=quat_from_to(sub(knee,hip),sub(solved,hip)); lq=quat_from_to(sub(foot,knee),sub(goal,solved))
    return {'knee':solved,'upper_angle_rad':qangle(uq),'lower_angle_rad':qangle(lq),'foot_error_m':0.0,'upper_length_error_m':abs(dist(hip,solved)-l1),'lower_length_error_m':abs(dist(solved,goal)-l2)}

def continuity_metrics(solutions):
    if len(solutions)!=CYCLE: raise ValueError('continuity requires full cycle')
    knee_steps=[]; joint_steps=[]
    for i in range(CYCLE):
        prev=(i-1)%CYCLE
        knee_steps.append(dist(solutions[i]['knee'],solutions[prev]['knee']))
        joint_steps.append(max(abs(solutions[i]['upper_angle_rad']-solutions[prev]['upper_angle_rad']),abs(solutions[i]['lower_angle_rad']-solutions[prev]['lower_angle_rad'])))
    return max(knee_steps),max(joint_steps)

def origin(s,b,side='target'):
    try:return v3(s['bones'][b][side]['model_origin'],f'{b}.{side}')
    except (KeyError,TypeError) as e:raise ValueError(f'missing {b}.{side}.model_origin') from e
def rel(s,b,side='target'):return sub(origin(s,b,side),origin(s,'Hips',side))
def minidx(seq):return min(range(CYCLE),key=lambda i:seq[i][1])
def circ(t,s):
    d=t-s
    while d>60:d-=120
    while d<-60:d+=120
    return d
def support(seq,c):return [seq[(c+d)%CYCLE] for d in (-2,-1,0,1,2)]
def vr(seq):return max(x[1] for x in seq)-min(x[1] for x in seq)
def ht(seq):return sum(math.hypot(seq[i][0]-seq[i-1][0],seq[i][2]-seq[i-1][2]) for i in range(1,len(seq)))

def contact_gate(base,src_min,baseline_phase,baseline_v,baseline_h,shift):
    seq=[[base[i][0],base[(i+shift)%CYCLE][1],base[i][2]] for i in range(CYCLE)]
    phase=circ(minidx(seq),src_min); sup=support(seq,src_min); vertical=vr(sup); horizontal=ht(sup)
    ok=abs(phase)<=MATERIAL and abs(phase)<abs(baseline_phase) and vertical<=baseline_v+1e-9 and horizontal<=baseline_h+1e-12
    return seq,{'shift_samples':shift,'phase_delta_samples':phase,'vertical_range_m':vertical,'horizontal_travel_m':horizontal,'contact_gate':ok}

def allowed_rows(samples,seq,limit_mm):
    rows=[]
    for i,s in enumerate(samples[:CYCLE]):
        hips=origin(s,'Hips');rf=origin(s,'RightFoot');lf=origin(s,'LeftFoot');rh=origin(s,'RightUpperLeg');rk=origin(s,'RightLowerLeg');lh=origin(s,'LeftUpperLeg');lk=origin(s,'LeftLowerLeg')
        goal=[rf[0],hips[1]+seq[i][1],rf[2]]; ok=[]
        for mm in range(-limit_mm,limit_mm+1):
            dy=mm/1000.0; rh2=[rh[0],rh[1]+dy,rh[2]];lh2=[lh[0],lh[1]+dy,lh[2]]
            if two_bone_reachable(rh2,rk,rf,goal,1e-6) and two_bone_reachable(lh2,lk,lf,lf,1e-6):ok.append(mm)
        rows.append(ok)
    return rows

def smooth_path(rows,step_mm):
    if any(not r for r in rows):return None
    costs={x:(abs(x),[x]) for x in rows[0]}
    for row in rows[1:]:
        nxt={}
        for cur in row:
            opts=[(cost+abs(cur),path+[cur]) for prev,(cost,path) in costs.items() if abs(cur-prev)<=step_mm]
            if opts:nxt[cur]=min(opts,key=lambda z:z[0])
        if not nxt:return None
        costs=nxt
    return min(costs.values(),key=lambda z:z[0])[1]

def minimal_path(samples,seq,max_used_mm,step_mm):
    rows=allowed_rows(samples,seq,max_used_mm)
    for used in range(max_used_mm+1):
        clipped=[[x for x in r if abs(x)<=used] for r in rows]
        path=smooth_path(clipped,step_mm)
        if path is not None:return used,path
    return None,None

def analyze(p):
    if p.get('rotation_enabled') is not True or p.get('position_enabled') is not False or p.get('scale_enabled') is not False:raise ValueError('rotation-only probe required')
    samples=p.get('model_space_samples')
    if not isinstance(samples,list) or len(samples)!=N:raise ValueError('expected 121 model_space_samples')
    for i,s in enumerate(samples):
        if s.get('sample_index')!=i:raise ValueError('sample index drift')
        if i<CYCLE:
            for b in ('Hips','RightUpperLeg','RightLowerLeg','RightFoot','LeftUpperLeg','LeftLowerLeg','LeftFoot'):origin(s,b)
            origin(s,'RightFoot','source');origin(s,'Hips','source')
    src=[rel(samples[i],'RightFoot','source') for i in range(CYCLE)];base=[rel(samples[i],'RightFoot') for i in range(CYCLE)]
    si=minidx(src);bi=minidx(base);baseline_phase=circ(bi,si);baseline_sup=support(base,si);baseline_v=vr(baseline_sup);baseline_h=ht(baseline_sup)
    ys=[origin(samples[i],'Hips','source')[1] for i in range(CYCLE)];source_step=max(abs(ys[i]-ys[i-1]) for i in range(1,CYCLE));source_range=max(ys)-min(ys)
    step_mm=max(1,int(math.floor(source_step*1000.0+1e-9))); source_range_mm=int(math.floor(source_range*1000.0+1e-9)); max_used=max(0,source_range_mm-MIN_MARGIN_MM)
    evidence=[]; candidates=[]
    for shift in range(1,MAX_SHIFT+1):
        seq,e=contact_gate(base,si,baseline_phase,baseline_v,baseline_h,shift)
        if not e['contact_gate']:continue
        used,path=minimal_path(samples,seq,max_used,step_mm)
        e['reachable_path']=path is not None; e['max_used_mm']=used; e['required_cap_mm']=None if used is None else used+MIN_MARGIN_MM
        evidence.append(e)
        if path is not None:candidates.append((used,abs(e['phase_delta_samples']),shift,seq,path,e))
    if not candidates:raise ValueError('no contact-gated bilateral path inside source pelvis envelope')
    used,_,shift,seq,pathmm,chosen=min(candidates,key=lambda x:(x[0],x[1],x[2]))
    right=[];left=[]
    for i,s in enumerate(samples[:CYCLE]):
        dy=pathmm[i]/1000.0;hips=origin(s,'Hips');rf=origin(s,'RightFoot');lf=origin(s,'LeftFoot');rh=origin(s,'RightUpperLeg');rk=origin(s,'RightLowerLeg');lh=origin(s,'LeftUpperLeg');lk=origin(s,'LeftLowerLeg')
        rh2=[rh[0],rh[1]+dy,rh[2]];lh2=[lh[0],lh[1]+dy,lh[2]];goal=[rf[0],hips[1]+seq[i][1],rf[2]]
        right.append((solve_two_bone(rh2,rk,rf,goal),rk));left.append((solve_two_bone(lh2,lk,lf,lf),lk))
    max_len=max(max(r[0]['upper_length_error_m'],r[0]['lower_length_error_m']) for r in right+left)
    max_angle=max(max(r[0]['upper_angle_rad'],r[0]['lower_angle_rad']) for r in right+left)
    max_rk=max(dist(r[0]['knee'],r[1]) for r in right);max_lk=max(dist(r[0]['knee'],r[1]) for r in left)
    max_step=max(abs(pathmm[i]-pathmm[i-1]) for i in range(1,CYCLE))/1000.0
    r_kstep,r_jstep=continuity_metrics([r[0] for r in right]); l_kstep,l_jstep=continuity_metrics([r[0] for r in left])
    max_knee_step=max(r_kstep,l_kstep); max_joint_step=max(r_jstep,l_jstep)
    physical=max_len<=1e-7 and max_step<=source_step+1e-12 and (used+MIN_MARGIN_MM)/1000.0<=source_range+1e-12
    continuity=max_knee_step<=MAX_KNEE_STEP_M and max_joint_step<=MAX_JOINT_STEP_RAD
    verdict='AMELIORER_BILATERAL_RECONSTRUCTION' if physical and continuity else 'JETER_BILATERAL_RECONSTRUCTION'
    return {'schema':'grand-bruxelles-civ1-bilateral-reconstruction-v2','diagnostic_only':True,'runtime_authorized':False,'visual_approval_claimed':False,'grounding_verified':False,'baseline_phase_delta_samples':baseline_phase,'baseline_vertical_range_m':baseline_v,'baseline_horizontal_travel_m':baseline_h,'source_pelvis_range_m':source_range,'source_pelvis_max_step_m':source_step,'contact_gated_shift_evidence':evidence,'candidate':{'vertical_shift_samples':shift,'max_used_pelvis_mm':used,'required_cap_mm':used+MIN_MARGIN_MM,'required_cap_margin_mm':MIN_MARGIN_MM,'pelvis_amplitude_fraction_of_source_range':(used/1000.0)/source_range},'phase_delta_samples':chosen['phase_delta_samples'],'vertical_range_m':chosen['vertical_range_m'],'horizontal_travel_m':chosen['horizontal_travel_m'],'max_bone_length_error_m':max_len,'max_joint_delta_rad':max_angle,'max_right_knee_displacement_m':max_rk,'max_left_knee_displacement_m':max_lk,'max_pelvis_step_m':max_step,'max_knee_step_m':max_knee_step,'max_joint_step_rad':max_joint_step,'continuity_limits':{'max_knee_step_m':MAX_KNEE_STEP_M,'max_joint_step_rad':MAX_JOINT_STEP_RAD},'physical_envelope_pass':physical,'joint_continuity_pass':continuity,'verdict':verdict}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('native_json');ap.add_argument('output_json');a=ap.parse_args();r=analyze(json.loads(Path(a.native_json).read_text()));Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n');c=r['candidate'];print('CIV1_BILATERAL_RECONSTRUCTION_OK '+f"shift={c['vertical_shift_samples']} used_mm={c['max_used_pelvis_mm']} cap_mm={c['required_cap_mm']} phase={r['baseline_phase_delta_samples']}->{r['phase_delta_samples']} knee_step={r['max_knee_step_m']:.6f} joint_step={r['max_joint_step_rad']:.6f} verdict={r['verdict']}")
if __name__=='__main__':main()
