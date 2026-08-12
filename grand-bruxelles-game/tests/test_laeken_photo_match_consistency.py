import importlib.util
import json
import math
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
REFERENCE_ROOT = PROJECT_ROOT / "data" / "reference" / "laeken_jette"
VIEWS_PATH = REFERENCE_ROOT / "photo_match_views.json"
FINDINGS_PATH = REFERENCE_ROOT / "photo_match_findings.json"
FRAMING_AUDIT_PATH = REFERENCE_ROOT / "atomium_ground_framing_audit.json"
FRAMING_WITNESS_PATH = REFERENCE_ROOT / "atomium_ground_reference_witness.json"
FRAMING_TOOL_PATH = PROJECT_ROOT / "tools" / "audit_atomium_ground_framing.py"

SPEC = importlib.util.spec_from_file_location("audit_atomium_ground_framing", FRAMING_TOOL_PATH)
assert SPEC is not None and SPEC.loader is not None
FRAMING_TOOL = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(FRAMING_TOOL)


class LaekenPhotoMatchConsistencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.views_doc = json.loads(VIEWS_PATH.read_text(encoding="utf-8"))
        cls.findings_doc = json.loads(FINDINGS_PATH.read_text(encoding="utf-8"))
        cls.framing_audit = json.loads(FRAMING_AUDIT_PATH.read_text(encoding="utf-8"))
        cls.framing_witness = json.loads(FRAMING_WITNESS_PATH.read_text(encoding="utf-8"))
        cls.views = {view["id"]: view for view in cls.views_doc["views"]}
        cls.findings = cls.findings_doc["findings"]

    def test_closed_capture_missing_findings_have_registered_capture(self) -> None:
        closed_capture_findings = [
            finding
            for finding in self.findings
            if finding.get("category") == "capture_missing" and finding.get("status") == "closed"
        ]
        self.assertGreater(len(closed_capture_findings), 0)
        for finding in closed_capture_findings:
            view_id = finding["view_id"]
            self.assertIn(view_id, self.views)
            view = self.views[view_id]
            self.assertNotIn("capture_pending", str(view.get("status", "")))
            capture = str(view.get("matching_capture", ""))
            self.assertTrue(capture, f"{view_id} closed capture finding lacks matching_capture")
            capture_path = PROJECT_ROOT / capture
            self.assertTrue(capture_path.is_file(), f"{view_id} capture does not exist: {capture}")
            resolution = view.get("capture_resolution")
            self.assertEqual(resolution, view.get("resolution"))

    def test_open_high_severity_findings_block_benchmark_completion(self) -> None:
        high_open_by_view: dict[str, list[dict]] = {}
        for finding in self.findings:
            if finding.get("severity") == "high" and finding.get("status") == "open":
                high_open_by_view.setdefault(finding["view_id"], []).append(finding)
        self.assertIn("atomium_ground_oblique_v1", high_open_by_view)
        view = self.views["atomium_ground_oblique_v1"]
        self.assertNotIn(str(view.get("status", "")), {"realism_complete", "photo_match_complete"})
        self.assertEqual(view.get("fov_status"), "geometry_constrained_reference_bbox_pending")
        must_resolve = view.get("camera_selection_constraints", {}).get("must_resolve", [])
        self.assertTrue(any("bounding-box" in item or "FOV" in item or "framing" in item for item in must_resolve))

    def test_ground_oblique_framing_audit_matches_registered_geometry(self) -> None:
        view = self.views["atomium_ground_oblique_v1"]
        geometry = view.get("subject_geometry", {})
        self.assertEqual(geometry.get("official_height_m"), 102.0)
        self.assertEqual(geometry.get("top_y_m"), 102.0)
        self.assertEqual(geometry.get("baseline_y_m"), 0.0)
        self.assertEqual(view.get("reference", {}).get("source_image_dimensions_px"), [960, 638])

        evidence = view.get("framing_geometry_evidence", {})
        self.assertEqual(evidence.get("path"), "atomium_ground_framing_audit.json")
        self.assertEqual(evidence.get("status"), "geometry_audited_reference_bbox_pending")

        regenerated = FRAMING_TOOL.audit_view(view, self.framing_witness)
        persisted = self.framing_audit
        self.assertEqual(persisted.get("view_id"), view["id"])
        self.assertEqual(persisted.get("render_resolution_px"), view["resolution"])
        self.assertEqual(persisted.get("schema"), 2)
        self.assertTrue(math.isclose(persisted["current_fov_degrees"], view["fov_degrees"], abs_tol=1e-9))
        self.assertTrue(
            math.isclose(
                persisted["camera_to_target_horizontal_distance_m"],
                view["source_camera_to_atomium_ground_distance_m"],
                abs_tol=0.01,
            )
        )

        for field in (
            "camera_to_target_horizontal_distance_m",
            "camera_y_from_atomium_baseline_m",
            "subject_vertical_angular_span_deg",
            "camera_pitch_to_registered_target_deg",
            "current_fov_degrees",
            "predicted_subject_height_px",
            "predicted_subject_frame_height_fraction",
        ):
            self.assertTrue(
                math.isclose(float(persisted[field]), float(regenerated[field]), rel_tol=1e-12, abs_tol=1e-9),
                f"stale framing evidence for {field}",
            )

        self.assertEqual(len(persisted["predicted_subject_bbox_y_px"]), 2)
        for expected, actual in zip(
            persisted["predicted_subject_bbox_y_px"], regenerated["predicted_subject_bbox_y_px"], strict=True
        ):
            self.assertTrue(math.isclose(float(expected), float(actual), rel_tol=1e-12, abs_tol=1e-9))

        fraction = float(persisted["predicted_subject_frame_height_fraction"])
        self.assertGreater(fraction, 0.0)
        self.assertLess(fraction, 0.5)
        self.assertTrue(math.isclose(fraction, 0.35454757387279306, rel_tol=1e-12, abs_tol=1e-9))

    def test_reference_visible_witness_proves_current_fov_is_too_wide(self) -> None:
        view = self.views["atomium_ground_oblique_v1"]
        witness = self.framing_witness
        self.assertEqual(witness["view_id"], view["id"])
        self.assertEqual(witness["source_image_dimensions_px"], [960, 638])
        self.assertEqual(witness["vertical_visible_witness_y_px"], [58, 440])
        self.assertEqual(witness["endpoint_uncertainty_px"], 5)
        self.assertEqual(witness["conservative_min_visible_witness_height_px"], 372)
        expected_min_fraction = 372.0 / 638.0
        self.assertTrue(
            math.isclose(
                witness["conservative_min_visible_witness_frame_fraction"],
                expected_min_fraction,
                rel_tol=1e-12,
                abs_tol=1e-12,
            )
        )

        regenerated = FRAMING_TOOL.audit_view(view, witness)["reference_visible_witness"]
        persisted = self.framing_audit["reference_visible_witness"]
        self.assertTrue(persisted["current_fov_is_too_wide"])
        self.assertTrue(regenerated["current_fov_is_too_wide"])
        self.assertGreater(view["fov_degrees"], persisted["maximum_fov_consistent_with_visible_witness_deg"])
        self.assertTrue(
            math.isclose(
                persisted["maximum_fov_consistent_with_visible_witness_deg"],
                regenerated["maximum_fov_consistent_with_visible_witness_deg"],
                rel_tol=1e-12,
                abs_tol=1e-9,
            )
        )
        self.assertGreater(persisted["maximum_fov_consistent_with_visible_witness_deg"], 31.0)
        self.assertLess(persisted["maximum_fov_consistent_with_visible_witness_deg"], 32.0)

    def test_reference_witness_is_not_presented_as_recovered_lens(self) -> None:
        view = self.views["atomium_ground_oblique_v1"]
        unknowns = view.get("camera_selection_constraints", {}).get("remaining_unknowns", [])
        forbidden = view.get("camera_selection_constraints", {}).get("must_not_infer", [])
        witness_forbidden = self.framing_witness.get("must_not_infer", [])
        self.assertTrue(any("lens focal length" in item for item in unknowns))
        self.assertTrue(any("geometry-only" in item for item in forbidden))
        self.assertTrue(any("historical focal length" in item for item in witness_forbidden))
        self.assertIn("does not claim", self.framing_witness.get("measurement_role", ""))
        self.assertIn("neither geometry nor the witness recovers", self.framing_audit.get("interpretation", ""))


if __name__ == "__main__":
    unittest.main()
