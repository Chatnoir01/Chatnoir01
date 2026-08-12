import json
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
REFERENCE_ROOT = PROJECT_ROOT / "data" / "reference" / "laeken_jette"
VIEWS_PATH = REFERENCE_ROOT / "photo_match_views.json"
FINDINGS_PATH = REFERENCE_ROOT / "photo_match_findings.json"


class LaekenPhotoMatchConsistencyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.views_doc = json.loads(VIEWS_PATH.read_text(encoding="utf-8"))
        cls.findings_doc = json.loads(FINDINGS_PATH.read_text(encoding="utf-8"))
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
        self.assertEqual(view.get("fov_status"), "provisional_visual_fit_pending_measurement")
        must_resolve = view.get("camera_selection_constraints", {}).get("must_resolve", [])
        self.assertTrue(any("FOV" in item or "framing" in item for item in must_resolve))


if __name__ == "__main__":
    unittest.main()
