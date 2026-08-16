#!/usr/bin/env python3
"""Consolidate the already source-locked adjacent Bourse StreetSurfaces.

Compatibility entrypoint for the Bourse proportions lot. It deliberately consumes the
exact official polygons already persisted on current main instead of re-querying or
reinterpreting UrbIS TYPE values. It never grants runtime approval.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data" / "urbis"
ADJACENT_FILES = (
    "bourse_street_surfaces_adjacent_22982.game.json",
    "bourse_street_surfaces_adjacent_41098.game.json",
    "bourse_street_surfaces_adjacent_41084.game.json",
    "bourse_street_surfaces_adjacent_21944.game.json",
)
EXPECTED_SCHEMA = "grand-bruxelles-urbis-bourse-surfaces-v1"


def _load(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema") != EXPECTED_SCHEMA:
        raise ValueError(f"unsupported Bourse StreetSurface schema in {path}: {data.get('schema')!r}")
    if data.get("runtime_approved") is not False or data.get("realism_complete") is not False:
        raise ValueError(f"source-locked Bourse surface must remain unapproved: {path}")
    return data


def consolidate(paths: tuple[str, ...] = ADJACENT_FILES) -> dict[str, Any]:
    rows: list[dict[str, Any]] = []
    source_paths: list[str] = []
    seen: set[str] = set()
    for name in paths:
        path = DATA_DIR / name
        data = _load(path)
        source_paths.append(path.relative_to(ROOT).as_posix())
        for raw in data.get("surfaces", []):
            if not isinstance(raw, dict):
                continue
            inspire_id = str(raw.get("inspire_id", ""))
            if not inspire_id:
                raise ValueError(f"surface without INSPIRE id in {path}")
            if inspire_id in seen:
                raise ValueError(f"duplicate adjacent Bourse StreetSurface: {inspire_id}")
            if int(raw.get("level", 999)) != 0:
                raise ValueError(f"adjacent Bourse StreetSurface is not LVL=0: {inspire_id}")
            rings = raw.get("world_rings_xz", [])
            if not isinstance(rings, list) or len(rings) != 1 or len(rings[0]) < 4:
                raise ValueError(f"invalid world polygon for {inspire_id}")
            seen.add(inspire_id)
            rows.append(raw)

    rows.sort(key=lambda row: str(row["inspire_id"]))
    return {
        "schema": "grand-bruxelles-bourse-adjacent-street-surfaces-v1",
        "basis": "exact source-locked current-main UrbIS StreetSurface runtime files",
        "source_paths": source_paths,
        "surface_count": len(rows),
        "surfaces": rows,
        "type_semantics_interpreted": False,
        "runtime_approved": False,
        "realism_complete": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = consolidate()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(
        "BOURSE_ADJACENT_STREET_SURFACES_OK",
        output["surface_count"],
        [row["inspire_id"] for row in output["surfaces"]],
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
