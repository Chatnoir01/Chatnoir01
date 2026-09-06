#!/usr/bin/env python3
import importlib.util
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
TOOL=ROOT/'tools'/'analyze_civ1_bilateral_contact_phase_readiness.py'
spec=importlib.util.spec_from_file_location('phasegate',TOOL); mod=importlib.util.module_from_spec(spec); spec.loader.exec_module(mod)


def bilateral():
    return {
        'schema':'grand-bruxelles-civ1-bilateral-landmark-promotion-v2',
        'bilateral_identity_ready':True,
        'bilateral_contact_phase_ready':False,
        'quantitative_foot_slide_candidate':False,
        'planted_contact_claimed':False,
        'animation_correction_authorized':False,
        'runtime_authorized':False,
        'visual_approval_claimed':False,
        'player_view_claimed':False,
    }


def foot(samples, eligible):
    return {
        'vertical_stable_sample_count':len(samples),
        'eligible_vertical_stability_window_count':1 if eligible else 0,
        'windows':[{
            'eligible_vertical_stability_window':eligible,
            'sample_indices':samples,
        }],
    }


def contact(left, right):
    return {
        'schema':'grand-bruxelles-civ1-contact-windows-v4',
        'frame_count':120,
        'minimum_vertical_stability_window_samples':3,
        'feet':{'LeftFoot':left,'RightFoot':right},
        'ground_contact_claimed':False,
        'runtime_authorized':False,
        'visual_approval_claimed':False,
        'player_view_claimed':False,
    }

# Real measured shape from immutable native contact artifact: Left is eligible 115..118,
# Right is only 69..70 and must fail closed. The next witness window adds one source
# context sample on each side without inventing a new threshold.
out=mod.analyze(contact(foot([115,116,117,118],True),foot([69,70],False)),bilateral())
assert out['leftfoot']['phase_ready'] is True
assert out['rightfoot']['phase_ready'] is False
assert out['rightfoot']['next_witness_samples']==[68,69,70,71]
assert out['bilateral_contact_phase_ready'] is False
assert out['blockers']==[{'side':'RightFoot','reason':'vertical_stability_window_too_short_or_ineligible','observed_samples':[69,70],'minimum_samples':3}]
assert out['quantitative_foot_slide_candidate'] is False
assert out['animation_correction_authorized'] is False

# Positive control: three eligible samples per side may clear phase readiness but still
# cannot authorize planted contact, foot-slide, animation or runtime.
out=mod.analyze(contact(foot([115,116,117],True),foot([69,70,71],True)),bilateral())
assert out['bilateral_contact_phase_ready'] is True
assert out['quantitative_foot_slide_candidate'] is False
assert out['planted_contact_claimed'] is False
assert out['runtime_authorized'] is False

# Identity evidence is mandatory and cannot be inferred from phase windows.
bad=bilateral(); bad['bilateral_identity_ready']=False
try:
    mod.analyze(contact(foot([115,116,117],True),foot([69,70,71],True)),bad)
    raise AssertionError('missing fail-closed identity rejection')
except ValueError as exc:
    assert 'identity' in str(exc)

print('CIV1_BILATERAL_CONTACT_PHASE_READINESS_REGRESSION_OK')
