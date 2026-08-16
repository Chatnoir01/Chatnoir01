#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from build_cell_elevation_candidate_frontier import build


def write_json(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        evidence = root / "elevation_value_evidence.json"
        package = root / "candidate.json"

        write_json(evidence, {
            "format": "grand-bruxelles-cell-elevation-value-evidence-v1",
            "cell_id": "bxl-e149000-n169000-s500",
            "crs": "EPSG:31370",
            "bbox": [149000, 169000, 149500, 169500],
            "terrain_source_evidence_ready": True,
            "height_source_pair_ready": True,
            "quality_failures": [],
            "evidence_digest": "value-evidence-digest",
            "dtm": {"valid_ratio": 1.0, "p50_m": 66.0, "span_m": 8.0},
            "dsm_minus_dtm": {"valid_ratio": 1.0, "p50_m": 7.0, "p95_m": 19.0, "severe_negative_ratio": 0.0},
        })
        write_json(package, {
            "format": "grand-bruxelles-cell-candidate-package-v1",
            "cell_id": "bxl-e149000-n169000-s500",
            "crs": "EPSG:31370",
            "package_digest": "candidate-package-digest",
            "summary": {"valid_buildings": 42},
        })

        result = build(evidence, package)
        assert result["cell_id"] == "bxl-e149000-n169000-s500"
        assert result["terrain"]["source_ready"] is True
        assert result["terrain"]["runtime_approved"] is False
        assert result["terrain"]["resolution_m"] is None
        assert result["terrain"]["next_gate"] == "measure_terrain_lod_reconstruction_error"
        assert result["heights"]["source_pair_ready"] is True
        assert result["heights"]["runtime_approved"] is False
        assert result["heights"]["candidate_height_count"] == 0
        assert result["heights"]["building_sample_target_count"] == 42
        assert result["heights"]["next_gate"] == "sample_per_building_dsm_minus_dtm_and_cross_validate"
        assert result["next_action"] == "assess_terrain_lod_and_building_height_samples"
        assert result["runtime_promotion_allowed"] is False
        assert result["frontier_digest"]

        # Terrain may advance independently, but absent height-pair evidence must stay fail-closed.
        blocked_height = json.loads(evidence.read_text(encoding="utf-8"))
        blocked_height["height_source_pair_ready"] = False
        blocked_height["quality_failures"] = ["dsm_minus_dtm_severe_negative_ratio_too_high"]
        write_json(evidence, blocked_height)
        result = build(evidence, package)
        assert result["terrain"]["source_ready"] is True
        assert result["heights"]["source_pair_ready"] is False
        assert result["heights"]["building_sample_target_count"] == 0
        assert result["next_action"] == "assess_terrain_lod_only"
        assert "dsm_minus_dtm_severe_negative_ratio_too_high" in result["blockers"]

        # Identity mismatches are quarantined rather than silently combined.
        bad_package = json.loads(package.read_text(encoding="utf-8"))
        bad_package["cell_id"] = "bxl-e149500-n169000-s500"
        write_json(package, bad_package)
        try:
            build(evidence, package)
        except ValueError as exc:
            assert "cell identity mismatch" in str(exc)
        else:
            raise AssertionError("mismatched candidate package was accepted")

    print("CELL_ELEVATION_CANDIDATE_FRONTIER_TEST_OK")


if __name__ == "__main__":
    main()
