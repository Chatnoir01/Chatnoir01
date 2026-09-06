from pathlib import Path
import re

WORKFLOW = Path(__file__).parents[2] / ".github/workflows/grand-bruxelles-missing-road-source-batch.yml"
SELF = "test_missing_road_source_workflow_test_coverage.py"


def _workflow_test_sets(text: str) -> tuple[set[str], set[str]]:
    watched = set(re.findall(r"- 'grand-bruxelles-game/tests/(test_[A-Za-z0-9_]+\.py)'", text))
    marker = "- name: Validate exact missing-source registry and immutable acquisition evidence"
    assert marker in text, "missing dedicated Data validation step"
    validation = text.split(marker, 1)[1].split("\n\n  acquire-unresolved-road-sources:", 1)[0]
    executed = set(re.findall(r"\btests/(test_[A-Za-z0-9_]+\.py)\b", validation))
    return watched, executed


def test_missing_road_source_workflow_watches_and_executes_exact_same_regressions():
    watched, executed = _workflow_test_sets(WORKFLOW.read_text(encoding="utf-8"))
    assert SELF in watched, f"dedicated gate does not watch its own coverage regression: {SELF}"
    assert SELF in executed, f"dedicated gate does not execute its own coverage regression: {SELF}"
    assert watched == executed, f"workflow test drift: watched_only={sorted(watched-executed)} executed_only={sorted(executed-watched)}"
