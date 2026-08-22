#!/usr/bin/env python3
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("autonomous_citygen", HERE / "autonomous_citygen.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def row(cell_id, state, municipality, *, attempts=0, progress=0, blockers=None):
    return {
        "cell_id": cell_id,
        "state": state,
        "attempts": attempts,
        "evidence_progress": progress,
        "blockers": blockers or [],
        "municipalities": [municipality],
    }


# Build a deliberately hostile ordering: 40 already-materialized DATA_READY cells
# all belong to the same municipality, while the other 18 municipalities only
# have MISSING_SOURCE candidates. The historic priority-only selector would fill
# a 32-cell pass from the first municipality and starve the rest of Brussels.
cells = [
    row(f"bxl-e{100000 + i * 500}-n100000-s500", "DATA_READY", "municipality-00", progress=5)
    for i in range(40)
]
for index in range(1, mod.REGIONAL_MUNICIPALITY_TARGET):
    cells.append(
        row(
            f"bxl-e{130000 + index * 500}-n130000-s500",
            "MISSING_SOURCE",
            f"municipality-{index:02d}",
        )
    )

selected = mod.select_batch(cells, 32)
assert len(selected) == 32, selected
selected_rows = [cell for cell in cells if cell["cell_id"] in set(selected)]
covered = {name for cell in selected_rows for name in cell["municipalities"]}
assert len(covered) == mod.REGIONAL_MUNICIPALITY_TARGET, sorted(covered)
assert covered == {f"municipality-{index:02d}" for index in range(mod.REGIONAL_MUNICIPALITY_TARGET)}

# Default/small passes must remain backward-compatible and keep the established
# maturity-first ordering instead of forcing regional expansion.
small = mod.select_batch(cells, 4)
assert small == [cell["cell_id"] for cell in cells[:4]], small

# Within a municipality, the existing fail-closed source-repair priority still
# wins over an ordinary missing source candidate.
repair = row(
    "bxl-e199000-n199000-s500",
    "MISSING_SOURCE",
    "municipality-05",
    blockers=["missing_authoritative_source_file:buildings:raw/buildings.geojson"],
)
regular = row("bxl-e199500-n199000-s500", "MISSING_SOURCE", "municipality-05")
regional_with_repair = cells + [regular, repair]
selected_with_repair = mod.select_batch(regional_with_repair, 32)
assert repair["cell_id"] in selected_with_repair, selected_with_repair

print(
    "AUTONOMOUS_CITYGEN_MUNICIPALITY_BALANCE_OK "
    "municipalities=19 batch=32 small_batch_legacy=true repair_priority=true promotion_bypass=false"
)
