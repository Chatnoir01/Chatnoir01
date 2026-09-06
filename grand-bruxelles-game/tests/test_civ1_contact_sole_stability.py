#!/usr/bin/env python3
import importlib.util, tempfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
TOOL=ROOT/'tools'/'analyze_civ1_contact_sole_stability.py'
spec=importlib.util.spec_from_file_location('contactsole',TOOL); mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)


def witness():
    caps=[]
    for s in mod.SAMPLES:
        for d in mod.DISTANCES:
            caps.append({'sample_index':s,'distance_m':d,'png':f'x-{d}-{s}.png'})
    return {'schema':'grand-bruxelles-civ1-leftfoot-landmark-witness-v1','sample_indices':list(mod.SAMPLES),'resolution':[1280,720],
            'captures':caps,'planted_contact_claimed':False,'animation_correction_authorized':False,'runtime_authorized':False,
            'visual_approval_claimed':False,'player_view_claimed':False}


def run_with_sides(side_by_sample_distance):
    old=mod.observe
    try:
        def fake(path):
            _,d,s=path.stem.split('-'); side=side_by_sample_distance[(int(s),int(d))]
            return {'marker_x_px':0.0,'marker_y_px':0.0,'marker_radius_px':1.0,'local_bottom_y_px':0,'local_bottom_x_px':float(side),'normalized_offset_x':float(side),'side':side}
        mod.observe=fake
        return mod.analyze(witness(),Path(tempfile.mkdtemp()))
    finally: mod.observe=old


good={(s,d):1 for s in mod.SAMPLES for d in mod.DISTANCES}
out=run_with_sides(good)
assert out['contact_sole_identity_stable'] is True
assert out['longest_common_stable_window']==list(mod.SAMPLES)

# Real-shape regression: 118/119 agree at 2/4/8 m; frame 0 disagrees at 4 m;
# frames 1/2 have crossed to the opposite local side. Two samples are not enough
# for a quantitative planted-foot window, so the analyzer must fail closed.
real={}
for s in mod.SAMPLES:
    for d in mod.DISTANCES: real[(s,d)]=1
real[(0,4)]=-1
for s in (1,2):
    for d in mod.DISTANCES: real[(s,d)]=-1
out=run_with_sides(real)
assert out['common_same_side_samples']==[118,119,1,2]
assert out['longest_common_stable_window']==[118,119]
assert out['contact_sole_identity_stable'] is False
assert out['quantitative_foot_slide_candidate'] is False
assert out['verdict']=='AMELIORER_CONTACT_SOLE_IDENTITY_BREAKS_BEFORE_QUANTITATIVE_SLIDE'
print('CIV1_CONTACT_SOLE_STABILITY_REGRESSION_OK')
