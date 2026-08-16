#!/usr/bin/env python3
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[3] / ".github" / "workflows" / "grand-bruxelles-autonomous-citygen.yml"
text = WORKFLOW.read_text(encoding="utf-8")

start = text.index("      - name: Derive and resolve elevation requirements")
end = text.index("      - name: Download hash and structurally validate official archives", start)
step = text[start:end]

assert "ELEVATION_REQUIREMENTS_PENDING ${CELL}" in step, "missing maturity must be isolated as per-cell pending evidence"
assert 'REQLOG="/tmp/citygen-out/elevation-resolution-errors/${CELL}-requirements.log"' in step
assert 'if python3 grand-bruxelles-game/tools/citygen/build_cell_elevation_requirements.py' in step
assert 'rm -f "$D/elevation_requirements.json" "$D/elevation_dsm_resolution.json" "$D/elevation_dtm_resolution.json"' in step
assert "continue" in step, "failed requirement derivation must not abort or resolve stale requirements"

print("AUTONOMOUS_ELEVATION_REQUIREMENT_ISOLATION_OK")
