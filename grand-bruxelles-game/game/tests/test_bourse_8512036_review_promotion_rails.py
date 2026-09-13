#!/usr/bin/env python3
from pathlib import Path
from strict_json_evidence import load_path_strict

ROOT = Path(__file__).resolve().parents[2]
receipt = load_path_strict(ROOT / "data/qa/corridor/bourse_8512036_human_review.json")
assert isinstance(receipt, dict)
assert receipt.get("verdict") == "REJECT"
for key in ("runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized"):
    assert receipt.get(key) is False, f"{key} must be explicitly false on a REJECT receipt"
print("BOURSE_8512036_REVIEW_PROMOTION_RAILS_OK")
