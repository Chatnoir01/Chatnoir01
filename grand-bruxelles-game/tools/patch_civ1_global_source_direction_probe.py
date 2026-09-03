#!/usr/bin/env python3
"""Patch the validated CIV-1 bilateral probe with a constant global source-direction blend."""
from __future__ import annotations
import argparse, math
from pathlib import Path

RIGHT='    var normalized_target_local_rest_origin := normalized_target_local_direction * target_local_rest_origin.length()\n'
LEFT='    var normalized_target_left_local_rest_origin := normalized_target_left_local_direction * target_left_local_rest_origin.length()\n'
MARKER='CIV1_GLOBAL_SOURCE_DIRECTION_BLEND_PROBE'


def validate_blend(value: float) -> float:
    if isinstance(value, bool):
        raise ValueError('blend must be numeric')
    blend=float(value)
    if not math.isfinite(blend) or not 0.0 < blend <= 1.0:
        raise ValueError('blend must be finite and in (0,1]')
    return blend


def transform(text: str, blend: float) -> str:
    blend=validate_blend(blend)
    if MARKER in text:
        raise ValueError('input already patched')
    if 'func _make_shadow_skeleton' not in text or 'left_foot_reference_ab' not in text:
        raise ValueError('input is not validated bilateral shadow probe')
    if text.count(RIGHT)!=1 or text.count(LEFT)!=1:
        raise ValueError('validated rest anchors drifted')
    replacement=(
        f'    # {MARKER} blend={blend:.17g} component=target_local_rest_direction constant_over_cycle=true\n'
        f'    var global_source_direction_blend: float = {blend:.17g}\n'
        '    var global_source_direction_rest := normalized_target_local_direction * target_local_rest_origin.length()\n'
        '    var global_source_direction_mixed := target_local_rest_origin.lerp(global_source_direction_rest, global_source_direction_blend)\n'
        '    if global_source_direction_mixed.length() <= 0.000000001:\n'
        '        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: global source-direction blend became degenerate")\n'
        '        quit(20)\n'
        '        return\n'
        '    var normalized_target_local_rest_origin := global_source_direction_mixed.normalized() * target_local_rest_origin.length()\n'
        '    if abs(normalized_target_local_rest_origin.length() - target_local_rest_origin.length()) > 0.000001:\n'
        '        push_error("CIV1_GLOBAL_CHAIN_DIAGNOSTIC_FAIL: global source-direction blend changed RightFoot length")\n'
        '        quit(20)\n'
        '        return\n'
    )
    left=(
        '    # Global RightFoot source-direction probe intentionally leaves LeftFoot unchanged.\n'
        '    var normalized_target_left_local_rest_origin := target_left_local_rest_origin\n'
    )
    out=text.replace(RIGHT,replacement,1).replace(LEFT,left,1)
    if out.count(MARKER)!=1:
        raise ValueError('marker insertion failed')
    return out


def main()->int:
    p=argparse.ArgumentParser()
    p.add_argument('input_probe', type=Path)
    p.add_argument('output_probe', type=Path)
    p.add_argument('--blend', type=float, required=True)
    a=p.parse_args()
    a.output_probe.write_text(transform(a.input_probe.read_text(encoding='utf-8'), a.blend),encoding='utf-8')
    print('CIV1_GLOBAL_SOURCE_DIRECTION_BLEND_PROBE_OK')
    return 0


if __name__=='__main__':
    raise SystemExit(main())
