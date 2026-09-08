#!/usr/bin/env python3
import ast
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools" / "civ1_postwindow_reversal.py"
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-civ1-postwindow-reversal.yml"


def require(text: str, needle: str) -> None:
    assert needle in text, f"missing contract token: {needle}"


def has_strict_righttoe_call(source: str) -> bool:
    tree = ast.parse(source)
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if not isinstance(node.func, ast.Name) or node.func.id != "y_series":
            continue
        if len(node.args) < 2:
            continue
        bone = node.args[1]
        if isinstance(bone, ast.Constant) and bone.value == "RightToeBase":
            return True
    return False


def main() -> int:
    script = SCRIPT.read_text(encoding="utf-8")
    workflow = WORKFLOW.read_text(encoding="utf-8")

    for token in (
        'OUTPUT_SCHEMA = "grand-bruxelles-civ1-postwindow-reversal-v2"',
        'TOE_SCHEMA = "grand-bruxelles-civ1-righttoebase-pose-v1"',
        'PHASE_SAMPLES = [68, 69, 70, 71]',
        'len(frames) != 120',
        'y_series(frames, "RightFoot")',
        'toe_relative_transform(toe_pose)',
        'reconstruct_toe_series(frames, toe_local)',
        'validate_toe_anchor_samples(frames, toe_pose, toe_local)',
        '"righttoebase_series_available": True',
        '"righttoebase_series_coverage_count": len(toe)',
        '"righttoebase_anchor_max_origin_error_m": toe_anchor_error',
        '"toe_coverage_required_before_common_candidate": False',
        '"candidate_is_ground_contact_proof": False',
        '"quantitative_foot_slide_candidate": False',
        '"animation_correction_authorized": False',
        '"runtime_authorized": False',
        '"player_view_claimed": False',
    ):
        require(script, token)

    assert not has_strict_righttoe_call(script), "strict RightToeBase y_series access reintroduced"
    for forbidden in ('percentile', 'WEIGHT_THRESHOLD', 'camera rescue', 'viewport rescue'):
        assert forbidden not in script

    require(workflow, '313b4a67de2eff70035690127ec1aaa367954881')
    require(workflow, '10040629198')
    require(workflow, '353f091fe482abfe21e026ab31264315580bbfa463e9d384713cab45e88f4f87')
    require(workflow, '9996432028')
    require(workflow, '9b4dd309157ce1f3e5aae44125f5931fac409238eece1a0632b8ad07933ebb00')
    require(workflow, '10024557192')
    require(workflow, '3ec94d7b8ed10663d0ee17bf44ffec77104600a7c3006343f0dfbae13877023c')
    require(workflow, 'righttoebase-pose.json')
    require(workflow, 'run-context.txt')
    print('CIV1_POSTWINDOW_REVERSAL_CONTRACT_OK')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
