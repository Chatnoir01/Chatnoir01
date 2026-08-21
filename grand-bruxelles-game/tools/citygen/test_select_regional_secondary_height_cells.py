#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location(
    "select_regional_secondary_height_cells",
    HERE / "select_regional_secondary_height_cells.py",
)
assert SPEC and SPEC.loader
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def write(path: Path, payload) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(payload, str):
        path.write_text(payload, encoding="utf-8")
    else:
        path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def seal(payload: dict, field: str) -> dict:
    value = copy.deepcopy(payload)
    value[field] = mod._digest(value)
    return value


def height_payload(cell_id: str, height: float = 12.5) -> dict:
    return seal(
        {
            "format": mod.HEIGHT_FORMAT,
            "cell_id": cell_id,
            "crs": mod.CRS,
            "candidate_count": 1,
            "runtime_approved_count": 0,
            "buildings": [
                {
                    "building_id": f"{cell_id}-building-1",
                    "candidate_height_m": height,
                    "confidence": "high",
                    "runtime_approved": False,
                }
            ],
            "runtime_promotion_allowed": False,
        },
        "candidate_digest",
    )


def terrain_payload(cell_id: str) -> dict:
    return seal(
        {
            "format": mod.TERRAIN_FORMAT,
            "cell_id": cell_id,
            "crs": mod.CRS,
            "source": "official_validated_DTM",
            "selection": {
                "selected_resolution_m": 2.0,
                "runtime_approved": False,
                "blockers": [],
            },
            "runtime_approved": False,
        },
        "evidence_digest",
    )


def make_prerequisites(root: Path, cell_id: str) -> tuple[Path, dict]:
    cell = root / cell_id
    write(cell / "raw" / "buildings.geojson", '{"type":"FeatureCollection","features":[]}\n')
    heights = height_payload(cell_id)
    write(cell / "building_height_candidates.json", heights)
    write(cell / "terrain_lod_evidence.json", terrain_payload(cell_id))
    return cell, heights


def make_fresh_pair(cell: Path, heights: dict, *, validated: int = 1, blocked: int = 0) -> None:
    cell_id = cell.name
    secondary = {
        "schema": mod.SECONDARY_SCHEMA,
        "cell": cell_id,
        "source_crs": mod.CRS,
        "policy": {"runtime_approval": False},
        "counts": {
            "height_candidate_source_count": 1,
            "automatic_height_candidates": 1,
            "semantic_joined_records": 1,
        },
        "records": [],
        "runtime_approved": False,
    }
    write(cell / "secondary_height_evidence.json", secondary)
    validation = seal(
        {
            "format": mod.VALIDATION_FORMAT,
            "cell_id": cell_id,
            "crs": mod.CRS,
            "height_candidate_source_kind": "autonomous_measured_height_candidates",
            "source_candidate_digest": heights["candidate_digest"],
            "secondary_evidence_digest": mod._digest(secondary),
            "candidate_count": 1,
            "validated_candidate_count": validated,
            "blocked_candidate_count": blocked,
            "secondary_validation_complete": blocked == 0,
            "candidates": [
                {
                    "building_id": f"{cell_id}-building-1",
                    "candidate_height_m": 12.5,
                    "secondary_status": "validated" if validated else "blocked_missing_secondary_evidence",
                    "runtime_approved": False,
                }
            ],
            "blockers": [] if blocked == 0 else ["secondary_independent_height_validation_incomplete"],
            "runtime_promotion_allowed": False,
            "runtime_approved_count": 0,
        },
        "validation_digest",
    )
    write(cell / "secondary_height_validation.json", validation)


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp) / "cells"

        fresh_cell, fresh_heights = make_prerequisites(root, "bxl-e140000-n160000-s500")
        make_fresh_pair(fresh_cell, fresh_heights)

        failed_cell, failed_heights = make_prerequisites(root, "bxl-e140500-n160000-s500")
        # Missing pair => eligible. Mark this as previous failure so it rotates back.

        stale_cell, stale_heights = make_prerequisites(root, "bxl-e141000-n160000-s500")
        make_fresh_pair(stale_cell, stale_heights)
        stale_validation = json.loads((stale_cell / "secondary_height_validation.json").read_text(encoding="utf-8"))
        stale_validation.pop("validation_digest")
        stale_validation["source_candidate_digest"] = "f" * 64
        stale_validation = seal(stale_validation, "validation_digest")
        write(stale_cell / "secondary_height_validation.json", stale_validation)

        tampered_cell, _ = make_prerequisites(root, "bxl-e141500-n160000-s500")
        tampered = json.loads((tampered_cell / "building_height_candidates.json").read_text(encoding="utf-8"))
        tampered["buildings"][0]["candidate_height_m"] = 99.0  # digest intentionally not refreshed
        write(tampered_cell / "building_height_candidates.json", tampered)

        unsafe_cell, unsafe_heights = make_prerequisites(root, "bxl-e142000-n160000-s500")
        unsafe_heights.pop("candidate_digest")
        unsafe_heights["buildings"][0]["runtime_approved"] = True
        unsafe_heights = seal(unsafe_heights, "candidate_digest")
        write(unsafe_cell / "building_height_candidates.json", unsafe_heights)

        bad_terrain_cell, _ = make_prerequisites(root, "bxl-e142500-n160000-s500")
        bad_terrain = json.loads((bad_terrain_cell / "terrain_lod_evidence.json").read_text(encoding="utf-8"))
        bad_terrain["selection"]["selected_resolution_m"] = 8.0  # digest intentionally not refreshed
        write(bad_terrain_cell / "terrain_lod_evidence.json", bad_terrain)

        previous = Path(tmp) / "previous.json"
        write(previous, {"failed_cells": [failed_cell.name]})

        result = mod.select(root, 2, previous)
        assert result["fresh_count"] == 1, result
        assert result["eligible_count"] == 2, result
        assert result["rejected_count"] == 3, result
        assert result["selected_cells"] == [stale_cell.name, failed_cell.name], result
        assert result["previous_failed_deprioritized"] == [failed_cell.name]
        assert result["policy"]["embedded_source_digest_validation"] is True
        assert result["policy"]["runtime_promotion_allowed"] is False

        # A content change with a refreshed candidate digest invalidates prior validation.
        fresh_changed = copy.deepcopy(fresh_heights)
        fresh_changed.pop("candidate_digest")
        fresh_changed["buildings"][0]["candidate_height_m"] = 13.0
        fresh_changed = seal(fresh_changed, "candidate_digest")
        write(fresh_cell / "building_height_candidates.json", fresh_changed)
        changed = mod.select(root, 3, previous)
        assert fresh_cell.name in changed["selected_cells"]

        try:
            mod.select(root, 17, previous)
        except ValueError as exc:
            assert "between 1 and 16" in str(exc)
        else:
            raise AssertionError("oversized regional batch must fail closed")

    print(
        "REGIONAL_SECONDARY_HEIGHT_SELECTION_TEST_OK",
        "digest_freshness=true",
        "tamper_rejected=true",
        "failure_rotation=true",
        "runtime_promotion=false",
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
