#!/usr/bin/env python3
import json
import tempfile
from pathlib import Path

from build_source_repair_worklist import (
    MAX_FRONTIER,
    MAX_SHARDS,
    REPORT_FORMAT,
    WORKLIST_FORMAT,
    select_source_repairs,
    write_outputs,
)


def make_cell(index: int, incomplete: bool = False) -> dict:
    east = 140000 + (index % 20) * 500
    north = 160000 + (index // 20) * 500
    return {
        "cell_id": f"bxl-e{east}-n{north}-s500",
        "state": "MISSING_SOURCE",
        "autonomous_actionable": True,
        "bbox": [east, north, east + 500, north + 500],
        "municipalities": [f"municipality-{index % 19:02d}"],
        "attempts": index % 5,
        "blockers": [
            "missing_authoritative_source_file:buildings.geojson"
            if incomplete
            else "authoritative_source_cell_missing"
        ],
    }


report = {
    "format": REPORT_FORMAT,
    "cells": [make_cell(index, incomplete=index < 10) for index in reversed(range(160))],
}
selected = select_source_repairs(report, MAX_FRONTIER, MAX_SHARDS)

assert len(selected) == 128
assert len({row["cell_id"] for row in selected}) == 128
assert {name for row in selected for name in row["municipalities"]} == {
    f"municipality-{index:02d}" for index in range(19)
}

shard_sizes = {index: 0 for index in range(MAX_SHARDS)}
for row in selected:
    shard_sizes[row["shard"]] += 1
assert set(shard_sizes.values()) == {8}, shard_sizes

incomplete_ids = {make_cell(index, incomplete=True)["cell_id"] for index in range(10)}
selected_ids = {row["cell_id"] for row in selected}
assert incomplete_ids <= selected_ids, "incomplete authoritative payload repairs must not be starved"

with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    summary = write_outputs(
        selected,
        root / "repair_worklist.tsv",
        root / "summary.json",
        MAX_FRONTIER,
        MAX_SHARDS,
    )
    assert summary["format"] == WORKLIST_FORMAT
    assert summary["selected_count"] == 128
    assert summary["selected_municipality_count"] == 19
    assert summary["max_shard_size"] == 8
    assert summary["runtime_mount_authorized"] is False
    assert summary["jouable_promotion_authorized"] is False
    assert len((root / "repair_worklist.tsv").read_text(encoding="utf-8").splitlines()) == 128
    persisted = json.loads((root / "summary.json").read_text(encoding="utf-8"))
    assert persisted == summary

try:
    select_source_repairs(report, MAX_FRONTIER + 1, MAX_SHARDS)
except ValueError as exc:
    assert "limit must be between" in str(exc)
else:
    raise AssertionError("frontier limit above 128 must fail closed")

try:
    select_source_repairs(report, MAX_FRONTIER, MAX_SHARDS + 1)
except ValueError as exc:
    assert "shards must be between" in str(exc)
else:
    raise AssertionError("shard count above 16 must fail closed")

bad = {
    "format": REPORT_FORMAT,
    "cells": [
        {
            **make_cell(0),
            "bbox": [1, 2, 3],
        }
    ],
}
try:
    select_source_repairs(bad, 1, 1)
except ValueError as exc:
    assert "canonical bbox" in str(exc)
else:
    raise AssertionError("invalid repair bbox must fail closed")

print(
    "SOURCE_REPAIR_FANOUT_SELECTOR_TEST_OK "
    "frontier=128 shards=16 max_per_shard=8 municipalities=19 "
    "incomplete_payload_priority=true promotion_bypass=false"
)
