import copy
import json
import tempfile
import unittest
from pathlib import Path

from tools.qa.measure_corrected_frame_road_destination_readiness_impact import measure


class CorrectedFrameDestinationImpactTests(unittest.TestCase):
    def _write(self, root, name, obj):
        path = root / name
        path.write_text(json.dumps(obj, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        return path

    def _fixture(self, root):
        base = "a" * 40
        contract = {
            "schema": "grand-bruxelles-corrected-frame-road-destination-readiness-impact-contract-v1",
            "status": "MEASUREMENT_PENDING",
            "production_base_sha": base,
            "source": {
                "provider": "OpenStreetMap contributors via Overpass API",
                "license": "ODbL-1.0",
                "road_source_sha256": "1" * 64,
                "materialization_semantic_sha256": "2" * 64,
                "crs": "EPSG:31370",
            },
            "expected": {
                "current_destination_count": 2,
                "candidate_unique_destination_count": 2,
                "multicell_hold_count": 1,
                "no_registered_overlap_count": 3,
                "retained_destination_count": 0,
                "changed_cell_destination_count": 1,
                "new_destination_count": 1,
                "removed_destination_count": 1,
            },
            "policy": {
                "measurement_only": True,
                "replace_readiness_catalog_authorized": False,
                "replace_crosswalk_authorized": False,
                "multicell_destination_authorized": False,
                "atomic_followup_required": True,
            },
            "authorization": {
                "production_frame_update_authorized": False,
                "road_cell_mapping_authorized": False,
                "runtime_directory_scan_authorized": False,
                "runtime_mount_authorized": False,
                "rendered_geometry_authorized": False,
                "collision_authorized": False,
                "safe_spawn_authorized": False,
                "jouable_promotion_authorized": False,
            },
        }
        candidate = {
            "schema": "grand-bruxelles-corrected-frame-road-cell-crosswalk-materialization-candidate-v1",
            "status": "CANDIDATE_EVIDENCE_ONLY_NOT_APPLIED",
            "semantic_sha256": "2" * 64,
            "rows": [
                {"road_osm_id": 1, "cell_id": "cell-b"},
                {"road_osm_id": 3, "cell_id": "cell-c"},
            ],
            "multicell_hold_rows": [{"road_osm_id": 4, "hit_cells": ["cell-a", "cell-b"]}],
            "accounting": {"candidate_no_registered_overlap_count": 3},
            "materialization_policy": {
                "replace_current_crosswalk_authorized": False,
                "write_production_crosswalk_authorized": False,
                "multicell_mapping_authorized": False,
            },
            "authorization": copy.deepcopy(contract["authorization"]),
        }
        readiness = {
            "destination_count": 2,
            "authorization": {
                "collision_authorized": False,
                "jouable_authorized": False,
                "render_authorized": False,
                "road_cell_mapping_authorized": False,
                "runtime_directory_scan_authorized": False,
                "runtime_mount_authorized": False,
                "safe_spawn_authorized": False,
            },
            "destinations": [
                {
                    "road_osm_id": 1,
                    "destination_id": "road-1",
                    "cell_id": "cell-a",
                    "readiness": "REGISTERED_NOT_RENDERED",
                    "render_authorized": False,
                    "collision_authorized": False,
                    "runtime_mount_authorized": False,
                    "safe_spawn_authorized": False,
                    "jouable_authorized": False,
                },
                {
                    "road_osm_id": 2,
                    "destination_id": "road-2",
                    "cell_id": "cell-z",
                    "readiness": "REGISTERED_NOT_RENDERED",
                    "render_authorized": False,
                    "collision_authorized": False,
                    "runtime_mount_authorized": False,
                    "safe_spawn_authorized": False,
                    "jouable_authorized": False,
                },
            ],
        }
        return base, contract, candidate, readiness

    def test_classifies_changed_new_removed_without_authorizing_runtime(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base, contract, candidate, readiness = self._fixture(root)
            result = measure(
                self._write(root, "contract.json", contract),
                self._write(root, "candidate.json", candidate),
                self._write(root, "readiness.json", readiness),
                base,
            )
            self.assertEqual([1], [row["road_osm_id"] for row in result["changed_rows"]])
            self.assertEqual([3], [row["road_osm_id"] for row in result["new_rows"]])
            self.assertEqual([2], [row["road_osm_id"] for row in result["removed_rows"]])
            self.assertEqual([4], result["multicell_hold_road_ids"])
            self.assertTrue(all(v is False for v in result["authorization"].values()))

    def test_rejects_runtime_authorization(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base, contract, candidate, readiness = self._fixture(root)
            contract["authorization"]["road_cell_mapping_authorized"] = True
            with self.assertRaises(AssertionError):
                measure(
                    self._write(root, "contract.json", contract),
                    self._write(root, "candidate.json", candidate),
                    self._write(root, "readiness.json", readiness),
                    base,
                )

    def test_rejects_multicell_hold_leaking_into_unique_candidate(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base, contract, candidate, readiness = self._fixture(root)
            candidate["rows"].append({"road_osm_id": 4, "cell_id": "cell-a"})
            contract["expected"]["candidate_unique_destination_count"] = 3
            with self.assertRaises(AssertionError):
                measure(
                    self._write(root, "contract.json", contract),
                    self._write(root, "candidate.json", candidate),
                    self._write(root, "readiness.json", readiness),
                    base,
                )

    def test_rejects_stale_production_base(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base, contract, candidate, readiness = self._fixture(root)
            with self.assertRaises(AssertionError):
                measure(
                    self._write(root, "contract.json", contract),
                    self._write(root, "candidate.json", candidate),
                    self._write(root, "readiness.json", readiness),
                    "b" * 40,
                )


if __name__ == "__main__":
    unittest.main()
