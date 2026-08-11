#!/usr/bin/env python3
"""Select the single proven Brussels open-data boundary dataset and gate license.

A dataset is production-geometry eligible only when the catalog exposes a
non-empty license whose normalized text clearly matches a conservative set of
open-data/open-license indicators. Unknown or blank licenses remain blocked.
This is a pipeline safeguard, not a legal opinion.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any

DISCOVERY_FORMAT = "grand-bruxelles-opendata-boundary-discovery-v1"
PROBE_FORMAT = "grand-bruxelles-opendata-boundary-probe-v1"
FORMAT = "grand-bruxelles-opendata-dataset-selection-v1"
DEFAULT_TARGETS = ("quartier européen", "louise", "roosevelt", "bois de la cambre")
OPEN_LICENSE_PATTERNS = (
    "cc0",
    "creative commons zero",
    "cc by",
    "creative commons attribution",
    "odbl",
    "open database licence",
    "open database license",
    "open licence",
    "open license",
    "licence ouverte",
    "open data licence",
    "open data license",
    "public domain",
)


def normalized(value: object) -> str:
    text = str(value or "").casefold()
    text = re.sub(r"\s+", " ", text).strip()
    return text


def license_gate(license_text: str) -> tuple[bool, str | None]:
    text = normalized(license_text)
    if not text:
        return False, None
    for pattern in OPEN_LICENSE_PATTERNS:
        if pattern in text:
            return True, pattern
    return False, None


def load_json(path: Path, expected_format: str) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("format") != expected_format:
        raise ValueError(f"unsupported format in {path}: {payload.get('format')!r}")
    return payload


def common_dataset(probe: dict[str, Any], targets: list[str]) -> str:
    mapping = probe.get("datasets_with_polygon_match_by_target") or {}
    sets: list[set[str]] = []
    for target in targets:
        values = mapping.get(target) or []
        if not values:
            raise ValueError(f"target has no polygon-proven dataset: {target}")
        sets.append(set(str(value) for value in values))
    common = set.intersection(*sets)
    if len(common) != 1:
        raise ValueError(f"expected one common dataset for {targets}, got {sorted(common)}")
    return next(iter(common))


def select_dataset(discovery: dict[str, Any], probe: dict[str, Any], targets: list[str]) -> dict[str, Any]:
    dataset_id = common_dataset(probe, targets)
    candidates = {
        str(item.get("dataset_id")): item
        for item in discovery.get("candidates", [])
        if isinstance(item, dict) and item.get("dataset_id")
    }
    if dataset_id not in candidates:
        raise ValueError(f"proven dataset {dataset_id} is absent from discovery metadata")
    candidate = candidates[dataset_id]
    license_text = str(candidate.get("license") or "").strip()
    allowed, matched_pattern = license_gate(license_text)
    return {
        "format": FORMAT,
        "dataset_id": dataset_id,
        "title": str(candidate.get("title") or ""),
        "publisher": str(candidate.get("publisher") or ""),
        "license": license_text,
        "catalog_records_count": candidate.get("records_count"),
        "targets": targets,
        "polygon_name_proof": True,
        "license_gate": {
            "production_geometry_allowed": allowed,
            "matched_open_license_pattern": matched_pattern,
            "policy": "conservative string allowlist; unknown licenses remain blocked",
            "not_legal_opinion": True,
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Select and license-gate a proven Brussels open-data boundary dataset")
    parser.add_argument("--discovery", type=Path, required=True)
    parser.add_argument("--probe", type=Path, required=True)
    parser.add_argument("--target", action="append", default=[])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    targets = args.target or list(DEFAULT_TARGETS)
    result = select_dataset(
        load_json(args.discovery, DISCOVERY_FORMAT),
        load_json(args.probe, PROBE_FORMAT),
        targets,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("dataset:", result["dataset_id"])
    print("title:", result["title"])
    print("publisher:", result["publisher"])
    print("license:", result["license"])
    print("production geometry allowed:", result["license_gate"]["production_geometry_allowed"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
