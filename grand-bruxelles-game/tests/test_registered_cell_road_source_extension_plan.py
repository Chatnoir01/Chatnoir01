#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GAPS = ROOT / "data/provenance/brussels_registered_cell_road_coverage_gaps.json"
PLAN = ROOT / "data/qa/brussels_registered_cell_road_source_extension.plan.json"


class RegisteredCellRoadSourceExtensionPlanTest(unittest.TestCase):
    def test_plan_covers_all_locked_unmatched_cells_without_opening_rails(self):
        gaps = json.loads(GAPS.read_text(encoding="utf-8"))
        self.assertTrue(PLAN.is_file(), "RED: deterministic road-source extension plan is missing")
        plan = json.loads(PLAN.read_text(encoding="utf-8"))

        self.assertEqual(plan["schema"], "grand-bruxelles-road-source-extension-plan-v1")
        self.assertEqual(plan["status"], "PLANNED_NOT_ACQUIRED")
        self.assertEqual(plan["input_gap_semantic_sha256"], gaps["semantic_sha256"])
        self.assertEqual(plan["baseline_source"]["path"], gaps["road_source"]["source_path"])
        self.assertEqual(plan["baseline_source"]["sha256"], gaps["road_source"]["source_sha256"])
        self.assertEqual(plan["baseline_source"]["lambert72_bbox"], gaps["road_source"]["lambert72_bbox"])
        self.assertFalse(plan["baseline_source"]["may_be_overwritten"])

        unmatched = {row["cell_id"]: row["bbox"] for row in gaps["gaps"]}
        self.assertEqual(set(plan["required_cells"]), set(unmatched))
        for cell_id, bbox in unmatched.items():
            self.assertEqual(plan["required_cells"][cell_id], bbox)

        envelope = plan["required_acquisition_envelope_lambert72"]
        self.assertEqual(len(envelope), 4)
        self.assertLessEqual(envelope[0], min(b[0] for b in unmatched.values()))
        self.assertLessEqual(envelope[1], min(b[1] for b in unmatched.values()))
        self.assertGreaterEqual(envelope[2], max(b[2] for b in unmatched.values()))
        self.assertGreaterEqual(envelope[3], max(b[3] for b in unmatched.values()))
        self.assertGreaterEqual(envelope[2], 149500.0)
        self.assertGreaterEqual(envelope[3], 171000.0)

        future = plan["future_acquisition_contract"]
        for key in (
            "new_snapshot_path_required",
            "overpass_query_text_required",
            "overpass_query_sha256_required",
            "request_url_required",
            "acquired_at_utc_required",
            "odbl_attribution_required",
            "raw_payload_sha256_required",
            "road_count_required",
            "road_point_count_required",
            "normalized_semantic_sha256_required",
        ):
            self.assertTrue(future[key], key)
        self.assertNotEqual(future["target_snapshot_path"], gaps["road_source"]["source_path"])

        self.assertTrue(all(v is False for v in plan["authorization"].values()))

        semantic_basis = dict(plan)
        semantic_basis.pop("semantic_sha256", None)
        encoded = json.dumps(semantic_basis, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        self.assertEqual(plan["semantic_sha256"], hashlib.sha256(encoded).hexdigest())


if __name__ == "__main__":
    unittest.main()
