#!/usr/bin/env python3
"""Wire a validated CIV-1 time-varying source-direction schedule into the native Godot probe."""
from __future__ import annotations
import argparse, json, math
from pathlib import Path
RIGHT='    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n'
LEFT='    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n'
SAMPLE='        var normalized_target_foot_origin := target_right_parent_pose.origin + target_right_parent_pose.basis * normalized_target_local_rest_origin\n'
MARKER='CIV1_DYNAMIC_SOURCE_DIRECTION_NATIVE_PROBE'
EXPECTED_KIND='civ1_rightfoot_dynamic_source_direction_schedule'
EXPECTED_COMPONENT='target_local_rest_direction'
EXPECTED_CENTER=59
EXPECTED_CYCLE=120
LENGTH_TOLERANCE_M=1e-6

def _validated_blends(payload:dict)->list[float]:
    if payload.get('candidate_kind')!=EXPECTED_KIND: raise ValueError('unexpected candidate kind')
    if payload.get('component')!=EXPECTED_COMPONENT: raise ValueError('candidate must target target-local rest direction')
    if payload.get('candidate_is_native_measurement') is not False: raise ValueError('input must remain pre-native candidate evidence')
    if payload.get('runtime_authorized') is not False or payload.get('visual_approval_claimed') is not False: raise ValueError('promotion claim present')
    if payload.get('center_sample')!=EXPECTED_CENTER or payload.get('baseline_source_plant_sample')!=EXPECTED_CENTER: raise ValueError('candidate is not bound to plant sample 59')
    if payload.get('cycle_sample_count')!=EXPECTED_CYCLE or payload.get('baseline_cycle_sample_count')!=EXPECTED_CYCLE: raise ValueError('candidate is not bound to 120-sample cycle')
    radius=payload.get('radius_samples')
    if isinstance(radius,bool) or not isinstance(radius,int) or not 2<=radius<EXPECTED_CYCLE//2: raise ValueError('invalid radius')
    samples=payload.get('samples')
    if not isinstance(samples,list) or len(samples)!=EXPECTED_CYCLE: raise ValueError('candidate must contain exactly 120 samples')
    blends=[]
    for index,sample in enumerate(samples):
        if not isinstance(sample,dict): raise ValueError('invalid sample payload')
        value=sample.get('direction_blend')
        if isinstance(value,bool) or not isinstance(value,(int,float)): raise ValueError('direction_blend must be numeric')
        blend=float(value)
        if not math.isfinite(blend) or not 0.0<=blend<=1.0: raise ValueError('direction_blend must be finite and in [0,1]')
        distance=min((index-EXPECTED_CENTER)%EXPECTED_CYCLE,(EXPECTED_CENTER-index)%EXPECTED_CYCLE)
        if distance>radius and abs(blend)>1e-12: raise ValueError('blend outside declared window')
        for field,tol in (('right_foot_length_error_m',LENGTH_TOLERANCE_M),('left_foot_delta_m',1e-9)):
            metric=sample.get(field)
            if isinstance(metric,bool) or not isinstance(metric,(int,float)) or not math.isfinite(float(metric)): raise ValueError(f'invalid {field}')
            if abs(float(metric))>tol: raise ValueError(f'candidate violates {field} rail')
        blends.append(blend)
    if blends[EXPECTED_CENTER]<=1e-9: raise ValueError('center sample must be active')
    active=[round(v,12) for v in blends if v>1e-12]
    if len(set(active))<2: raise ValueError('candidate is not time-varying')
    for direction in (-1,1):
        for distance in range(radius):
            inner=blends[(EXPECTED_CENTER+direction*distance)%EXPECTED_CYCLE]
            outer=blends[(EXPECTED_CENTER+direction*(distance+1))%EXPECTED_CYCLE]
            if outer>inner+1e-12: raise ValueError('blend taper grows away from plant center')
    return blends

def transform(text:str,payload:dict)->str:
    blends=_validated_blends(payload)
    if MARKER in text: raise ValueError('input already contains dynamic source-direction probe')
    if 'func _make_shadow_skeleton' not in text or 'left_foot_reference_ab' not in text: raise ValueError('input is not validated bilateral shadow probe')
    if text.count(RIGHT)!=1 or text.count(LEFT)!=1 or text.count(SAMPLE)!=1: raise ValueError('validated anchors drifted')
    encoded=', '.join(format(v,'.17g') for v in blends)
    right=(f'    # {MARKER} center=59 cycle=120 component=target_local_rest_direction\n' f'    var right_dynamic_direction_blend_schedule := PackedFloat64Array([{encoded}])\n' '    var right_dynamic_source_rest := normalized_target_local_direction * target_local_rest_origin.length()\n' '    var normalized_target_local_rest_origin := target_local_rest_origin\n')
    left=('    # Dynamic RightFoot source-direction candidates intentionally leave LeftFoot rest translation unchanged.\n' '    var normalized_target_left_local_rest_origin := target_left_local_rest_origin\n')
    sample=('        var right_dynamic_blend: float = right_dynamic_direction_blend_schedule[sample_idx % 120]\n' '        var right_dynamic_length: float = target_local_rest_origin.length()\n' '        var right_dynamic_mixed := target_local_rest_origin.lerp(right_dynamic_source_rest, right_dynamic_blend)\n' '        if right_dynamic_mixed.length() <= 0.000000001:\n' '            push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: dynamic source-direction blend became degenerate")\n' '            quit(20)\n            return\n' '        var right_dynamic_sample_rest := right_dynamic_mixed.normalized() * right_dynamic_length\n' '        if abs(right_dynamic_sample_rest.length() - right_dynamic_length) > 0.000001:\n' '            push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: dynamic source-direction blend changed RightFoot length")\n' '            quit(20)\n            return\n' '        var normalized_target_foot_origin := target_right_parent_pose.origin + target_right_parent_pose.basis * right_dynamic_sample_rest\n')
    out=text.replace(RIGHT,right,1).replace(LEFT,left,1).replace(SAMPLE,sample,1)
    if out.count(MARKER)!=1: raise ValueError('marker insertion failed')
    return out

def main()->int:
    p=argparse.ArgumentParser(); p.add_argument('input_probe',type=Path); p.add_argument('schedule_json',type=Path); p.add_argument('output_probe',type=Path); a=p.parse_args()
    payload=json.loads(a.schedule_json.read_text(encoding='utf-8')); a.output_probe.write_text(transform(a.input_probe.read_text(encoding='utf-8'),payload),encoding='utf-8'); print('CIV1_DYNAMIC_SOURCE_DIRECTION_NATIVE_PROBE_OK'); return 0
if __name__=='__main__': raise SystemExit(main())
