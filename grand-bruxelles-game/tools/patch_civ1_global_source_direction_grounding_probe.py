#!/usr/bin/env python3
"""Patch the validated CIV-1 bilateral probe with the proven full source-direction candidate plus grounding evidence."""
from __future__ import annotations
import argparse
from pathlib import Path
RIGHT='    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n'
LEFT='    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n'
SAMPLES='    var model_space_samples: Array[Dictionary] = []\n'
APPEND='        normalized_target_right_foot_y.append(normalized_hips_relative.y)\n'
SUMMARY='    var phase_vertical_summary := _vertical_phase_summary(model_space_samples, animation.length)\n'
MARKER='CIV1_GLOBAL_SOURCE_DIRECTION_GROUNDING_PROBE'

def transform(text:str)->str:
    if MARKER in text: raise ValueError('input already patched')
    if 'func _make_shadow_skeleton' not in text or 'left_foot_reference_ab' not in text: raise ValueError('input is not validated bilateral shadow probe')
    for anchor in (RIGHT,LEFT,SAMPLES,APPEND,SUMMARY):
        if text.count(anchor)!=1: raise ValueError('validated probe anchor drifted')
    right=(f'    # {MARKER} blend=1 component=target_local_rest_direction constant_over_cycle=true\n'
           '    var global_source_direction_rest := normalized_target_local_direction * target_local_rest_origin.length()\n'
           '    if global_source_direction_rest.length() <= 0.000000001:\n        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: source direction degenerate")\n        quit(20)\n        return\n'
           '    var normalized_target_local_rest_origin := global_source_direction_rest.normalized() * target_local_rest_origin.length()\n')
    left='    # RightFoot-only candidate: LeftFoot control remains unchanged.\n    var normalized_target_left_local_rest_origin := target_left_local_rest_origin\n'
    out=text.replace(RIGHT,right,1).replace(LEFT,left,1)
    out=out.replace(SAMPLES,SAMPLES+'    var normalized_target_right_foot_positions: Array[Array] = []\n',1)
    out=out.replace(APPEND,APPEND+'        normalized_target_right_foot_positions.append(_v3(normalized_hips_relative))\n',1)
    out=out.replace(SUMMARY,SUMMARY+'    # Persist full-cycle candidate trajectory for explicit support-plane/slide assessment.\n',1)
    needle='    var right_foot_reference_ab := _reference_ab_summary(\n'
    if out.count(needle)!=1: raise ValueError('reference summary anchor drifted')
    end='        animation.length,\n    )\n'
    idx=out.find(needle); endidx=out.find(end,idx)
    if endidx<0: raise ValueError('reference summary terminator drifted')
    endidx += len(end)
    out=out[:endidx]+'    right_foot_reference_ab["normalized_target_hips_relative_samples"] = normalized_target_right_foot_positions\n'+out[endidx:]
    if out.count(MARKER)!=1: raise ValueError('marker insertion failed')
    return out

def main()->int:
    p=argparse.ArgumentParser(); p.add_argument('input_probe',type=Path); p.add_argument('output_probe',type=Path); a=p.parse_args()
    a.output_probe.write_text(transform(a.input_probe.read_text(encoding='utf-8')),encoding='utf-8'); print('CIV1_GLOBAL_SOURCE_DIRECTION_GROUNDING_PROBE_OK'); return 0
if __name__=='__main__': raise SystemExit(main())
