#!/usr/bin/env python3
"""Validate source-backed runtime approval for hero buildings."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any


COMPONENTS = ("footprint", "height", "roof", "frontage")


def validate_record(record: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    label = str(record.get("name") or record.get("osm_id") or "<unknown hero>")

    for key in ("osm_id", "anchor_id", "role", "name"):
        if record.get(key) in (None, ""):
            errors.append(f"{label}: missing required field {key}")

    approvals = record.get("runtime_approval")
    evidence = record.get("evidence")
    if not isinstance(approvals, dict):
        return errors + [f"{label}: runtime_approval must be an object"]
    if not isinstance(evidence, dict):
        return errors + [f"{label}: evidence must be an object"]

    for component in COMPONENTS:
        approved = approvals.get(component)
        if not isinstance(approved, bool):
            errors.append(f"{label}: runtime_approval.{component} must be boolean")
            continue
        component_evidence = evidence.get(component)
        if approved and not isinstance(component_evidence, dict):
            errors.append(
                f"{label}: runtime-approved {component} requires structured evidence"
            )

    if approvals.get("footprint") is True:
        footprint = evidence.get("footprint")
        if isinstance(footprint, dict):
            if footprint.get("source") != "official_urbis_plan":
                errors.append(
                    f"{label}: approved footprint source must be official_urbis_plan"
                )
            if footprint.get("crs") != "EPSG:31370":
                errors.append(f"{label}: approved footprint must use EPSG:31370")
            inspire_id = str(footprint.get("inspire_id") or "")
            if not inspire_id.startswith("https://databrussels.be/id/building/"):
                errors.append(
                    f"{label}: approved footprint requires a databrussels building inspire_id"
                )
            try:
                area = float(footprint.get("area_m2"))
            except (TypeError, ValueError):
                area = 0.0
            if area <= 0.0:
                errors.append(f"{label}: approved footprint area_m2 must be positive")

    return errors


def validate_document(document: dict[str, Any]) -> list[str]:
    records = document.get("required_buildings")
    if not isinstance(records, list) or not records:
        return ["required_buildings must be a non-empty list"]

    errors: list[str] = []
    seen: set[int] = set()
    for index, record in enumerate(records):
        if not isinstance(record, dict):
            errors.append(f"required_buildings[{index}] must be an object")
            continue
        osm_id = record.get("osm_id")
        if isinstance(osm_id, int):
            if osm_id in seen:
                errors.append(f"duplicate required hero osm_id {osm_id}")
            seen.add(osm_id)
        errors.extend(validate_record(record))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    document = json.loads(args.path.read_text(encoding="utf-8"))
    errors = validate_document(document)
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"Hero building evidence OK: {len(document['required_buildings'])} hero(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
