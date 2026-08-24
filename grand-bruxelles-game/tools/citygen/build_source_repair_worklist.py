#!/usr/bin/env python3
"""Build a deterministic, municipality-balanced source-repair fan-out worklist."""
from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any

REPORT_FORMAT = "grand-bruxelles-autonomous-citygen-v1"
WORKLIST_FORMAT = "grand-bruxelles-source-repair-worklist-v2"
MAX_FRONTIER = 128
MAX_SHARDS = 16


def _read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _municipalities(cell: dict[str, Any]) -> list[str]:
    values = cell.get("municipalities") or []
    if not isinstance(values, list):
        return []
    return sorted({str(value).strip() for value in values if str(value).strip()})


def _validate_bbox(cell_id: str, bbox: Any) -> list[int | float]:
    if not isinstance(bbox, list) or len(bbox) != 4 or not all(isinstance(v, (int, float)) for v in bbox):
        raise ValueError(f"missing source has no canonical bbox: {cell_id}")
    if not (bbox[0] < bbox[2] and bbox[1] < bbox[3]):
        raise ValueError(f"invalid bbox for source repair: {cell_id}")
    return bbox


def _repair_priority(cell: dict[str, Any]) -> tuple[int, int, str]:
    blockers = [str(item) for item in (cell.get("blockers") or [])]
    incomplete_payload = any(item.startswith("missing_authoritative_source_file:") for item in blockers)
    return (
        0 if incomplete_payload else 1,
        int(cell.get("attempts", 0)),
        str(cell.get("cell_id", "")),
    )


def select_source_repairs(report: dict[str, Any], limit: int, shards: int) -> list[dict[str, Any]]:
    if report.get("format") != REPORT_FORMAT:
        raise ValueError("unsupported autonomous CityGen report format")
    if limit < 1 or limit > MAX_FRONTIER:
        raise ValueError(f"limit must be between 1 and {MAX_FRONTIER}")
    if shards < 1 or shards > MAX_SHARDS:
        raise ValueError(f"shards must be between 1 and {MAX_SHARDS}")

    candidates: list[dict[str, Any]] = []
    for raw in report.get("cells") or []:
        if not isinstance(raw, dict):
            continue
        if raw.get("state") != "MISSING_SOURCE" or raw.get("autonomous_actionable") is not True:
            continue
        cell_id = raw.get("cell_id")
        if not isinstance(cell_id, str) or not cell_id.startswith("bxl-"):
            raise ValueError("invalid source-repair cell id")
        cell = dict(raw)
        cell["bbox"] = _validate_bbox(cell_id, cell.get("bbox"))
        cell["municipalities"] = _municipalities(cell)
        candidates.append(cell)

    candidates.sort(key=_repair_priority)
    municipality_names = sorted({name for cell in candidates for name in cell["municipalities"]})

    selected: list[dict[str, Any]] = []
    selected_ids: set[str] = set()
    covered: set[str] = set()

    for municipality in municipality_names:
        if municipality in covered or len(selected) >= limit:
            continue
        choice = next(
            (
                cell
                for cell in candidates
                if cell["cell_id"] not in selected_ids and municipality in cell["municipalities"]
            ),
            None,
        )
        if choice is None:
            continue
        selected.append(choice)
        selected_ids.add(choice["cell_id"])
        covered.update(choice["municipalities"])

    for cell in candidates:
        if len(selected) >= limit:
            break
        if cell["cell_id"] in selected_ids:
            continue
        selected.append(cell)
        selected_ids.add(cell["cell_id"])

    out: list[dict[str, Any]] = []
    for index, cell in enumerate(selected):
        out.append(
            {
                "cell_id": cell["cell_id"],
                "bbox": cell["bbox"],
                "municipalities": cell["municipalities"],
                "shard": index % shards,
                "attempts": int(cell.get("attempts", 0)),
                "repair_priority": _repair_priority(cell)[0],
            }
        )
    return out


def write_outputs(
    selected: list[dict[str, Any]],
    output: Path,
    summary: Path,
    limit: int,
    shards: int,
) -> dict[str, Any]:
    output.parent.mkdir(parents=True, exist_ok=True)
    summary.parent.mkdir(parents=True, exist_ok=True)

    lines = []
    for row in selected:
        bbox = ",".join(str(value) for value in row["bbox"])
        municipalities = ",".join(row["municipalities"])
        lines.append(f"{row['cell_id']}\t{bbox}\t{municipalities}\t{row['shard']}\n")
    output.write_text("".join(lines), encoding="utf-8")

    shard_sizes = Counter(int(row["shard"]) for row in selected)
    municipality_names = sorted({name for row in selected for name in row["municipalities"]})
    payload = {
        "format": WORKLIST_FORMAT,
        "frontier_limit": limit,
        "shard_count": shards,
        "selected_count": len(selected),
        "selected_municipality_count": len(municipality_names),
        "selected_municipalities": municipality_names,
        "shard_sizes": {str(index): shard_sizes.get(index, 0) for index in range(shards)},
        "max_shard_size": max(shard_sizes.values(), default=0),
        "runtime_mount_authorized": False,
        "jouable_promotion_authorized": False,
        "rows": selected,
    }
    summary.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=MAX_FRONTIER)
    parser.add_argument("--shards", type=int, default=MAX_SHARDS)
    args = parser.parse_args()

    report = _read_json(args.report)
    selected = select_source_repairs(report, args.limit, args.shards)
    payload = write_outputs(selected, args.output, args.summary, args.limit, args.shards)
    print(
        "SOURCE_REPAIR_FANOUT_WORKLIST_OK "
        f"selected={payload['selected_count']} "
        f"municipalities={payload['selected_municipality_count']} "
        f"shards={payload['shard_count']} "
        f"max_shard_size={payload['max_shard_size']} "
        "promotion_bypass=false"
    )


if __name__ == "__main__":
    main()
