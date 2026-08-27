#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/qa/audit_registered_cell_road_coverage_gaps.py"


def load_tool():
    spec = importlib.util.spec_from_file_location("gap_audit", TOOL)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class RegisteredCellRoadCoverageGapTest(unittest.TestCase):
    def setUp(self):
        self.m = load_tool()
        self.coverage = ROOT / "data/city_machine/road_cell_coverage_candidates.json"
        self.cells = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"
        self.crosswalk = ROOT / "data/provenance/brussels_road_registered_cell_crosswalk.json"
        self.base = "26810e71b4f31d9452f7d8645786669519f04f6f"

    def test_live_locked_evidence_classifies_two_source_bbox_gaps(self):
        report = self.m.build_report(self.coverage, self.cells, self.crosswalk, self.base)
        self.assertEqual(report["schema"], "grand-bruxelles-registered-cell-road-coverage-gaps-v1")
        self.assertEqual(report["status"], "SOURCE_EXTENSION_REQUIRED_EVIDENCE_ONLY")
        self.assertEqual(report["coverage_accounting"]["registered_cell_count"], 5)
        self.assertEqual(report["coverage_accounting"]["mapped_registered_cell_count"], 3)
        self.assertEqual(report["coverage_accounting"]["unmatched_registered_cell_count"], 2)
        self.assertTrue(report["coverage_accounting"]["all_unmatched_are_source_bbox_disjoint"])
        by_id = {row["cell_id"]: row for row in report["gaps"]}
        self.assertEqual(
            set(by_id),
            {"bxl-e148500-n170500-s500", "bxl-e149000-n169000-s500"},
        )
        corrected = by_id["bxl-e148500-n170500-s500"]
        self.assertEqual(corrected["grid_cell_id"], "E148500_N170500")
        self.assertEqual(corrected["reason"], "SOURCE_ROAD_BBOX_DISJOINT")
        self.assertFalse(corrected["candidate_present"])
        self.assertAlmostEqual(corrected["east_gap_m"], 374.1837720806652, places=9)
        self.assertAlmostEqual(corrected["north_gap_m"], 66.07785073801642, places=9)
        historical = by_id["bxl-e149000-n169000-s500"]
        self.assertEqual(historical["reason"], "SOURCE_ROAD_BBOX_DISJOINT")
        self.assertAlmostEqual(historical["east_gap_m"], 874.1837720806652, places=9)
        self.assertEqual(report["semantic_sha256"], "65536c521ff9897b74046bc1ac5aa653d4dce08ea3a66d60a610b913481508a3")
        self.assertTrue(all(v is False for v in report["authorization"].values()))

    def test_crosswalk_binding_drift_is_red(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            bad = json.loads(self.crosswalk.read_text(encoding="utf-8"))
            bad["registered_cell_index_semantic_sha256"] = "0" * 64
            p = td / "crosswalk.json"
            p.write_text(json.dumps(bad), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "does not bind current registered-cell semantic"):
                self.m.build_report(self.coverage, self.cells, p, self.base)

    def test_opened_rail_is_red(self):
        with tempfile.TemporaryDirectory() as td:
            td = Path(td)
            bad = json.loads(self.cells.read_text(encoding="utf-8"))
            bad["runtime_mount_authorized"] = True
            p = td / "cells.json"
            p.write_text(json.dumps(bad), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "rail widened"):
                self.m.build_report(self.coverage, p, self.crosswalk, self.base)


if __name__ == "__main__":
    unittest.main()
