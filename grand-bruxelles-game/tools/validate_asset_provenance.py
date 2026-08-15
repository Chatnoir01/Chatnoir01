#!/usr/bin/env python3
from __future__ import annotations

import csv
import sys
from pathlib import Path

REQUIRED = [
    "asset_id",
    "source_url",
    "author",
    "license",
    "attribution_required",
    "derivative_terms",
    "local_path",
    "notes",
]
IGNORED_NAMES = {"LICENSE_REGISTRY.tsv", "PROVENANCE.md", ".gitkeep"}
IGNORED_SUFFIXES = {".md", ".import"}


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    assets_dir = root / "assets"
    registry = assets_dir / "LICENSE_REGISTRY.tsv"
    if not registry.exists():
        return [f"missing registry: {registry}"]

    with registry.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames != REQUIRED:
            errors.append(f"registry header mismatch: {reader.fieldnames!r}")
            return errors
        rows = list(reader)

    seen_ids: set[str] = set()
    registered_paths: set[str] = set()
    for index, row in enumerate(rows, start=2):
        missing = [field for field in REQUIRED if not row.get(field, "").strip()]
        if missing:
            errors.append(f"row {index}: empty required fields: {', '.join(missing)}")
            continue
        asset_id = row["asset_id"].strip()
        if asset_id in seen_ids:
            errors.append(f"row {index}: duplicate asset_id {asset_id}")
        seen_ids.add(asset_id)
        local_path = row["local_path"].strip().replace("\\", "/")
        if local_path in registered_paths:
            errors.append(f"row {index}: duplicate local_path {local_path}")
        registered_paths.add(local_path)
        target = root / local_path
        if not target.is_file():
            errors.append(f"row {index}: local_path does not exist: {local_path}")
        if row["attribution_required"].strip().lower() not in {"true", "false"}:
            errors.append(f"row {index}: attribution_required must be true/false")

    for path in assets_dir.rglob("*"):
        if not path.is_file() or path.name in IGNORED_NAMES or path.suffix.lower() in IGNORED_SUFFIXES:
            continue
        rel = path.relative_to(root).as_posix()
        if rel not in registered_paths:
            errors.append(f"unregistered asset: {rel}")

    return errors


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    errors = validate(root)
    if errors:
        print("ASSET_PROVENANCE_FAIL")
        for error in errors:
            print(f"- {error}")
        return 1
    print("ASSET_PROVENANCE_OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
