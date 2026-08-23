#!/usr/bin/env python3
import json, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LOCK = ROOT / "data/provenance/brussels_sidewalk_high_coverage_runs.json"
PERSISTED = ROOT / "data/provenance/brussels_sidewalk_owner_review_queue.json"
BUILDER = ROOT / "tools/source_factory/build_sidewalk_owner_review_queue.py"

with tempfile.TemporaryDirectory() as td:
    candidate = Path(td) / "candidate.json"
    subprocess.run([sys.executable, str(BUILDER), "--output", str(candidate)], check=True)
    data = json.loads(candidate.read_text())

assert data["schema"] == "grand-bruxelles-sidewalk-owner-review-queue-v1"
assert data["run_count"] == 27
assert data["surface_count"] == 47
assert len(data["queue"]) == 27
assert all(x["exact_location_owner_review_required"] for x in data["queue"])
assert all(not x["runtime_replacement_authorized"] for x in data["queue"])
assert data["policy"]["horizontal_only"] is True
assert data["policy"]["curb_height_authorized"] is False
assert data["policy"]["vertical_profile_authorized"] is False
assert data["policy"]["runtime_geometry_authorized"] is False
assert data["policy"]["jouable_promotion_authorized"] is False
expected_ids = {x["run_id"] for x in json.loads(LOCK.read_text())["runs"]}
assert {x["run_id"] for x in data["queue"]} == expected_ids
assert all(x["road_name"] and x["nearest_corridor_anchor"] in {"midi","anneessens","bourse","grand_place"} for x in data["queue"])

if not PERSISTED.exists():
    raise AssertionError("persisted sidewalk exact-location owner review queue missing")
persisted = json.loads(PERSISTED.read_text())
assert persisted == data, "persisted owner review queue drifted from exact generated candidate"
print(f"SIDEWALK_OWNER_REVIEW_QUEUE_GREEN runs={data['run_count']} surfaces={data['surface_count']}")
