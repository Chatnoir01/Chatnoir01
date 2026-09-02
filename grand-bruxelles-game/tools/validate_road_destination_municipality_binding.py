#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
READINESS = ROOT / "data/provenance/brussels_road_destination_readiness_catalog.json"


def fail(message: str) -> None:
    raise SystemExit(f"ROAD_DESTINATION_MUNICIPALITY_BINDING_FAIL: {message}")


def _load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"cannot read {path.relative_to(ROOT)}: {exc}")
    if not isinstance(value, dict):
        fail(f"root must be object: {path.relative_to(ROOT)}")
    return value


def _canonical_intersections(manifest: dict[str, Any]) -> list[dict[str, Any]]:
    provenance = manifest.get("provenance")
    if not isinstance(provenance, dict):
        fail("cell manifest provenance missing")
    raw = provenance.get("municipality_intersections")
    if raw is None:
        nis = provenance.get("municipality_niscode")
        inspire = provenance.get("municipality_id")
        ratio = provenance.get("municipality_coverage_ratio")
        raw = [{"niscode": nis, "inspire_id": inspire, "coverage_ratio": ratio}]
    if not isinstance(raw, list) or not raw:
        fail("cell manifest municipality evidence missing")
    result: list[dict[str, Any]] = []
    seen: set[str] = set()
    total = 0.0
    for item in raw:
        if not isinstance(item, dict):
            fail("malformed municipality intersection")
        nis = item.get("niscode")
        inspire = item.get("inspire_id")
        ratio = item.get("coverage_ratio")
        if not isinstance(nis, str) or not nis or nis in seen:
            fail("invalid/duplicate municipality niscode")
        if not isinstance(inspire, str) or not inspire:
            fail(f"invalid municipality inspire_id for {nis}")
        if type(ratio) not in (int, float) or not math.isfinite(float(ratio)) or float(ratio) <= 0.0:
            fail(f"invalid municipality coverage_ratio for {nis}")
        seen.add(nis)
        total += float(ratio)
        result.append({"niscode": nis, "inspire_id": inspire, "coverage_ratio": float(ratio)})
    if abs(total - 1.0) > 1e-9:
        fail(f"municipality coverage does not sum to 1.0: {total}")
    return sorted(result, key=lambda x: x["niscode"])


def validate(readiness: dict[str, Any]) -> dict[str, int]:
    destinations = readiness.get("destinations")
    if not isinstance(destinations, list):
        fail("destinations must be list")
    cells: set[str] = set()
    for dest in destinations:
        if not isinstance(dest, dict):
            fail("malformed destination")
        path_value = dest.get("cell_manifest_path")
        if not isinstance(path_value, str) or not path_value.startswith("data/cell_manifests/"):
            fail("invalid cell_manifest_path")
        path = ROOT / path_value
        try:
            raw_bytes = path.read_bytes()
        except OSError as exc:
            fail(f"cell manifest unavailable {path_value}: {exc}")
        expected_sha = dest.get("cell_manifest_sha256")
        actual_sha = hashlib.sha256(raw_bytes).hexdigest()
        if expected_sha != actual_sha:
            fail(f"cell manifest sha drift {path_value}")
        manifest = json.loads(raw_bytes.decode("utf-8"))
        if manifest.get("cell_id") != dest.get("cell_id"):
            fail(f"cell identity drift {dest.get('destination_id')}")
        if manifest.get("crs") != dest.get("cell_crs") or manifest.get("bbox") != dest.get("cell_bbox"):
            fail(f"cell geometry metadata drift {dest.get('destination_id')}")
        expected = _canonical_intersections(manifest)
        actual = dest.get("municipalities")
        if not isinstance(actual, list):
            fail(f"municipalities missing {dest.get('destination_id')}")
        normalized = sorted(actual, key=lambda x: x.get("niscode", "") if isinstance(x, dict) else "")
        if normalized != expected:
            fail(f"municipality evidence drift {dest.get('destination_id')}")
        niscodes = dest.get("municipality_niscodes")
        expected_niscodes = [item["niscode"] for item in expected]
        if niscodes != expected_niscodes:
            fail(f"municipality_niscodes drift {dest.get('destination_id')}")
        cells.add(path_value)
    return {"destinations": len(destinations), "cells": len(cells)}


def main() -> int:
    result = validate(_load_json(READINESS))
    print(f"ROAD_DESTINATION_MUNICIPALITY_BINDING_OK destinations={result['destinations']} cells={result['cells']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
