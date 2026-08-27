from __future__ import annotations

import copy
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools" / "qa"))

from check_corrected_frame_destination_atomic_migration_preflight import measure  # noqa: E402


BASE_SHA = "a" * 40


def contract() -> dict:
    return {
        "schema": "grand-bruxelles-corrected-frame-destination-atomic-migration-preflight-contract-v1",
        "status": "MEASUREMENT_PENDING",
        "production_base_sha": BASE_SHA,
        "source": {
            "provider": "OpenStreetMap contributors via Overpass API",
            "license": "ODbL-1.0",
            "crs": "EPSG:31370",
            "road_source_sha256": "1" * 64,
            "corrected_crosswalk_semantic_sha256": "2" * 64,
            "corrected_readiness_semantic_sha256": "3" * 64,
        },
        "expected": {
            "production_mapping_count": 2,
            "production_destination_count": 2,
            "candidate_mapping_count": 3,
            "candidate_destination_count": 3,
            "candidate_mapped_cell_count": 2,
            "multicell_hold_count": 1,
            "no_registered_overlap_count": 1,
            "retained_same_cell_count": 0,
            "changed_cell_count": 1,
            "new_destination_count": 2,
            "removed_destination_count": 1,
            "representatives": [{"road_osm_id": 10, "cell_id": "cell-b"}],
        },
        "policy": {
            "artifact_only": True,
            "crosswalk_and_readiness_must_be_one_to_one": True,
            "multicell_routes_must_remain_hold": True,
            "production_files_must_remain_unchanged": True,
            "atomic_migration_required": True,
            "production_frame_update_authorized": False,
            "replace_production_crosswalk_authorized": False,
            "replace_production_readiness_authorized": False,
            "road_cell_mapping_authorized": False,
            "runtime_probe_authorized": False,
        },
        "authorization": {
            "runtime_directory_scan_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        },
    }


def crosswalk() -> dict:
    return {
        "schema": "grand-bruxelles-corrected-frame-road-cell-crosswalk-materialization-candidate-v1",
        "status": "CANDIDATE_EVIDENCE_ONLY_NOT_APPLIED",
        "semantic_sha256": "2" * 64,
        "rows": [
            {"road_osm_id": 10, "cell_id": "cell-b"},
            {"road_osm_id": 30, "cell_id": "cell-b"},
            {"road_osm_id": 40, "cell_id": "cell-c"},
        ],
        "multicell_hold_rows": [{"road_osm_id": 50, "cell_ids": ["cell-b", "cell-c"]}],
        "materialization_policy": {
            "replace_current_crosswalk_authorized": False,
            "write_production_crosswalk_authorized": False,
        },
        "authorization": {
            "production_frame_update_authorized": False,
            "road_cell_mapping_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        },
    }


def readiness() -> dict:
    rows = []
    for road_id, cell_id in ((10, "cell-b"), (30, "cell-b"), (40, "cell-c")):
        rows.append(
            {
                "road_osm_id": road_id,
                "cell_id": cell_id,
                "readiness": "REGISTERED_NOT_RENDERED",
                "render_authorized": False,
                "collision_authorized": False,
                "runtime_mount_authorized": False,
                "safe_spawn_authorized": False,
                "jouable_authorized": False,
            }
        )
    return {
        "schema": "grand-bruxelles-corrected-frame-road-destination-readiness-candidate-v1",
        "status": "CANDIDATE_SOURCE_BACKED_REGISTERED_NOT_RENDERED",
        "semantic_sha256": "3" * 64,
        "accounting": {"no_registered_overlap_count": 1},
        "destinations": rows,
        "multicell_hold_rows": [{"road_osm_id": 50, "cell_ids": ["cell-b", "cell-c"]}],
        "authorization": {
            "runtime_directory_scan_authorized": False,
            "runtime_mount_authorized": False,
            "rendered_geometry_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_promotion_authorized": False,
        },
    }


def production_crosswalk() -> dict:
    return {
        "destination_readiness": "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY",
        "rows": [
            {"road_osm_id": 10, "cell_id": "cell-a"},
            {"road_osm_id": 20, "cell_id": "cell-a"},
        ],
        "road_cell_mapping_authorized": False,
        "runtime_directory_scan_authorized": False,
        "runtime_mount_authorized": False,
        "rendered_geometry_authorized": False,
        "collision_authorized": False,
        "safe_spawn_authorized": False,
        "jouable_promotion_authorized": False,
    }


def production_readiness() -> dict:
    return {
        "destinations": [
            {"road_osm_id": 10, "cell_id": "cell-a"},
            {"road_osm_id": 20, "cell_id": "cell-a"},
        ],
        "authorization": {
            "road_cell_mapping_authorized": False,
            "runtime_directory_scan_authorized": False,
            "runtime_mount_authorized": False,
            "render_authorized": False,
            "collision_authorized": False,
            "safe_spawn_authorized": False,
            "jouable_authorized": False,
        },
    }


class AtomicMigrationPreflightTests(unittest.TestCase):
    def test_valid_pair_is_measured_without_authority(self):
        result = measure(contract(), crosswalk(), readiness(), production_crosswalk(), production_readiness(), BASE_SHA)
        self.assertEqual(result["status"], "ATOMIC_PAIR_PROVEN_EVIDENCE_ONLY_NOT_APPLIED")
        self.assertEqual(result["accounting"]["changed_cell_count"], 1)
        self.assertEqual(result["accounting"]["new_destination_count"], 2)
        self.assertEqual(result["accounting"]["removed_destination_count"], 1)
        self.assertTrue(all(value is False for value in result["authorization"].values()))

    def test_readiness_cell_mismatch_fails(self):
        candidate_readiness = readiness()
        candidate_readiness["destinations"][0]["cell_id"] = "wrong-cell"
        with self.assertRaisesRegex(RuntimeError, "crosswalk/readiness mismatch"):
            measure(contract(), crosswalk(), candidate_readiness, production_crosswalk(), production_readiness(), BASE_SHA)

    def test_multicell_hold_leak_fails(self):
        candidate = crosswalk()
        candidate["rows"].append({"road_osm_id": 50, "cell_id": "cell-b"})
        with self.assertRaisesRegex(RuntimeError, "HOLD leaked"):
            measure(contract(), candidate, readiness(), production_crosswalk(), production_readiness(), BASE_SHA)

    def test_runtime_authority_open_fails(self):
        candidate_readiness = readiness()
        candidate_readiness["authorization"]["runtime_mount_authorized"] = True
        with self.assertRaisesRegex(RuntimeError, "authorization drift"):
            measure(contract(), crosswalk(), candidate_readiness, production_crosswalk(), production_readiness(), BASE_SHA)

    def test_production_pair_mismatch_fails(self):
        current_readiness = production_readiness()
        current_readiness["destinations"][1]["cell_id"] = "wrong-cell"
        with self.assertRaisesRegex(RuntimeError, "production crosswalk/readiness are not one-to-one"):
            measure(contract(), crosswalk(), readiness(), production_crosswalk(), current_readiness, BASE_SHA)


if __name__ == "__main__":
    unittest.main()
