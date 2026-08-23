#!/usr/bin/env python3
import argparse
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK_PATH = ROOT / "data/provenance/brussels_sidewalk_high_coverage_runs.json"
EXPECTED_SURFACES = 47
MIN_COVERAGE = 0.99


def _load(path: Path):
    if not path.exists():
        raise AssertionError(f"required sidewalk high-coverage evidence missing: {path}")
    return json.loads(path.read_text(encoding="utf-8"))


def _canonical_sha256(value):
    payload = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def _compact_lock(candidate):
    classification = candidate["classification"]
    return {
        "schema": "grand-bruxelles-sidewalk-high-coverage-runs-lock-v1",
        "candidate_schema": candidate["schema"],
        "candidate_sha256": _canonical_sha256(candidate),
        "coverage_threshold": candidate["coverage_threshold"],
        "inputs": candidate["inputs"],
        "high_coverage_surface_ids": [surface["surface_id"] for surface in classification["high_coverage_surfaces"]],
        "runs": [
            {
                "run_id": run["run_id"],
                "osm_id": run["osm_id"],
                "side": run["side"],
                "start_segment_index": run["start_segment_index"],
                "end_segment_index": run["end_segment_index"],
                "surface_count": run["surface_count"],
                "surface_ids": run["surface_ids"],
            }
            for run in classification["runs"]
        ],
        "policy": candidate["policy"],
    }


def validate(candidate_path: Path):
    candidate = _load(candidate_path)
    assert candidate["schema"] == "grand-bruxelles-sidewalk-high-coverage-runs-v1"
    assert candidate["classification_kind"] == "same-osm-way-same-side-consecutive-segment-runs"
    assert candidate["horizontal_only"] is True
    assert abs(float(candidate["coverage_threshold"]) - MIN_COVERAGE) <= 1e-12
    classification = candidate["classification"]
    assert int(classification["high_coverage_surface_count"]) == EXPECTED_SURFACES
    surfaces = classification["high_coverage_surfaces"]
    assert len(surfaces) == EXPECTED_SURFACES
    assert len({surface["surface_id"] for surface in surfaces}) == EXPECTED_SURFACES
    for surface in surfaces:
        assert float(surface["coverage_fraction"]) >= MIN_COVERAGE
        assert int(surface["osm_id"]) > 0
        assert int(surface["segment_index"]) >= 0
        assert int(surface["side"]) in (-1, 1)
        assert len(surface["center_xz"]) == 2
        assert float(surface["length_m"]) > 0.0
        assert float(surface["width_m"]) > 0.0
    runs = classification["runs"]
    assert len(runs) == int(classification["run_count"])
    flattened = []
    for run in runs:
        ids = run["surface_ids"]
        assert ids
        assert int(run["surface_count"]) == len(ids)
        assert float(run["min_coverage_fraction"]) >= MIN_COVERAGE
        assert int(run["end_segment_index"]) - int(run["start_segment_index"]) + 1 == len(ids)
        flattened.extend(ids)
    assert sorted(flattened) == sorted(surface["surface_id"] for surface in surfaces)
    policy = candidate["policy"]
    for key in (
        "curb_height_authorized",
        "vertical_profile_authorized",
        "runtime_geometry_authorized",
        "runtime_replacement_authorized",
        "jouable_promotion_authorized",
        "classification_alone_authorizes_runtime",
    ):
        assert policy[key] is False
    assert policy["exact_location_owner_review_required"] is True

    if not LOCK_PATH.exists():
        raise AssertionError("persisted high-coverage sidewalk run lock missing")
    persisted = _load(LOCK_PATH)
    expected_lock = _compact_lock(candidate)
    assert persisted == expected_lock, "persisted high-coverage sidewalk run lock drifted"
    print(
        "OFFICIAL_SIDEWALK_HIGH_COVERAGE_RUNS_OK "
        + json.dumps(
            {
                "surfaces": EXPECTED_SURFACES,
                "runs": classification["run_count"],
                "multi_surface_runs": classification["multi_surface_run_count"],
                "threshold": MIN_COVERAGE,
                "candidate_sha256": expected_lock["candidate_sha256"],
            },
            sort_keys=True,
        )
    )


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", required=True)
    args = parser.parse_args()
    validate(Path(args.candidate))


if __name__ == "__main__":
    main()
