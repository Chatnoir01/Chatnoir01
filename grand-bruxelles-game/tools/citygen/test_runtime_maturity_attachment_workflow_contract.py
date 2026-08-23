#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
workflow = ROOT / '.github/workflows/grand-bruxelles-runtime-maturity-attachment.yml'
source_repair = ROOT / '.github/workflows/grand-bruxelles-citygen-source-repair-frontier.yml'
text = workflow.read_text(encoding='utf-8')
repair_text = source_repair.read_text(encoding='utf-8')

assert 'Grand Bruxelles Runtime Candidate Frontier' in text
assert "group: grand-bruxelles-autonomous-citygen" in text
assert "cancel-in-progress: false" in text
assert "group: grand-bruxelles-autonomous-citygen" in repair_text
assert "citygen-autonomous-state" in text
assert "citygen-runtime-candidates" in text
assert "--force-with-lease=\"refs/heads/citygen-autonomous-state:${REMOTE_SHA}\"" in text
assert "attach_runtime_candidate_maturity.py" in text
assert "runtime_mount_authorized': False" in text
assert "jouable_promotion_authorized': False" in text
assert "maturity_state_promotion_authorized': False" in text
assert "runtime_geometry" in text
assert "git push origin HEAD:refs/heads/main" not in text
assert "JOUABLE" not in text or "jouable_promotion_authorized" in text

print('RUNTIME_MATURITY_ATTACHMENT_WORKFLOW_OK shared_writer_lock=true force_with_lease=true runtime_geometry_only=true main_mutation=false promotion_bypass=false')
