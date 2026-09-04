from pathlib import Path
import importlib.util,math,pytest
SCRIPT=Path(__file__).parents[1]/'tools'/'analyze_civ1_foot_frame_preserving_map.py'
spec=importlib.util.spec_from_file_location('m',SCRIPT);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
SRC_Q={78:[0.965128302574158,0.00101248372811824,-0.000996139133349061,-0.261773496866226],79:[0.957781553268433,0.000749636848922819,-0.000533975078724325,-0.287495642900467]}
TGT_Q={78:[0.0111699160188437,-0.262538641691208,0.964026272296906,0.0400258749723434],79:[0.0118019161745906,-0.288249313831329,0.956646740436554,0.0400012135505676]}
RS=[0.0,0.4559001294737344,0.05140012550169159];RT=[0.0,0.42608533143676275,0.0]
def _mk(prefix,side,q,rest):
 R=m._mat(m._quat(q,'q'));link=m._mul(R,rest);lo=[0.1,0.6,0.2];ft=[lo[k]+link[k] for k in range(3)]
 return {prefix+'LowerLeg':{side:{'model_origin':lo,'model_rotation_xyzw':q[:]}},prefix+'Foot':{side:{'model_origin':ft,'model_rotation_xyzw':[0,0,0,1]}}}
def sample(i):
 bones={}
 for prefix in ('Right','Left'):
  for side,q,rest in [('source',SRC_Q[i],RS),('target',TGT_Q[i],RT)]:
   for bone,val in _mk(prefix,side,q,rest).items(): bones.setdefault(bone,{}).update(val)
 return {'sample_index':i,'bones':bones}
def payload():
 s=[{'sample_index':i,'bones':{}} for i in range(80)];s[78]=sample(78);s[79]=sample(79)
 return {'rotation_enabled':True,'position_enabled':False,'scale_enabled':False,'model_space_samples':s}
def test_contract_and_length_preservation():
 r=m.analyze(payload());q=r['right_foot'];assert r['diagnostic_only'] and not r['runtime_authorized'] and not r['grounding_verified'] and not r['visual_approval_claimed'];assert q['improvement_abs_m']>0.002;assert q['candidate_length_m']==pytest.approx(q['target_length_m'],abs=1e-12)
def test_wrong_probe_mode_rejected():
 p=payload();p['position_enabled']=True
 with pytest.raises(ValueError,match='rotation-only'):m.analyze(p)
def test_sample_drift_rejected():
 p=payload();p['model_space_samples'][79]['sample_index']=78
 with pytest.raises(ValueError,match='sample index drift'):m.analyze(p)
def test_nonfinite_rotation_rejected():
 p=payload();p['model_space_samples'][78]['bones']['RightLowerLeg']['source']['model_rotation_xyzw'][0]=float('nan')
 with pytest.raises(ValueError,match='non-finite'):m.analyze(p)
def test_degenerate_target_length_rejected():
 p=payload()
 for i in (78,79):
  b=p['model_space_samples'][i]['bones'];b['RightFoot']['target']['model_origin']=b['RightLowerLeg']['target']['model_origin'][:]
 with pytest.raises(ValueError,match='degenerate target limb length'):m.analyze(p)
