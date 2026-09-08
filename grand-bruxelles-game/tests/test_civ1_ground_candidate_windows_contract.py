#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "civ1_ground_candidate_windows.py"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-ground-candidate-windows.yml"


def require(text: str, needle: str) -> None:
    assert needle in text, f"missing contract token: {needle}"


def main() -> int:
    script = SCRIPT.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        'OUTPUT_SCHEMA = "grand-bruxelles-civ1-ground-candidate-windows-v1"',
        'PHASE_SAMPLES = [68, 69, 70, 71]',
        'len(frames) != 120',
        'foot_candidates = reversals(foot_y)',
        'toe_candidates = reversals(toe_y)',
        'evidence_windows(foot_candidates, toe_candidates, len(frames))',
        '"same_sample_ground_geometry_windows": windows',
        '"window_semantics": "kinematic-reversal-neighborhood-only"',
        '"requires_canonical_ground_same_sample": True',
        '"requires_skinned_geometry_same_sample": True',
        '"candidate_is_ground_contact_proof": False',
        '"planted_interval_claimable": False',
        '"quantitative_foot_slide_candidate": False',
        '"animation_correction_authorized": False',
        '"runtime_authorized": False',
        '"visual_approval_claimed": False',
        '"player_view_claimed": False',
    ):
        require(script, token)

    for forbidden in (
        'percentile',
        'WEIGHT_THRESHOLD',
        'camera rescue',
        'viewport rescue',
        'exact_common_reversal_required',
    ):
        assert forbidden not in script

    require(workflow, '1a2210270477f3e20b5127a42a7b3e13000a624c')
    require(workflow, '9996432028')
    require(workflow, '9b4dd309157ce1f3e5aae44125f5931fac409238eece1a0632b8ad07933ebb00')
    require(workflow, '10024557192')
    require(workflow, '3ec94d7b8ed10663d0ee17bf44ffec77104600a7c3006343f0dfbae13877023c')
    require(workflow, "assert r['rightfoot_reversal_candidates']==[25,44,60,67,71]")
    require(workflow, "assert r['righttoebase_reversal_candidates']==[40,43,59,72,94]")
    require(workflow, "assert r['exact_common_reversal_candidates']==[]")
    require(workflow, "assert r['window_count']==10")
    require(workflow, 'run-context.txt')

    print('CIV1_GROUND_CANDIDATE_WINDOWS_CONTRACT_OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
