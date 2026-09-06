#!/usr/bin/env python3
from __future__ import annotations
import importlib.util
from pathlib import Path
HERE=Path(__file__).resolve().parents[1]; TOOL=HERE/'tools'/'analyze_civ1_leftfoot_contact_phase.py'; spec=importlib.util.spec_from_file_location('contact_phase',TOOL); assert spec and spec.loader; m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
PATCH_TOOL=HERE/'tools'/'patch_civ1_probe_deterministic_sampling.py'; patch_spec=importlib.util.spec_from_file_location('probe_patch',PATCH_TOOL); assert patch_spec and patch_spec.loader; probe_patch=importlib.util.module_from_spec(patch_spec); patch_spec.loader.exec_module(probe_patch)

def bundle_from_y(ys):
    frames=[]
    for i,y in enumerate(ys):
        frames.append({'sample_index':i,'poses':{'LeftFoot':{'origin':[0.0,float(y),float(i)*0.001]}}})
    return {'schema':'grand-bruxelles-civ1-skeleton-witness-bundle-v1','frames':frames}

def main()->int:
    # Historical timing-contaminated shape: minimum at 119. It must remain fail-closed without the contact render.
    ys=[0.25]*120
    for i,v in {114:0.1980745,115:0.1960654,116:0.1940823,117:0.1921091,118:0.1901650,119:0.188777774572372,0:0.192155390977859,1:0.1966471,2:0.2051500}.items(): ys[i]=v
    old=m.assess_bundle(bundle_from_y(ys))
    assert old['leftfoot_min_sample']==119
    assert old['contact_target_contains_contact_min'] is True
    assert old['identity_window_contains_contact_min'] is False
    assert old['two_sided_low_contact'] is True
    assert old['contact_render_complete'] is False
    assert old['quantitative_foot_slide_candidate'] is False

    # Deterministic exact-seek receipt shape from artifact 9990147270: minimum moved to seam sample 0.
    det=[0.25]*120
    for i,v in {115:0.196,116:0.194,117:0.192,118:0.1904,119:0.190634220838547,0:0.188701927661896,1:0.190221518278122,2:0.194}.items(): det[i]=v
    real=m.assess_bundle(bundle_from_y(det))
    assert real['leftfoot_min_sample']==0
    assert real['contact_target_contains_contact_min'] is True
    assert real['prev_sample']==119 and real['next_sample']==1
    assert real['prev_low'] is True and real['next_low'] is True
    assert real['two_sided_low_contact'] is True
    assert real['contact_render_complete'] is False
    assert real['planted_contact_verified'] is False
    assert real['quantitative_foot_slide_candidate'] is False
    assert real['verdict']=='AMELIORER_CONTACT_RENDER_MISSING_NO_SLIDE_PROMOTION'
    good=m.assess_bundle(bundle_from_y(det), set(m.CONTACT_RENDER_SAMPLES))
    assert good['contact_target_contains_contact_min'] is True
    assert good['contact_render_complete'] is True and good['contact_render_contains_contact_min'] is True
    assert good['planted_contact_verified'] is True and good['quantitative_foot_slide_candidate'] is True

    # Fail closed if the actual phase minimum falls outside the predeclared raster target.
    bad=[0.25]*120; bad[60]=0.18; bad[59]=0.181; bad[61]=0.181
    shifted=m.assess_bundle(bundle_from_y(bad), set(m.CONTACT_RENDER_SAMPLES))
    assert shifted['contact_target_contains_contact_min'] is False
    assert shifted['planted_contact_verified'] is False
    assert shifted['quantitative_foot_slide_candidate'] is False
    assert shifted['verdict']=='AMELIORER_CONTACT_TARGET_MISALIGNED_NO_SLIDE_PROMOTION'

    text=TOOL.read_text(); assert 'LOW_BAND_M=0.010' in text; assert 'CONTACT_RENDER_SAMPLES=(118,119,0,1,2)' in text; assert "'animation_correction_authorized':False" in text
    probe='''func sample():\n    player.play(SOURCE_ANIMATION)\n    player.advance(0.0)\n    await process_frame\n    for sample_idx in range(SAMPLE_COUNT):\n        var t := animation.length * float(sample_idx) / float(SAMPLE_COUNT - 1)\n        player.seek(t, true)\n        player.advance(0.0)\n        await process_frame\n'''
    patched=probe_patch.patch_text(probe)
    assert patched.count('player.pause()')==1
    assert patched.index('player.pause()') < patched.index('for sample_idx in range(SAMPLE_COUNT):')
    try:
        probe_patch.patch_text(patched)
    except ValueError:
        pass
    else:
        raise AssertionError('patch must fail closed when applied twice or when the sampling block drifts')
    print('CIV1_LEFTFOOT_CONTACT_PHASE_TEST_OK'); return 0
if __name__=='__main__': raise SystemExit(main())
