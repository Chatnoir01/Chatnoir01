#!/usr/bin/env python3
import unittest

from pr_drift_planner import build_drift_plan


class DriftTests(unittest.TestCase):
    def test_fresh_pr_is_current(self):
        snap = {"main_sha": "m1", "prs": [{"number": 1, "head_sha": "h1", "behind_by": 0, "changed_files": ["a.py"], "commits": 2, "age_hours": 3}]}
        row = build_drift_plan(snap)["prs"][0]
        self.assertEqual(row["state"], "CURRENT")
        self.assertFalse(row["rebuild_required"])

    def test_stale_disjoint_pr_is_rebuild_candidate(self):
        snap = {"main_sha": "m2", "prs": [{"number": 1, "head_sha": "h1", "behind_by": 7, "changed_files": ["a.py"], "commits": 3, "age_hours": 10}]}
        row = build_drift_plan(snap)["prs"][0]
        self.assertEqual(row["state"], "REBUILD_REQUIRED")
        self.assertTrue(row["auto_rebuild_candidate"])

    def test_overlap_is_manual_ownership_conflict(self):
        snap = {"main_sha": "m2", "prs": [
            {"number": 1, "head_sha": "h1", "behind_by": 5, "changed_files": ["shared.gd"], "commits": 2, "age_hours": 2},
            {"number": 2, "head_sha": "h2", "behind_by": 0, "changed_files": ["shared.gd", "b.gd"], "commits": 1, "age_hours": 1},
        ]}
        plan = build_drift_plan(snap)
        one = next(r for r in plan["prs"] if r["number"] == 1)
        self.assertEqual(one["state"], "OWNERSHIP_CONFLICT")
        self.assertFalse(one["auto_rebuild_candidate"])
        self.assertEqual(one["overlaps"][0]["with_pr"], 2)

    def test_truncated_file_list_fails_closed(self):
        snap = {"main_sha": "m", "prs": [{"number": 4, "head_sha": "h", "behind_by": 9, "changed_files": ["x"], "files_complete": False}]}
        row = build_drift_plan(snap)["prs"][0]
        self.assertEqual(row["state"], "OWNERSHIP_UNCERTAIN")
        self.assertFalse(row["auto_rebuild_candidate"])

    def test_long_branch_risk_is_visible_but_not_fake_conflict(self):
        snap = {"main_sha": "m", "prs": [{"number": 3, "head_sha": "h", "behind_by": 0, "changed_files": ["x"], "commits": 25, "age_hours": 100}]}
        row = build_drift_plan(snap, max_commits=20, max_age_hours=72)["prs"][0]
        self.assertEqual(row["state"], "CURRENT")
        self.assertTrue(row["long_lived_risk"])

    def test_output_deterministic(self):
        snap = {"main_sha": "m", "prs": [
            {"number": 9, "head_sha": "x", "behind_by": 1, "changed_files": ["z"]},
            {"number": 2, "head_sha": "y", "behind_by": 0, "changed_files": ["a"]},
        ]}
        self.assertEqual(build_drift_plan(snap), build_drift_plan(snap))
        self.assertEqual([r["number"] for r in build_drift_plan(snap)["prs"]], [2, 9])


if __name__ == "__main__":
    unittest.main()
