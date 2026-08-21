#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import tempfile
from pathlib import Path

MODULE = Path(__file__).with_name("select_secondary_height_validation_cell.py")
spec = importlib.util.spec_from_file_location("select_secondary_height_validation_cell", MODULE)
assert spec and spec.loader
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)


def cell(cell_id: str, bbox: list[int], *, state: str = "DATA_READY", progress: int = 10,
         stages: int = 10, municipalities: list[str] | None = None,
         next_action: str = selector.TARGET_NEXT_ACTION, actionable: bool = False) -> dict:
    return {
        "cell_id": cell_id,
        "bbox": bbox,
        "state": state,
        "evidence_progress": progress,
        "evidence_stage_count": stages,
        "municipalities": municipalities or ["anderlecht"],
        "next_action": next_action,
        "autonomous_actionable": actionable,
    }


report = {
    "cells": [
        cell("bxl-e141500-n167500-s500", [141500, 167500, 142000, 168000], state="MISSING_SOURCE", progress=0, actionable=True, next_action="materialize_authoritative_source"),
        cell("bxl-e142000-n167000-s500", [142000, 167000, 142500, 167500]),
        cell("bxl-e142000-n167500-s500", [142000, 167500, 142500, 168000]),
        cell("bxl-e142000-n168000-s500", [142000, 168000, 142500, 168500], progress=8),
        cell("bxl-e142500-n167500-s500", [142500, 167500, 143000, 168000], municipalities=["anderlecht", "molenbeek-saint-jean"]),
    ]
}
available = {
    "bxl-e142000-n167000-s500",
    "bxl-e142000-n167500-s500",
    "bxl-e142500-n167500-s500",
}
chosen = selector.select(report, available, "anderlecht")
assert chosen["cell_id"] == "bxl-e142000-n167000-s500", chosen
assert chosen["bbox_epsg31370"] == [142000, 167000, 142500, 167500]
assert chosen["eligible_cell_count"] == 2
assert chosen["runtime_promotion_allowed"] is False
assert chosen["runtime_approved"] is False

# Durable inventory is part of the contract: if the first ready cell vanishes,
# selection deterministically advances to the next fully evidenced one.
chosen_next = selector.select(report, {"bxl-e142000-n167500-s500"}, "anderlecht")
assert chosen_next["cell_id"] == "bxl-e142000-n167500-s500"

# A boundary cell cannot be validated from one municipality package alone.
boundary_only = {
    "cells": [cell("bxl-e142500-n167500-s500", [142500, 167500, 143000, 168000], municipalities=["anderlecht", "molenbeek-saint-jean"])]
}
try:
    selector.select(boundary_only, {"bxl-e142500-n167500-s500"}, "anderlecht")
except ValueError as exc:
    assert "no durable fully-evidenced" in str(exc)
else:
    raise AssertionError("boundary cell unexpectedly selected")

# No incomplete/MISSING_SOURCE cell may be used merely to keep CI green.
not_ready = {
    "cells": [
        cell("bxl-e141500-n167500-s500", [141500, 167500, 142000, 168000], state="MISSING_SOURCE", progress=0, actionable=True, next_action="materialize_authoritative_source"),
        cell("bxl-e142000-n168000-s500", [142000, 168000, 142500, 168500], progress=8),
    ]
}
try:
    selector.select(not_ready, {"bxl-e141500-n167500-s500", "bxl-e142000-n168000-s500"}, "anderlecht")
except ValueError as exc:
    assert "no durable fully-evidenced" in str(exc)
else:
    raise AssertionError("incomplete cell unexpectedly selected")

# Cell identity and 500m bbox are coupled; do not silently reinterpret geography.
bad_bbox = {"cells": [cell("bxl-e142000-n167000-s500", [142000, 167000, 142600, 167500])]}
try:
    selector.select(bad_bbox, {"bxl-e142000-n167000-s500"}, "anderlecht")
except ValueError as exc:
    assert "bbox does not match" in str(exc)
else:
    raise AssertionError("invalid bbox unexpectedly accepted")

# Duplicate report identities are ambiguous and fail closed.
duplicate = {"cells": [report["cells"][1], report["cells"][1]]}
try:
    selector.select(duplicate, {"bxl-e142000-n167000-s500"}, "anderlecht")
except ValueError as exc:
    assert "duplicate cell" in str(exc)
else:
    raise AssertionError("duplicate cell unexpectedly accepted")

# CLI inventory parsing rejects malformed durable entries.
with tempfile.TemporaryDirectory() as tmp:
    p = Path(tmp) / "available.txt"
    p.write_text("not-a-cell\n", encoding="utf-8")
    try:
        selector._available_cells(p)
    except ValueError as exc:
        assert "invalid durable source cell id" in str(exc)
    else:
        raise AssertionError("malformed durable cell id unexpectedly accepted")

print("CITYGEN_SECONDARY_HEIGHT_TARGET_TEST_OK selected=bxl-e142000-n167000-s500 dynamic=true boundary_fail_closed=true runtime_promotion=false")
