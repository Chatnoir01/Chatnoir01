#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "civ1_postwindow_reversal.py"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-postwindow-reversal.yml"


def require(text: str, needle: str) -> None:
    assert needle in text, f"missing contract token: {needle}"


def main() -> int:
    script = SCRIPT.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        'OUTPUT_SCHEMA = "grand-bruxelles-civ1-postwindow-reversal-v1"',
        'PHASE_SAMPLES = [68, 69, 70, 71]',
        'len(frames) != 120',
        'y_series(frames, "RightFoot")',
        'y_series(frames, "RightToeBase")',
        'values[i] - values[i - 1] < 0.0',
        'values[i + 1] - values[i] >= 0.0',
        '"candidate_is_ground_contact_proof": False',
        '"quantitative_foot_slide_candidate": False',
        '"animation_correction_authorized": False',
        '"runtime_authorized": False',
        '"player_view_claimed": False',
    ):
        require(script, token)

    for forbidden in ('percentile', 'WEIGHT_THRESHOLD', 'camera rescue', 'viewport rescue'):
        assert forbidden not in script

    require(workflow, 'be06017ae3c759e418c35db395addb111bb984b4')
    require(workflow, '10040629198')
    require(workflow, '353f091fe482abfe21e026ab31264315580bbfa463e9d384713cab45e88f4f87')
    require(workflow, '9996432028')
    require(workflow, '9b4dd309157ce1f3e5aae44125f5931fac409238eece1a0632b8ad07933ebb00')
    print('CIV1_POSTWINDOW_REVERSAL_CONTRACT_OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
