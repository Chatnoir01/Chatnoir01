#!/usr/bin/env python3
"""Derive global-cell reservations from another Git branch.

The Grand Bruxelles project is developed in parallel zone branches. Because a
500 m Lambert72 cell can cross an administrative boundary, municipality names
alone cannot prevent duplicate production geometry. This tool scans JSON files
from another Git ref and reserves any globally identified built cells plus any
v2 zone-grid cells declared for selected zone IDs.

It never modifies the external branch. The output is a small, reproducible
reservation snapshot that local seed selectors can consume.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Any, Iterable

FORMAT = "grand-bruxelles-external-cell-reservations-v1"
BUILT_FORMAT = "grand-bruxelles-urbis-built-cell-v1"
GRID_FORMAT = "grand-bruxelles-zone-cells-v2"


def git_paths(ref: str) -> list[str]:
    result = subprocess.run(
        ["git", "ls-tree", "-r", "--name-only", ref],
        check=True,
        capture_output=True,
        text=True,
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip().endswith(".json")]


def git_json(ref: str, path: str) -> dict[str, Any] | None:
    result = subprocess.run(
        ["git", "show", f"{ref}:{path}"],
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError:
        return None
    return payload if isinstance(payload, dict) else None


def valid_global_cell_id(value: object) -> str | None:
    text = str(value or "").strip()
    if text.startswith("bxl-e") and "-n" in text and "-s" in text:
        return text
    return None


def extract_reservations(
    documents: Iterable[tuple[str, dict[str, Any]]],
    reserved_zone_ids: set[str],
) -> dict[str, Any]:
    materialized: set[str] = set()
    planned: set[str] = set()
    evidence: list[dict[str, Any]] = []

    for path, payload in documents:
        fmt = payload.get("format")
        if fmt == BUILT_FORMAT:
            cell_id = valid_global_cell_id(payload.get("cell_id"))
            if cell_id:
                materialized.add(cell_id)
                evidence.append({"path": path, "format": fmt, "cell_ids": [cell_id]})
        elif fmt == GRID_FORMAT:
            zone_id = str(payload.get("zone_id", "")).strip()
            if reserved_zone_ids and zone_id not in reserved_zone_ids:
                continue
            ids: list[str] = []
            for cell in payload.get("cells", []):
                if not isinstance(cell, dict):
                    continue
                cell_id = valid_global_cell_id(cell.get("id"))
                if cell_id:
                    planned.add(cell_id)
                    ids.append(cell_id)
            if ids:
                evidence.append(
                    {
                        "path": path,
                        "format": fmt,
                        "zone_id": zone_id,
                        "cell_ids": sorted(set(ids)),
                    }
                )

    reserved = materialized | planned
    return {
        "materialized_cell_ids": sorted(materialized),
        "planned_cell_ids": sorted(planned),
        "reserved_cell_ids": sorted(reserved),
        "evidence": evidence,
    }


def scan_ref(ref: str, reserved_zone_ids: set[str]) -> dict[str, Any]:
    documents: list[tuple[str, dict[str, Any]]] = []
    scanned = 0
    for path in git_paths(ref):
        payload = git_json(ref, path)
        scanned += 1
        if payload is not None:
            documents.append((path, payload))
    extracted = extract_reservations(documents, reserved_zone_ids)
    return {
        "format": FORMAT,
        "source_ref": ref,
        "reserved_zone_ids": sorted(reserved_zone_ids),
        "json_files_scanned": scanned,
        "json_documents_parsed": len(documents),
        "materialized_cell_count": len(extracted["materialized_cell_ids"]),
        "planned_cell_count": len(extracted["planned_cell_ids"]),
        "reserved_cell_count": len(extracted["reserved_cell_ids"]),
        **extracted,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync global cell reservations from another zone branch")
    parser.add_argument("--ref", required=True, help="Git ref to scan, e.g. origin/zone-laeken-jette")
    parser.add_argument("--zone-id", action="append", default=[], help="reserved v2 grid zone ID; repeatable")
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    result = scan_ref(args.ref, set(args.zone_id))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(
        f"{args.ref}: {result['reserved_cell_count']} reserved global cells "
        f"({result['materialized_cell_count']} materialized, {result['planned_cell_count']} planned)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
