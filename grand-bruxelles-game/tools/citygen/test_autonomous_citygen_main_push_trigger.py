#!/usr/bin/env python3
from pathlib import Path

WORKFLOW = Path(__file__).resolve().parents[3] / ".github" / "workflows" / "grand-bruxelles-autonomous-citygen.yml"
text = WORKFLOW.read_text(encoding="utf-8")

on_start = text.index("on:\n")
permissions_start = text.index("\npermissions:", on_start)
trigger_block = text[on_start:permissions_start]

assert "  push:\n" in trigger_block, "Autonomous CityGen must run immediately after relevant CityGen merges to main"
assert "    branches: [main]\n" in trigger_block, "post-merge trigger must be restricted to main"
for required_path in [
    '      - "grand-bruxelles-game/tools/citygen/**"',
    '      - ".github/workflows/grand-bruxelles-autonomous-citygen.yml"',
]:
    assert required_path in trigger_block, f"missing main-push path guard: {required_path}"

print("AUTONOMOUS_CITYGEN_MAIN_PUSH_TRIGGER_OK")
