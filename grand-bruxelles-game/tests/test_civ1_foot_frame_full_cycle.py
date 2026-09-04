from pathlib import Path
import importlib.util,math,pytest
SCRIPT=Path(__file__).parents[1]/'tools'/'analyze_civ1_foot_frame_full_cycle.py'
spec=importlib.util.spec_from_file_location('m',SCRIPT);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
def qx(a):
 h=a/2;return [math.sin(h),0,0,math.cos(h)]
def payload():
 out=[]
 for i in range(121):
  t=2*math.pi*i/120; bones={}
  for prefix in ('Right','Left'):
   for side,rest,shift in [('source',[0,0.4559,0.0514],0.0),('target',[0,0.4261,0.0],0.35)]:
    R=m._mat(m._quat(qx(0.35*math.sin(t+shift)),'q')); lo=[0.05*math.sin(t),0.5,0.05*math.cos(t)]; link=m._mul(R,rest); ft=[lo[k]+link[k] for k in range(3)]; hips=[0,0.9,0]
    bones.setdefault(prefix+'LowerLeg',{})[side]={'model_origin':lo,'model_rotation_xyzw':qx(0.35*math.sin(t+shift))}
    bones.setdefault(prefix+'Foot',{})[side]={'model_origin':ft,'model_rotation_xyzw':[0,0,0,1]}
    bones.setdefault('Hips',{})[side]={'model_origin':hips,'model_rotation_xyzw':[0,0,0,1]}
  out.append({'sample_index':i,'bones':bones})
 return {'rotation_enabled':True,'position_enabled':False,'scale_enabled':False,'model_space_samples':out}
def test_full_cycle_contract_is_fail_closed_and_length_preserving():
 r=m.analyze(payload());assert r['diagnostic_only'] and not r['runtime_authorized'] and not r['visual_approval_claimed'] and not r['grounding_verified'];assert len(r['support_samples'])==5;assert r['candidate_length_m']==pytest.approx(r['target_length_m'],abs=1e-10);assert isinstance(r['full_cycle_gate_pass'],bool);assert r['blend_sweep']['alpha_step']==pytest.approx(0.01);assert isinstance(r['blend_sweep']['simple_blend_family_viable'],bool);assert math.isfinite(r['horizontal_regression_pct'])
def test_requires_exact_121_samples():
 p=payload();p['model_space_samples'].pop()
 with pytest.raises(ValueError,match='121'):m.analyze(p)
def test_sample_drift_rejected():
 p=payload();p['model_space_samples'][50]['sample_index']=49
 with pytest.raises(ValueError,match='sample index drift'):m.analyze(p)
def test_wrong_probe_mode_rejected():
 p=payload();p['scale_enabled']=True
 with pytest.raises(ValueError,match='rotation-only'):m.analyze(p)
def test_nonfinite_rotation_rejected():
 p=payload();p['model_space_samples'][78]['bones']['RightLowerLeg']['target']['model_rotation_xyzw'][0]=float('nan')
 with pytest.raises(ValueError,match='non-finite'):m.analyze(p)
