#!/usr/bin/env python3
"""Regression: do not burn scheduler attempts on a measured, non-automatable height frontier."""
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("autonomous_citygen", HERE / "autonomous_citygen.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)


def write_json(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value), encoding="utf-8")


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    source = root / "source"
    cell = "bxl-e141000-n167000-s500"
    cell_dir = source / cell
    write_json(cell_dir / "manifest.json", {"cell_id": cell, "crs": "EPSG:31370", "layers": ["buildings"]})

    # Production has already reached the measured elevation frontier. The source
    # quality gate explicitly says the DSM/DTM pair is not ready, so repeatedly
    # scheduling per-building height derivation cannot make progress.
    for filename, _action in mod.EVIDENCE_STAGES[:8]:
        write_json(cell_dir / filename, {"cell_id": cell})
    write_json(
        cell_dir / "elevation_candidate_frontier.json",
        {
            "format": "grand-bruxelles-cell-elevation-candidate-frontier-v1",
            "cell_id": cell,
            "crs": "EPSG:31370",
            "next_action": "resolve_elevation_quality_blockers",
            "blockers": ["height_source_pair_not_ready", "delta_valid_ratio_below_0.95"],
            "heights": {"source_pair_ready": False, "next_gate": "resolve_height_source_pair_blockers"},
            "terrain": {"source_ready": False, "next_gate": "resolve_terrain_source_quality_blockers"},
            "runtime_promotion_allowed": False,
        },
    )

    progress, action = mod.evidence_plan(cell, source)
    assert progress == 8, (progress, action)
    assert action == "resolve_elevation_quality_blockers", action

    blocked = {
        "cell_id": cell,
        "state": "DATA_READY",
        "attempts": 18,
        "evidence_progress": progress,
        "next_action": action,
    }
    assert mod._autonomously_actionable(blocked) is False, blocked
    assert mod.select_batch([blocked], 1) == [], "blocked height frontier must not consume another attempt"

print("AUTONOMOUS_CITYGEN_BLOCKED_HEIGHT_FRONTIER_OK retries_stopped=true fail_closed=true")
