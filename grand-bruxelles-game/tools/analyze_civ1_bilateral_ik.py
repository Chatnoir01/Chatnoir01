#!/usr/bin/env python3
from __future__ import annotations
import argparse,json,math
from pathlib import Path
CYCLE=120; N=121; SHIFT=16; MATERIAL=12; EPS=1e-9; CAPS_MM=range(55,61); MIN_MARGIN_MM=2

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
    if d>1.0-1e-12: return [0.0,0.0,0.0,1.0]
    if d<-1.0+1e-12:
        axis=cross(a,[1,0,0])
        if norm(axis)<EPS: axis=cross(a,[0,1,0])
        axis=unit(axis); return [axis[0],axis[1],axis[2],0.0]
    c=cross(a,b); s=math.sqrt((1.0+d)*2.0); q=[c[0]/s,c[1]/s,c[2]/s,s*0.5]
    qn=math.sqrt(sum(x*x for x in q)); return [x/qn for x in q]
def qangle(q): return 2.0*math.acos(clamp(abs(q[3]),-1.0,1.0))
def two_bone_reachable(hip,knee,foot,goal,tol=1e-7):
    l1=dist(hip,knee); l2=dist(knee,foot); d=dist(hip,goal)
    return l1>=EPS and l2>=EPS and d>=EPS and d<=l1+l2+tol and d>=abs(l1-l2)-tol

def solve_two_bone(hip,knee,foot,goal):
    l1=dist(hip,knee); l2=dist(knee,foot); d=dist(hip,goal)
    if not two_bone_reachable(hip,knee,foot,goal): raise ValueError('unreachable two-bone target')
    axis=unit(sub(goal,hip)); a=(l1*l1-l2*l2+d*d)/(2.0*d); h=math.sqrt(max(0.0,l1*l1-a*a)); center=add(hip,mul(axis,a))
    rel=sub(knee,center); bend=sub(rel,mul(axis,dot(rel,axis)))
    if norm(bend)<EPS:
        bend=cross(axis,[0,1,0])
        if norm(bend)<EPS: bend=cross(axis,[1,0,0])
    bend=unit(bend); k1=add(center,mul(bend,h)); k2=sub(center,mul(bend,h)); solved=k1 if dist(k1,knee)<=dist(k2,knee) else k2
    uq=quat_from_to(sub(knee,hip),sub(solved,hip)); lq=quat_from_to(sub(foot,knee),sub(goal,solved))
    return {'knee':solved,'upper_delta_xyzw':uq,'lower_delta_xyzw':lq,'upper_angle_rad':qangle(uq),'lower_angle_rad':qangle(lq),'foot_error_m':0.0,'upper_length_error_m':abs(dist(hip,solved)-l1),'lower_length_error_m':abs(dist(solved,goal)-l2)}

def origin(s,b,side='target'):
    try:return v3(s['bones'][b][side]['model_origin'],f'{b}.{side}')
    except (KeyError,TypeError) as e: raise ValueError(f'missing {b}.{side}.model_origin') from e
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

def allowed_dys(samples,seq,cap_mm):
    rows=[]
    for i,s in enumerate(samples[:CYCLE]):
        hips=origin(s,'Hips'); rf=origin(s,'RightFoot'); lf=origin(s,'LeftFoot'); rh=origin(s,'RightUpperLeg'); rk=origin(s,'RightLowerLeg'); lh=origin(s,'LeftUpperLeg'); lk=origin(s,'LeftLowerLeg')
        goal=[rf[0],hips[1]+seq[i][1],rf[2]]; ok=[]
        for mm in range(-cap_mm,cap_mm+1):
            dy=mm/1000.0; rh2=[rh[0],rh[1]+dy,rh[2]]; lh2=[lh[0],lh[1]+dy,lh[2]]
            if two_bone_reachable(rh2,rk,rf,goal,1e-6) and two_bone_reachable(lh2,lk,lf,lf,1e-6): ok.append(mm)
        rows.append(ok)
    return rows
def smooth_path(rows,max_step_m):
    if any(not r for r in rows): return None
    step=int(math.floor(max_step_m*1000.0+1e-9)); costs={x:(abs(x),[x]) for x in rows[0]}
    for row in rows[1:]:
        nxt={}
        for cur in row:
            c=[(cost+abs(cur),path+[cur]) for prev,(cost,path) in costs.items() if abs(cur-prev)<=step]
            if c:nxt[cur]=min(c,key=lambda x:x[0])
        if not nxt:return None
        costs=nxt
    return [x/1000.0 for x in min(costs.values(),key=lambda x:x[0])[1]]
def choose_robust_path(samples,seq,max_step_m):
    evidence=[]
    for cap in CAPS_MM:
        path=smooth_path(allowed_dys(samples,seq,cap),max_step_m)
        used_mm=0 if path is None else int(math.ceil(max(abs(x) for x in path)*1000.0-1e-9))
        margin=cap-used_mm if path is not None else -1
        evidence.append({'pelvis_cap_mm':cap,'reachable':path is not None,'max_used_mm':used_mm,'margin_mm':margin})
        if path is not None and margin>=MIN_MARGIN_MM: return cap,path,evidence
    return None,None,evidence

def analyze(p):
    if p.get('rotation_enabled') is not True or p.get('position_enabled') is not False or p.get('scale_enabled') is not False: raise ValueError('rotation-only probe required')
    samples=p.get('model_space_samples')
    if not isinstance(samples,list) or len(samples)!=N: raise ValueError('expected 121 model_space_samples')
    for i,s in enumerate(samples):
        if s.get('sample_index')!=i: raise ValueError('sample index drift')
        if i<CYCLE:
            for b in ('Hips','RightUpperLeg','RightLowerLeg','RightFoot','LeftUpperLeg','LeftLowerLeg','LeftFoot'): origin(s,b)
            origin(s,'RightFoot','source'); origin(s,'Hips','source')
    src=[rel(samples[i],'RightFoot','source') for i in range(CYCLE)]; base=[rel(samples[i],'RightFoot') for i in range(CYCLE)]
    si=minidx(src); bi=minidx(base); baseline_phase=circ(bi,si); baseline_sup=support(base,si); baseline_v=vr(baseline_sup); baseline_h=ht(baseline_sup)
    seq=[[base[i][0],base[(i+SHIFT)%CYCLE][1],base[i][2]] for i in range(CYCLE)]
    ys=[origin(samples[i],'Hips','source')[1] for i in range(CYCLE)]; source_step=max(abs(ys[i]-ys[i-1]) for i in range(1,CYCLE)); source_range=max(ys)-min(ys)
    cap,path,cap_evidence=choose_robust_path(samples,seq,source_step)
    if path is None: raise ValueError('no robust +16 pelvis path with >=2 mm cap margin')
    if max(abs(x) for x in path)>source_range+1e-12: raise ValueError('pelvis path exceeds source vertical range')
    right=[]; left=[]
    for i,s in enumerate(samples[:CYCLE]):
        dy=path[i]; hips=origin(s,'Hips'); rf=origin(s,'RightFoot'); lf=origin(s,'LeftFoot'); rh=origin(s,'RightUpperLeg'); rk=origin(s,'RightLowerLeg'); lh=origin(s,'LeftUpperLeg'); lk=origin(s,'LeftLowerLeg')
        rh2=[rh[0],rh[1]+dy,rh[2]]; lh2=[lh[0],lh[1]+dy,lh[2]]; rgoal=[rf[0],hips[1]+seq[i][1],rf[2]]
        right.append(solve_two_bone(rh2,rk,rf,rgoal)); left.append(solve_two_bone(lh2,lk,lf,lf))
    phase=circ(minidx(seq),si); sup=support(seq,si); vertical=vr(sup); horizontal=ht(sup)
    max_r_foot=max(x['foot_error_m'] for x in right); max_l_foot=max(x['foot_error_m'] for x in left); max_len=max(max(x['upper_length_error_m'],x['lower_length_error_m']) for x in right+left)
    max_angle=max(max(x['upper_angle_rad'],x['lower_angle_rad']) for x in right+left); max_knee=max(dist(right[i]['knee'],origin(samples[i],'RightLowerLeg')) for i in range(CYCLE)); max_left_knee=max(dist(left[i]['knee'],origin(samples[i],'LeftLowerLeg')) for i in range(CYCLE))
    pass_all=abs(phase)<=MATERIAL and abs(phase)<abs(baseline_phase) and vertical<=baseline_v+1e-9 and horizontal<=baseline_h+1e-12 and max_r_foot<=1e-9 and max_l_foot<=1e-9 and max_len<=1e-7
    return {'schema':'grand-bruxelles-civ1-bilateral-ik-v3','diagnostic_only':True,'runtime_authorized':False,'visual_approval_claimed':False,'grounding_verified':False,'candidate':{'vertical_shift_samples':SHIFT,'pelvis_cap_mm':cap,'required_cap_margin_mm':MIN_MARGIN_MM},'cap_evidence':cap_evidence,'baseline_phase_delta_samples':baseline_phase,'phase_delta_samples':phase,'baseline_vertical_range_m':baseline_v,'vertical_range_m':vertical,'baseline_horizontal_travel_m':baseline_h,'horizontal_travel_m':horizontal,'max_right_foot_target_error_m':max_r_foot,'max_left_foot_target_error_m':max_l_foot,'max_bone_length_error_m':max_len,'max_joint_delta_rad':max_angle,'max_right_knee_displacement_m':max_knee,'max_left_knee_displacement_m':max_left_knee,'max_abs_pelvis_delta_m':max(abs(x) for x in path),'max_pelvis_step_m':max(abs(path[i]-path[i-1]) for i in range(1,CYCLE)),'joint_solution_pass':pass_all,'verdict':'AMELIORER_BILATERAL_IK' if pass_all else 'JETER_BILATERAL_IK'}
def main():
    ap=argparse.ArgumentParser(); ap.add_argument('native_json'); ap.add_argument('output_json'); a=ap.parse_args(); r=analyze(json.loads(Path(a.native_json).read_text())); Path(a.output_json).write_text(json.dumps(r,indent=2,sort_keys=True)+'\n'); print('CIV1_BILATERAL_IK_OK '+f"cap={r['candidate']['pelvis_cap_mm']} phase={r['baseline_phase_delta_samples']}->{r['phase_delta_samples']} vertical={r['baseline_vertical_range_m']:.9f}->{r['vertical_range_m']:.9f} horizontal={r['baseline_horizontal_travel_m']:.9f}->{r['horizontal_travel_m']:.9f} max_joint_rad={r['max_joint_delta_rad']:.6f} verdict={r['verdict']}")
if __name__=='__main__': main()
