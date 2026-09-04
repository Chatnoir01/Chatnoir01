from pathlib import Path
import importlib.util, math, pytest
SCRIPT=Path(__file__).parents[1]/'tools'/'analyze_civ1_foot_rest_basis_ab.py'
spec=importlib.util.spec_from_file_location('ab',SCRIPT); mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)
def qx(d):
    h=math.radians(d)/2;return [math.sin(h),0,0,math.cos(h)]
def sample(i,src_deg,tgt_deg,left_src=-4,left_tgt=-2):
    bones={}
    for prefix,sd,td in [('Right',src_deg,tgt_deg),('Left',left_src,left_tgt)]:
        for side,deg,rest in [('source',sd,[0,0.4559,0.0514]),('target',td,[0,0.4261,0.0])]:
            R=mod._mat(mod._quat(qx(deg),'q')); link=mod._mul(R,rest); lo=[0.1,0.6,0.2]; ft=[lo[k]+link[k] for k in range(3)]
            bones.setdefault(prefix+'LowerLeg',{})[side]={'model_origin':lo,'model_rotation_xyzw':qx(deg)}
            bones.setdefault(prefix+'Foot',{})[side]={'model_origin':ft,'model_rotation_xyzw':[0,0,0,1]}
    return {'sample_index':i,'bones':bones}
def payload():
    samples=[{'sample_index':i,'bones':{}} for i in range(80)];samples[78]=sample(78,10,12);samples[79]=sample(79,8,9)
    return {'rotation_enabled':True,'position_enabled':False,'scale_enabled':False,'model_space_samples':samples}
def test_contract_and_no_runtime_claims():
    r=mod.analyze(payload()); assert r['diagnostic_only'] is True; assert r['runtime_authorized'] is False; assert r['grounding_verified'] is False; assert r['visual_approval_claimed'] is False
    assert abs(r['right_foot_ab']['source_rest_local_m'][2]-0.0514)<1e-6
    assert abs(r['right_foot_ab']['target_rest_local_m'][2])<1e-6
def test_wrong_probe_modes_rejected():
    for key,val in [('rotation_enabled',False),('position_enabled',True),('scale_enabled',True)]:
        p=payload();p[key]=val
        with pytest.raises(ValueError): mod.analyze(p)
def test_sample_drift_rejected():
    p=payload();p['model_space_samples'][79]['sample_index']=78
    with pytest.raises(ValueError): mod.analyze(p)
def test_nonfinite_rotation_rejected():
    p=payload();p['model_space_samples'][78]['bones']['RightLowerLeg']['target']['model_rotation_xyzw']=[float('nan'),0,0,1]
    with pytest.raises(ValueError): mod.analyze(p)
def test_missing_source_z_rejected():
    p=payload()
    for i in (78,79):
        s=p['model_space_samples'][i]; lo=s['bones']['RightLowerLeg']['source']; R=mod._mat(mod._quat(lo['model_rotation_xyzw'],'q')); rest=[0,0.4559,0.0]; link=mod._mul(R,rest); o=lo['model_origin']; s['bones']['RightFoot']['source']['model_origin']=[o[k]+link[k] for k in range(3)]
    with pytest.raises(ValueError): mod.analyze(p)
def test_target_nonzero_z_rejected():
    p=payload()
    for i in (78,79):
        s=p['model_space_samples'][i]; lo=s['bones']['RightLowerLeg']['target']; R=mod._mat(mod._quat(lo['model_rotation_xyzw'],'q')); rest=[0,0.4261,0.01]; link=mod._mul(R,rest); o=lo['model_origin']; s['bones']['RightFoot']['target']['model_origin']=[o[k]+link[k] for k in range(3)]
    with pytest.raises(ValueError): mod.analyze(p)
