#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools" / "validate_midi_ambulance_parking_evidence.py"
spec = importlib.util.spec_from_file_location("parking_validator", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def snapshot() -> dict:
    return {
        "corridor": {"anchors": [{"id": "midi", "x": 0.0, "z": 0.0}]},
        "roads": [
            {
                "osm_id": 108931599,
                "name": "Rue d'Angleterre - Engelandstraat",
                "class": "residential",
                "width": 5.6,
                "points": [[0.0, 0.0], [0.0, 84.0]],
            },
            {
                "osm_id": 408211693,
                "name": "Short evidence road",
                "class": "residential",
                "width": 5.6,
                "points": [[10.0, 0.0], [10.0, 10.0]],
            },
            {
                "osm_id": 288509378,
                "name": "Outside radius evidence road",
                "class": "residential",
                "width": 5.6,
                "points": [[800.0, 0.0], [800.0, 84.0]],
            },
        ],
    }


def source_digest(element: dict) -> str:
    payload = json.dumps(element, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def candidate(
    evidence_id: str,
    road_id: int = 108931599,
    *,
    source_id: int | None = None,
    evidence_tags: dict[str, str] | None = None,
    source_tags: dict[str, str] | None = None,
    runtime_approved: bool = True,
) -> dict:
    if source_id is None:
        source_id = road_id
    if source_tags is None:
        source_tags = {
            "highway": "residential",
            "parking:both": "yes",
            "parking:both:orientation": "parallel",
        }
    if evidence_tags is None:
        evidence_tags = {"parking:both": "yes"}
    source_element = {
        "type": "way",
        "id": source_id,
        "version": 7,
        "timestamp": "2026-08-22T08:00:00Z",
        "tags": source_tags,
    }
    return {
        "evidence_id": evidence_id,
        "road_osm_id": road_id,
        "source_osm_type": "way",
        "source_osm_id": source_id,
        "source_url": f"https://www.openstreetmap.org/way/{source_id}",
        "source_license": "ODbL-1.0",
        "source_accessed_at": "2026-08-22",
        "source_element": source_element,
        "source_element_sha256": source_digest(source_element),
        "evidence_tags": evidence_tags,
        "evidence_note": "Exact OSM road way carries explicit positive curbside parking semantics.",
        "runtime_approved": runtime_approved,
    }


def refresh_digest(item: dict) -> None:
    item["source_element_sha256"] = source_digest(item["source_element"])


def registry(candidates: list[dict], ready: bool) -> dict:
    return {
        "format": module.FORMAT,
        "source_contract": {
            "license": "ODbL-1.0",
            "versioned_source_binding_required": True,
        },
        "target": {
            "required_runtime_candidate_count": 2,
            "anchor_id": "midi",
            "candidate_radius_m": 360.0,
        },
        "candidates": candidates,
        "runtime_ready": ready,
    }


class ParkingEvidenceValidatorTest(unittest.TestCase):
    def test_current_empty_registry_is_valid_hold_but_not_ready(self) -> None:
        data = registry([], False)
        result = module.validate(data, snapshot(), False)
        self.assertEqual(result["runtime_candidate_count"], 0)
        self.assertFalse(result["runtime_ready"])
        with self.assertRaisesRegex(ValueError, "not ready"):
            module.validate(data, snapshot(), True)

    def test_one_long_source_backed_road_can_supply_required_runtime_slots(self) -> None:
        data = registry([candidate("midi-parking-angleterre")], True)
        result = module.validate(data, snapshot(), True)
        self.assertEqual(result["approved_distinct_road_count"], 1)
        self.assertEqual(result["runtime_candidate_count"], 3)
        self.assertTrue(result["runtime_ready"])

    def test_parking_no_cannot_authorize_runtime(self) -> None:
        bad = candidate(
            "midi-parking-no",
            evidence_tags={"parking:both": "no"},
            source_tags={"highway": "residential", "parking:both": "no"},
        )
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "no positive right-side/both"):
            module.validate(data, snapshot(), False)

    def test_left_only_parking_cannot_authorize_right_side_consumer(self) -> None:
        bad = candidate(
            "midi-parking-left-only",
            evidence_tags={"parking:left": "street_side", "parking:right": "no"},
            source_tags={"highway": "residential", "parking:left": "street_side", "parking:right": "no"},
        )
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "no positive right-side/both"):
            module.validate(data, snapshot(), False)

    def test_runtime_source_way_must_equal_vertical_slice_road(self) -> None:
        bad = candidate("midi-parking-wrong-road-source", road_id=108931599, source_id=408211693)
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "must bind the exact vertical-slice road way"):
            module.validate(data, snapshot(), False)

    def test_unknown_road_is_rejected(self) -> None:
        bad = candidate("midi-parking-invented", road_id=999999999)
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "not in vertical slice"):
            module.validate(data, snapshot(), False)

    def test_source_url_must_match_osm_identity(self) -> None:
        bad = candidate("midi-parking-bad-url")
        bad["source_url"] = "https://www.openstreetmap.org/way/408211693"
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source_url"):
            module.validate(data, snapshot(), False)

    def test_unrelated_osm_tag_cannot_authorize_parking(self) -> None:
        bad = candidate(
            "midi-parking-tree",
            evidence_tags={"natural": "tree"},
            source_tags={"natural": "tree"},
        )
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "unsupported parking evidence tag"):
            module.validate(data, snapshot(), False)

    def test_evidence_tags_must_match_versioned_osm_source_element(self) -> None:
        bad = candidate("midi-parking-tag-drift")
        bad["source_element"]["tags"] = {"highway": "residential", "parking:both": "no"}
        refresh_digest(bad)
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source element tags do not contain evidence"):
            module.validate(data, snapshot(), False)

    def test_source_element_identity_must_match_declared_osm_identity(self) -> None:
        bad = candidate("midi-parking-source-drift")
        bad["source_element"]["id"] = 408211693
        refresh_digest(bad)
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source element identity"):
            module.validate(data, snapshot(), False)

    def test_source_element_digest_drift_is_rejected(self) -> None:
        bad = candidate("midi-parking-digest-drift")
        bad["source_element"]["tags"]["parking:both"] = "street_side"
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source element SHA-256"):
            module.validate(data, snapshot(), False)

    def test_invalid_source_element_version_is_rejected(self) -> None:
        bad = candidate("midi-parking-version-drift")
        bad["source_element"]["version"] = 0
        refresh_digest(bad)
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source element version"):
            module.validate(data, snapshot(), False)

    def test_short_road_cannot_fake_runtime_readiness(self) -> None:
        bad = candidate("midi-parking-short", road_id=408211693)
        data = registry([bad], True)
        with self.assertRaisesRegex(ValueError, "runtime_ready drift"):
            module.validate(data, snapshot(), False)

    def test_out_of_radius_road_cannot_fake_runtime_readiness(self) -> None:
        bad = candidate("midi-parking-far", road_id=288509378)
        data = registry([bad], True)
        with self.assertRaisesRegex(ValueError, "runtime_ready drift"):
            module.validate(data, snapshot(), False)


if __name__ == "__main__":
    unittest.main()
