#!/usr/bin/env python3
"""Fail closed if Anneessens machine evidence can self-authorize visual acceptance."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
WORKFLOW = ROOT.parent / ".github" / "workflows" / "grand-bruxelles-anneessens-automatic-road-player-witness.yml"
FINALIZER = ROOT / "game" / "tests" / "finalize_anneessens_human_review_policy.py"

workflow = WORKFLOW.read_text(encoding="utf-8")
finalizer = FINALIZER.read_text(encoding="utf-8")

assert '"human_review_required": True' in workflow
assert '"destination_advertisable": False' in workflow
assert '"jouable_authorized": False' in workflow
assert "finalize_anneessens_human_review_policy.py" in workflow

validation_call = "validate_anneessens_player_witness_evidence.py"
finalizer_call = "finalize_anneessens_human_review_policy.py"
assert workflow.index(validation_call) < workflow.rindex(finalizer_call), (
    "human-review policy must finalize the already integrity-validated evidence before upload"
)
assert workflow.rindex(finalizer_call) < workflow.index("Upload exact Anneessens player-view evidence")

assert 'payload["candidate_meets_frozen_ray_rule"] = candidate_meets_frozen_ray_rule' in finalizer
assert 'payload["visual_acceptance"] = False' in finalizer
assert 'payload.get("human_review_required") is not True' in finalizer
assert 'payload.get("destination_advertisable") is not False' in finalizer
assert 'payload.get("jouable_authorized") is not False' in finalizer
assert 'finalized.get("visual_acceptance") is not False' in finalizer

print("ANNEESSENS_HUMAN_VISUAL_ACCEPTANCE_CONTRACT_GREEN")
