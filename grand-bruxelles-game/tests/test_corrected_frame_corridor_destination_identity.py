import copy
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tools.qa.measure_corrected_frame_corridor_representatives import measure


class CorridorDestinationIdentityTests(unittest.TestCase):
    def _write(self, root, name, obj):
        path = root / name
        path.write_text(json.dumps(obj, sort_keys=True, indent=2) + "\n", encoding="utf-8")
        return path

    def test_rejects_upstream_destination_id_drift(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            base = "a" * 40
            auth = {key: False for key in (
                "production_frame_update_authorized", "road_cell_mapping_authorized",
                "runtime_directory_scan_authorized", "runtime_mount_authorized",
                "rendered_geometry_authorized", "collision_authorized",
                "safe_spawn_authorized", "jouable_promotion_authorized"
            )}
            source = {
                "source": "OpenStreetMap contributors via Overpass API",
                "license": "ODbL-1.0",
                "roads": [{
                    "osm_id": 10, "name": "Road A", "class": "secondary",
                    "width": 8.0, "drivable": True, "points": [[0, 0], [1, 1]]
                }]
            }
            source_path = self._write(root, "source.json", source)
            index = {
                "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
                "semantic_sha256": "3" * 64,
                "registered_cell_count": 1,
                "road_crosswalk_authorized": False,
                "runtime_directory_scan_authorized": False,
                "runtime_mount_authorized": False,
                "rendered_geometry_authorized": False,
                "collision_authorized": False,
                "safe_spawn_authorized": False,
                "jouable_promotion_authorized": False,
                "entries": [{
                    "cell_id": "cell-a", "crs": "EPSG:31370",
                    "maturity_state": "data_ready", "evidence_only": True,
                    "manifest_path": "data/cell_manifests/cell-a.json",
                    "manifest_sha256": "4" * 64, "bbox": [0, 0, 1, 1],
                    "runtime_mount_authorized": False,
                    "rendered_geometry_authorized": False,
                    "collision_authorized": False,
                    "safe_spawn_authorized": False,
                    "jouable_promotion_authorized": False
                }]
            }
            impact = {
                "schema": "grand-bruxelles-corrected-frame-road-destination-readiness-impact-v1",
                "status": "IMPACT_EVIDENCE_ONLY_NOT_APPLIED",
                "semantic_sha256": "2" * 64,
                "authorization": copy.deepcopy(auth),
                "changed_rows": [],
                "new_rows": [{
                    "road_osm_id": 10, "candidate_cell_id": "cell-a",
                    "destination_id": "road-999"
                }]
            }
            contract = {
                "schema": "grand-bruxelles-corrected-frame-corridor-representative-contract-v1",
                "status": "MEASUREMENT_PENDING",
                "production_base_sha": base,
                "source": {
                    "provider": source["source"], "license": "ODbL-1.0",
                    "road_source_sha256": hashlib.sha256(source_path.read_bytes()).hexdigest(),
                    "impact_semantic_sha256": "2" * 64,
                    "registered_cell_index_semantic_sha256": "3" * 64,
                    "crs": "EPSG:31370"
                },
                "selection": {
                    "policy": "changed-first-then-new-lowest-osm-id-per-target-cell",
                    "target_cells": [{
                        "anchor": "a", "cell_id": "cell-a",
                        "expected_transition": "new", "expected_road_osm_id": 10
                    }]
                },
                "expected": {"representative_count": 1, "changed_count": 0, "new_count": 1},
                "policy": {
                    "measurement_only": True,
                    "replace_crosswalk_authorized": False,
                    "replace_readiness_catalog_authorized": False,
                    "representative_runtime_probe_authorized": False,
                    "atomic_followup_required": True
                },
                "authorization": copy.deepcopy(auth)
            }

            with self.assertRaises(AssertionError):
                measure(
                    self._write(root, "contract.json", contract),
                    self._write(root, "impact.json", impact),
                    source_path,
                    self._write(root, "index.json", index),
                    base,
                )


if __name__ == "__main__":
    unittest.main()
