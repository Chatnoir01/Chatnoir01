#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TRIGGER = ROOT / ".github" / "workflows" / "grand-bruxelles-citygen-post-merge-trigger.yml"
AUTONOMOUS = ROOT / ".github" / "workflows" / "grand-bruxelles-autonomous-citygen.yml"

trigger_text = TRIGGER.read_text(encoding="utf-8")
on_start = trigger_text.index("on:\n")
permissions_start = trigger_text.index("\npermissions:", on_start)
trigger_block = trigger_text[on_start:permissions_start]

assert "  push:\n" in trigger_block, "relevant CityGen merges must trigger an immediate fresh-main pass"
assert "    branches: [main]\n" in trigger_block, "post-merge trigger must be restricted to main"
for required_path in [
    '      - "grand-bruxelles-game/tools/citygen/**"',
    '      - "grand-bruxelles-game/tools/match_urbis3d_semantic_heights.py"',
    '      - "grand-bruxelles-game/tools/test_match_urbis3d_semantic_heights.py"',
    '      - ".github/workflows/grand-bruxelles-autonomous-citygen.yml"',
    '      - ".github/workflows/grand-bruxelles-citygen-state-refresh.yml"',
    '      - ".github/workflows/grand-bruxelles-citygen-post-merge-trigger.yml"',
    '      - ".github/workflows/grand-bruxelles-urbis3d-semantic-height-generic.yml"',
]:
    assert required_path in trigger_block, f"missing main-push path guard: {required_path}"

assert "  actions: write\n" in trigger_text, "dispatch workflow needs Actions write permission"
assert "gh workflow run grand-bruxelles-autonomous-citygen.yml" in trigger_text
assert '--ref main' in trigger_text, "dispatch must resolve the exact live main ref"
assert '-f batch_size=4' in trigger_text, "post-merge pass must keep the established bounded batch size"

autonomous_text = AUTONOMOUS.read_text(encoding="utf-8")
assert "  workflow_dispatch:\n" in autonomous_text, "target Autonomous CityGen workflow must remain dispatchable"
assert "if: github.event_name != 'pull_request'" in autonomous_text, "dispatched runs must execute the real evidence pass"

print("AUTONOMOUS_CITYGEN_MAIN_PUSH_TRIGGER_OK")
