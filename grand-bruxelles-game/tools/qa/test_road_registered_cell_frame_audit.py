#!/usr/bin/env python3
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from road_registered_cell_frame_audit import BOUND_STATUS, HOLD_STATUS, audit


def write(path: Path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload), encoding="utf-8")


def sha(path: Path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class RoadRegisteredCellFrameAuditTest(unittest.TestCase):
    def setUp(self):
        self.td = tempfile.TemporaryDirectory()
        self.root = Path(self.td.name) / "grand-bruxelles-game"
        self.road_source = self.root / "data/osm/source.game.json"
        self.road_index = self.root / "data/runtime/road_destination_runtime_index.json"
        self.cell_index = self.root / "data/provenance/brussels_registered_cell_manifest_index.json"
        self.crosswalk = self.root / "data/provenance/brussels_road_registered_cell_crosswalk.json"
        self.coverage = self.root / "data/city_machine/road_cell_coverage_candidates.json"
        write(self.road_source, {
            "format": "grand-bruxelles-osm-v1",
            "source": "OpenStreetMap contributors via Overpass API",
            "license": "ODbL-1.0",
            "origin": {"lat": 50.8419, "lon": 4.348},
            "roads": [
                {"osm_id": 100, "drivable": True, "points": [[0.0, 0.0], [10.0, 0.0]]},
                {"osm_id": 200, "drivable": True, "points": [[10.0, 0.0], [20.0, 0.0]]},
            ],
        })
        write(self.road_index, {
            "format": "grand-bruxelles-road-runtime-index-v1",
            "source_lookup_only": True,
            "authorization": {
                "source_lookup_only": True,
                "collision_authorized": False,
                "jouable_authorized": False,
                "render_authorized": False,
                "runtime_mount_authorized": False,
                "safe_spawn_authorized": False,
            },
            "documents": [{
                "path": "data/osm/source.game.json",
                "sha256": sha(self.road_source),
                "road_ids": [100, 200],
            }],
        })
        write(self.cell_index, {
            "schema": "grand-bruxelles-registered-cell-manifest-index-v1",
            "destination_readiness": "REGISTERED_CELL_INDEX_EVIDENCE_ONLY",
            "registered_cell_count": 1,
            "entries": [{
                "cell_id": "bxl-e149000-n169000-s500",
                "crs": "EPSG:31370",
                "bbox": [149000.0, 169000.0, 149500.0, 169500.0],
            }],
            "runtime_directory_scan_authorized": False,
            "road_crosswalk_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        })

    def tearDown(self):
        self.td.cleanup()

    def _write_bound_crosswalk(self, readiness):
        bbox = [149000.0, 169000.0, 149500.0, 169500.0]
        write(self.coverage, {
            "schema": "grand-bruxelles-road-cell-coverage-candidates-v2",
            "status": "DISCOVERED_SOURCE_ONLY",
            "frame": {
                "crs": "EPSG:31370",
                "formula": "E=origin_easting_m+x;N=origin_northing_m-z",
            },
            "road_source_sha256": sha(self.road_source),
            "semantic_sha256": "coverage-semantic",
            "road_semantic_sha256": "road-semantic",
            "road_cell_mapping_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
            "candidates": [{
                "grid_cell_id": "E149000_N169000",
                "road_ids": [100, 200],
                "bbox": bbox,
            }],
        })
        write(self.crosswalk, {
            "schema": "grand-bruxelles-road-registered-cell-crosswalk-v1",
            "destination_readiness": readiness,
            "coverage_semantic_sha256": "coverage-semantic",
            "road_semantic_sha256": "road-semantic",
            "road_cell_mapping_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
            "rows": [{
                "road_osm_id": 100,
                "cell_id": "bxl-e149000-n169000-s500",
                "grid_cell_id": "E149000_N169000",
            }],
        })

    def test_current_local_frame_holds_without_explicit_transform(self):
        report = audit(self.road_index, self.cell_index, self.crosswalk)
        self.assertEqual(report["status"], HOLD_STATUS)
        self.assertEqual(report["indexed_road_count"], 2)
        self.assertFalse(report["source_frames"][0]["frame_proven"])
        self.assertFalse(report["road_crosswalk_authorized"])

    def test_explicit_lambert72_crs_can_advance_to_review(self):
        source = json.loads(self.road_source.read_text())
        source["crs"] = "EPSG:31370"
        write(self.road_source, source)
        index = json.loads(self.road_index.read_text())
        index["documents"][0]["sha256"] = sha(self.road_source)
        write(self.road_index, index)
        report = audit(self.road_index, self.cell_index, self.crosswalk)
        self.assertEqual(report["status"], "READY_FOR_DETERMINISTIC_SPATIAL_CROSSWALK_REVIEW")
        self.assertTrue(report["source_frames"][0]["frame_proven"])

    def test_explicit_transform_contract_can_advance_to_review(self):
        source = json.loads(self.road_source.read_text())
        source["coordinate_transform"] = {
            "target_crs": "EPSG:31370",
            "method": "locked-reviewed-transform-v1",
        }
        write(self.road_source, source)
        index = json.loads(self.road_index.read_text())
        index["documents"][0]["sha256"] = sha(self.road_source)
        write(self.road_index, index)
        report = audit(self.road_index, self.cell_index, self.crosswalk)
        self.assertEqual(report["status"], "READY_FOR_DETERMINISTIC_SPATIAL_CROSSWALK_REVIEW")

    def test_corrected_frame_evidence_only_crosswalk_is_bound(self):
        self._write_bound_crosswalk("CORRECTED_FRAME_ROAD_CELL_CROSSWALK_EVIDENCE_ONLY")
        report = audit(self.road_index, self.cell_index, self.crosswalk, self.coverage)
        self.assertEqual(report["status"], BOUND_STATUS)
        self.assertTrue(report["external_coverage_frame_bound"])
        self.assertFalse(report["runtime_mount_authorized"])
        self.assertFalse(report["jouable_promotion_authorized"])

    def test_widened_crosswalk_readiness_still_fails(self):
        self._write_bound_crosswalk("PLAYABLE")
        with self.assertRaisesRegex(RuntimeError, "crosswalk readiness widened"):
            audit(self.road_index, self.cell_index, self.crosswalk, self.coverage)

    def test_source_sha_drift_fails(self):
        source = json.loads(self.road_source.read_text())
        source["roads"][0]["points"].append([99.0, 99.0])
        write(self.road_source, source)
        with self.assertRaises(RuntimeError):
            audit(self.road_index, self.cell_index, self.crosswalk)

    def test_crosswalk_presence_stops_hold_lot(self):
        write(self.crosswalk, {"schema": "grand-bruxelles-road-registered-cell-crosswalk-v1"})
        with self.assertRaises(RuntimeError):
            audit(self.road_index, self.cell_index, self.crosswalk)

    def test_future_authorization_fails(self):
        index = json.loads(self.road_index.read_text())
        index["authorization"]["streaming_authorized"] = True
        write(self.road_index, index)
        with self.assertRaises(RuntimeError):
            audit(self.road_index, self.cell_index, self.crosswalk)


if __name__ == "__main__":
    unittest.main()
