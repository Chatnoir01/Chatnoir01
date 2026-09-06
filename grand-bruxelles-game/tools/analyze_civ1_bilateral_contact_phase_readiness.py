#!/usr/bin/env python3
from __future__ import annotations
import json, sys
from pathlib import Path

MIN_STABLE_SAMPLES = 3
FRAME_COUNT = 120
CONTEXT_RADIUS = 1


def _load(path: Path) -> dict:
    data = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(data, dict):
        raise ValueError(f'expected object: {path}')
    return data


def _candidate_window(foot: dict) -> tuple[list[int], bool]:
    windows = foot.get('windows')
    if not isinstance(windows, list):
        raise ValueError('missing windows')
    eligible = [w for w in windows if w.get('eligible_vertical_stability_window') is True]
    candidates = [w for w in windows if isinstance(w.get('sample_indices'), list) and w.get('sample_indices')]
    if not candidates:
        raise ValueError('missing sample windows')
    best = max(candidates, key=lambda w: (len(w['sample_indices']), -int(w['sample_indices'][0])))
    samples = [int(x) for x in best['sample_indices']]
    return samples, bool(eligible)


def _expand(samples: list[int]) -> list[int]:
    start, end = min(samples), max(samples)
    out = []
    for i in range(start - CONTEXT_RADIUS, end + CONTEXT_RADIUS + 1):
        if 0 <= i < FRAME_COUNT:
            out.append(i)
    return out


def analyze(contact: dict, bilateral: dict) -> dict:
    if contact.get('schema') != 'grand-bruxelles-civ1-contact-windows-v4':
        raise ValueError('contact schema')
    if bilateral.get('schema') != 'grand-bruxelles-civ1-bilateral-landmark-promotion-v2':
        raise ValueError('bilateral schema')
    if bilateral.get('bilateral_identity_ready') is not True:
        raise ValueError('bilateral identity not ready')
    if contact.get('frame_count') != FRAME_COUNT:
        raise ValueError('frame count')
    if contact.get('minimum_vertical_stability_window_samples') != MIN_STABLE_SAMPLES:
        raise ValueError('minimum stable sample rail')
    for k in ('ground_contact_claimed','runtime_authorized','visual_approval_claimed','player_view_claimed'):
        if contact.get(k) is not False:
            raise ValueError('contact claim rail '+k)
    for k in ('bilateral_contact_phase_ready','quantitative_foot_slide_candidate','planted_contact_claimed','animation_correction_authorized','runtime_authorized','visual_approval_claimed','player_view_claimed'):
        if bilateral.get(k) is not False:
            raise ValueError('bilateral claim rail '+k)

    feet = contact.get('feet')
    if not isinstance(feet, dict) or set(feet) != {'LeftFoot','RightFoot'}:
        raise ValueError('feet contract')

    result = {}
    blockers = []
    for side in ('LeftFoot','RightFoot'):
        foot = feet[side]
        samples, has_eligible = _candidate_window(foot)
        stable_count = int(foot.get('vertical_stable_sample_count', -1))
        eligible_count = int(foot.get('eligible_vertical_stability_window_count', -1))
        ready = has_eligible and eligible_count >= 1 and len(samples) >= MIN_STABLE_SAMPLES
        reason = None if ready else 'vertical_stability_window_too_short_or_ineligible'
        if not ready:
            blockers.append({'side': side, 'reason': reason, 'observed_samples': samples, 'minimum_samples': MIN_STABLE_SAMPLES})
        result[side.lower()] = {
            'phase_ready': ready,
            'best_low_window_samples': samples,
            'best_low_window_sample_count': len(samples),
            'vertical_stable_sample_count': stable_count,
            'eligible_vertical_stability_window_count': eligible_count,
            'next_witness_samples': _expand(samples),
        }

    bilateral_ready = result['leftfoot']['phase_ready'] and result['rightfoot']['phase_ready']
    return {
        'schema':'grand-bruxelles-civ1-bilateral-contact-phase-readiness-v1',
        'diagnostic_only':True,
        'source_semantic':'deterministic_native_contact_windows_plus_independent_bilateral_landmark_identity',
        'minimum_vertical_stability_window_samples':MIN_STABLE_SAMPLES,
        'leftfoot':result['leftfoot'],
        'rightfoot':result['rightfoot'],
        'bilateral_contact_phase_ready':bilateral_ready,
        'blockers':blockers,
        'quantitative_foot_slide_candidate':False,
        'planted_contact_claimed':False,
        'animation_correction_authorized':False,
        'runtime_authorized':False,
        'visual_approval_claimed':False,
        'player_view_claimed':False,
        'verdict':'AMELIORER_BILATERAL_CONTACT_PHASE_READY_SOLE_EVIDENCE_REQUIRED' if bilateral_ready else 'AMELIORER_RIGHTFOOT_CONTACT_PHASE_TOO_SHORT_NO_PROMOTION',
    }


def main(argv: list[str]) -> int:
    if len(argv) != 4:
        print('usage: analyze_civ1_bilateral_contact_phase_readiness.py CONTACT.json BILATERAL.json OUT.json', file=sys.stderr)
        return 2
    try:
        out = analyze(_load(Path(argv[1])), _load(Path(argv[2])))
        Path(argv[3]).write_text(json.dumps(out, indent=2)+'\n', encoding='utf-8')
    except Exception as exc:
        print('CIV1_BILATERAL_CONTACT_PHASE_READINESS_FAIL:', exc, file=sys.stderr)
        return 3
    print('CIV1_BILATERAL_CONTACT_PHASE_READINESS_OK', out['leftfoot']['phase_ready'], out['rightfoot']['phase_ready'], out['bilateral_contact_phase_ready'])
    return 0

if __name__ == '__main__':
    raise SystemExit(main(sys.argv))
