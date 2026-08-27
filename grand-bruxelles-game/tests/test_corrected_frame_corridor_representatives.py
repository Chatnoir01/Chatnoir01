import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tools.qa.measure_corrected_frame_corridor_representatives import measure


class CorridorRepresentativeTests(unittest.TestCase):
    def _write(self, root, name, obj):
        path = root / name
        path.write_text(json.dumps(obj, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        return path

    def _fixture(self, root):
        base = "a" * 40
        auth = {key: False for key in ("production_frame_update_authorized", "road_cell_mapping_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized")}
        source = {
            "source": "OpenStreetMap contributors via Overpass API",
            "license": "ODbL-1.0",
            "roads": [
                {"osm_id": 10, "name": "Road A", "class": "secondary", "width": 8.0, "drivable": True, "points": [[0, 0], [1, 1]]},
                {"osm_id": 20, "name": "Road B", "class": "tertiary", "width": 7.0, "drivable": True, "points": [[2, 2], [3, 3]]}
            ]
        }
        source_path = self._write(root, "source.json", source)
        index = {
            "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
            "semantic_sha256": "3" * 64,
            "registered_cell_count": 2,
            "road_crosswalk_authorized": False,
            "runtime_directory_scan_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
            "entries": [
                {"cell_id": cell, "crs": "EPSG:31370", "maturity_state": "data_ready", "evidence_only": True, "manifest_path": f"data/cell_manifests/{cell}.json", "manifest_sha256": "4" * 64, "bbox": [0, 0, 1, 1], "runtime_mount_authorized": False, "rendered_geometry_authorized": False, "collision_authorized": False, "safe_spawn_authorized": False, "jouable_promotion_authorized": False}
                for cell in ("cell-a", "cell-b")
            ]
        }
        impact = {
            "schema": "grand-bruxelles-corrected-frame-road-destination-readiness-impact-v1",
            "status": "IMPACT_EVIDENCE_ONLY_NOT_APPLIED",
            "semantic_sha256": "2" * 64,
            "authorization": copy.deepcopy(auth),
            "changed_rows": [{"road_osm_id": 20, "current_cell_id": "old", "candidate_cell_id": "cell-b", "destination_id": "road-20"}],
            "new_rows": [{"road_osm_id": 10, "candidate_cell_id": "cell-a", "destination_id": "road-10"}]
        }
        contract = {
            "schema": "grand-bruxelles-corrected-frame-corridor-representative-contract-v1",
            "status": "MEASUREMENT_PENDING",
            "production_base_sha": base,
            "source": {"provider": source["source"], "license": "ODbL-1.0", "road_source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(), "impact_semantic_sha256": "2" * 64, "registered_cell_index_semantic_sha256": "3" * 64, "crs": "EPSG:31370"},
            "selection": {"policy": "changed-first-then-new-lowest-osm-id-per-target-cell", "target_cells": [{"anchor": "a", "cell_id": "cell-a", "expected_transition": "new", "expected_road_osm_id": 10}, {"anchor": "b", "cell_id": "cell-b", "expected_transition": "changed", "expected_road_osm_id": 20}]},
            "expected": {"representative_count": 2, "changed_count": 1, "new_count": 1},
            "policy": {"measurement_only": True, "replace_crosswalk_authorized": False, "replace_readiness_catalog_authorized": False, "representative_runtime_probe_authorized": False, "atomic_followup_required": True},
            "authorization": copy.deepcopy(auth)
        }
        return base, contract, impact, index, source_path

    def test_selects_changed_first_and_new_fallback(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base, contract, impact, index, source = self._fixture(root)
            result = measure(self._write(root, "contract.json", contract), self._write(root, "impact.json", impact), source, self._write(root, "index.json", index), base)
            self.assertEqual([10, 20], [row["road_osm_id"] for row in result["representatives"]])
            self.assertTrue(all(v is False for v in result["authorization"].values()))

    def test_rejects_source_byte_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base, contract, impact, index, source = self._fixture(root)
            source.write_text(source.read_text() + " ", encoding="utf-8")
            with self.assertRaises(AssertionError):
                measure(self._write(root, "contract.json", contract), self._write(root, "impact.json", impact), source, self._write(root, "index.json", index), base)

    def test_rejects_runtime_authorization(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base, contract, impact, index, source = self._fixture(root)
            contract["authorization"]["runtime_mount_authorized"] = True
            with self.assertRaises(AssertionError):
                measure(self._write(root, "contract.json", contract), self._write(root, "impact.json", impact), source, self._write(root, "index.json", index), base)

    def test_rejects_selection_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base, contract, impact, index, source = self._fixture(root)
            contract["selection"]["target_cells"][0]["expected_road_osm_id"] = 999
            with self.assertRaises(AssertionError):
                measure(self._write(root, "contract.json", contract), self._write(root, "impact.json", impact), source, self._write(root, "index.json", index), base)


if __name__ == "__main__":
    unittest.main()
