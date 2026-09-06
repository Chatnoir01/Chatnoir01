#!/usr/bin/env python3
"""Fail closed if Anneessens machine evidence can self-authorize visual acceptance."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-anneessens-automatic-road-player-witness.yml"
VALIDATOR = ROOT / "game" / "tests" / "validate_anneessens_player_witness_evidence.py"

workflow = WORKFLOW.read_text(encoding="utf-8")
validator = VALIDATOR.read_text(encoding="utf-8")

assert '"human_review_required": True' in workflow
assert '"destination_advertisable": False' in workflow
assert '"jouable_authorized": False' in workflow
assert '"visual_acceptance": False' in workflow, (
    "Anneessens evidence must stay fail-closed until an explicit human review receipt exists"
)
assert '"candidate_meets_frozen_ray_rule": candidate_meets_frozen_ray_rule' in workflow

assert 'payload["visual_acceptance"] is not False' in validator
assert 'payload["human_review_required"] is not True' in validator
assert 'payload["candidate_meets_frozen_ray_rule"] is not expected_ray_candidate' in validator
assert 'expected_visual_acceptance = len(traces) == 3' not in validator

print("ANNEESSENS_HUMAN_VISUAL_ACCEPTANCE_CONTRACT_GREEN")
