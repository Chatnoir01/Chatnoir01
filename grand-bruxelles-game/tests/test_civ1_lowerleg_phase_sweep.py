from pathlib import Path
import importlib.util,math,pytest
SCRIPT=Path(__file__).parents[1]/'tools'/'analyze_civ1_lowerleg_phase_sweep.py'
spec=importlib.util.spec_from_file_location('m',SCRIPT);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def qx(a):
 h=a/2;return [math.sin(h),0,0,math.cos(h)]
def payload(target_shift_samples=18):
 out=[]
 for i in range(121):
  bones={}
  for prefix in ('Right','Left'):
   for side,rest,shift in [('source',[0,0.4559,0.0514],0),('target',[0,0.4261,0.0],target_shift_samples)]:
    j=(i+shift)%120;t=2*math.pi*j/120;rot=0.42*math.sin(t)
    R=m.mat(m.quat(qx(rot),'q'));lo=[0.03*math.sin(2*math.pi*i/120),0.5,0.02*math.cos(2*math.pi*i/120)];link=m.mul(R,rest);ft=[lo[k]+link[k] for k in range(3)]
    bones.setdefault(prefix+'LowerLeg',{})[side]={'model_origin':lo,'model_rotation_xyzw':qx(rot)}
    bones.setdefault(prefix+'Foot',{})[side]={'model_origin':ft,'model_rotation_xyzw':[0,0,0,1]}
    bones.setdefault('Hips',{})[side]={'model_origin':[0,0.9,0],'model_rotation_xyzw':[0,0,0,1]}
  out.append({'sample_index':i,'bones':bones})
 return {'rotation_enabled':True,'position_enabled':False,'scale_enabled':False,'model_space_samples':out}
def test_phase_sweep_preserves_target_rest_and_is_diagnostic_only():
 r=m.analyze(payload());assert r['diagnostic_only'] and not r['runtime_authorized'] and not r['visual_approval_claimed'];assert r['foot_link_rest_preserved'];assert r['tested_shift_count']==81;assert -40<=r['best']['shift_samples']<=40;assert isinstance(r['family_viable'],bool);assert all(math.isfinite(x) for x in r['target_rest_local_m'])
def test_known_synthetic_phase_offset_has_corrective_family():
 r=m.analyze(payload(18));assert r['viable_shift_count']>0;assert min(abs(s+18) for s in r['viable_shifts'])<=2
def test_requires_rotation_only_probe():
 p=payload();p['position_enabled']=True
 with pytest.raises(ValueError,match='rotation-only'):m.analyze(p)
def test_rejects_sample_drift():
 p=payload();p['model_space_samples'][9]['sample_index']=8
 with pytest.raises(ValueError,match='sample index drift'):m.analyze(p)
def test_rejects_nonfinite_lowerleg_rotation():
 p=payload();p['model_space_samples'][12]['bones']['RightLowerLeg']['target']['model_rotation_xyzw'][0]=float('nan')
 with pytest.raises(ValueError,match='non-finite'):m.analyze(p)
