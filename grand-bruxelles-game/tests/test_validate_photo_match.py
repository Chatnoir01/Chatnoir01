from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from contextlib import redirect_stderr
from io import StringIO
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = PROJECT_ROOT / "tools" / "validate_photo_match.py"
SPEC = importlib.util.spec_from_file_location("validate_photo_match", VALIDATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
VALIDATOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(VALIDATOR)


class PhotoMatchValidatorTests(unittest.TestCase):
    def test_rejects_complete_reference_with_provisional_camera(self) -> None:
        scores = {field: 5.0 for field in VALIDATOR.SCORE_FIELDS}
        manifest = {
            "schema_version": 1,
            "score_scale": {
                "min": 0,
                "max": 5,
                "passing_average": 4.0,
                "critical_fields": [
                    "silhouette",
                    "building_placement",
                    "height_roofline",
                    "street_width",
                    "landmark_alignment",
                ],
            },
            "references": [
                {
                    "id": "test-provisional-complete",
                    "hero_location": "Test hero",
                    "zone": "test",
                    "reference": {
                        "source_page": "https://example.invalid/reference",
                        "captured_at": "2026-01-01T00:00:00Z",
                        "author": "Test",
                        "license": "CC0-1.0",
                        "distribution_policy": "provenance-only",
                        "camera_notes": "test camera",
                    },
                    "viewpoint": {
                        "description": "test viewpoint",
                        "game_camera_transform": {
                            "position": [0.0, 1.7, 0.0],
                            "rotation_degrees": [0.0, 0.0, 0.0],
                            "fov_degrees": 60.0,
                            "status": "provisional",
                        },
                        "game_screenshot": "data/qa/photo_match/never-reached.png",
                    },
                    "scores": scores,
                    "mismatches": [],
                    "realism_complete": True,
                }
            ],
        }

        with tempfile.TemporaryDirectory(dir=PROJECT_ROOT) as temp_dir:
            manifest_path = Path(temp_dir) / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            stderr = StringIO()
            with redirect_stderr(stderr), self.assertRaises(SystemExit) as raised:
                VALIDATOR.validate_manifest(manifest_path)

        self.assertEqual(raised.exception.code, 1)
        self.assertIn("provisional game_camera_transform", stderr.getvalue())


if __name__ == "__main__":
    unittest.main()
