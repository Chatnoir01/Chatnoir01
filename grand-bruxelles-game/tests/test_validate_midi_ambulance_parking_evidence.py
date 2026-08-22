#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import importlib.util
import json
import tempfile
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
        "roads": [
            {"osm_id": 288509378, "name": "Avenue Fonsny"},
            {"osm_id": 408211693, "name": "Avenue Fonsny"},
        ]
    }


def source_digest(element: dict) -> str:
    payload = json.dumps(element, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()


def candidate(evidence_id: str, road_id: int, source_id: int) -> dict:
    source_element = {
        "type": "way",
        "id": source_id,
        "version": 7,
        "timestamp": "2026-08-22T08:00:00Z",
        "tags": {"parking:right": "parallel"},
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
        "evidence_tags": {"parking:right": "parallel"},
        "evidence_note": "Exact OSM way carries explicit curbside parking semantics.",
        "runtime_approved": True,
    }


def refresh_digest(item: dict) -> None:
    item["source_element_sha256"] = source_digest(item["source_element"])


def registry(candidates: list[dict], ready: bool) -> dict:
    return {
        "format": module.FORMAT,
        "source_contract": {"license": "ODbL-1.0"},
        "target": {"required_distinct_road_count": 2},
        "candidates": candidates,
        "runtime_ready": ready,
    }


class ParkingEvidenceValidatorTest(unittest.TestCase):
    def test_current_empty_registry_is_valid_hold_but_not_ready(self) -> None:
        data = registry([], False)
        result = module.validate(data, snapshot(), False)
        self.assertFalse(result["runtime_ready"])
        with self.assertRaisesRegex(ValueError, "not ready"):
            module.validate(data, snapshot(), True)

    def test_two_distinct_source_backed_roads_are_ready(self) -> None:
        data = registry(
            [
                candidate("midi-parking-fonsny-a", 288509378, 288509378),
                candidate("midi-parking-fonsny-b", 408211693, 408211693),
            ],
            True,
        )
        result = module.validate(data, snapshot(), True)
        self.assertEqual(result["approved_distinct_road_count"], 2)
        self.assertTrue(result["runtime_ready"])

    def test_unknown_road_is_rejected(self) -> None:
        data = registry(
            [
                candidate("midi-parking-known", 288509378, 288509378),
                candidate("midi-parking-invented", 999999999, 999999999),
            ],
            True,
        )
        with self.assertRaisesRegex(ValueError, "not in vertical slice"):
            module.validate(data, snapshot(), True)

    def test_source_url_must_match_osm_identity(self) -> None:
        bad = candidate("midi-parking-bad-url", 288509378, 288509378)
        bad["source_url"] = "https://www.openstreetmap.org/way/408211693"
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source_url"):
            module.validate(data, snapshot(), False)

    def test_unrelated_osm_tag_cannot_authorize_parking(self) -> None:
        bad = candidate("midi-parking-tree", 288509378, 288509378)
        bad["evidence_tags"] = {"natural": "tree"}
        bad["source_element"]["tags"] = {"natural": "tree"}
        refresh_digest(bad)
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "unsupported parking evidence tag"):
            module.validate(data, snapshot(), False)

    def test_evidence_tags_must_match_versioned_osm_source_element(self) -> None:
        bad = candidate("midi-parking-tag-drift", 288509378, 288509378)
        bad["source_element"]["tags"] = {"highway": "primary"}
        refresh_digest(bad)
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source element tags do not contain evidence"):
            module.validate(data, snapshot(), False)

    def test_source_element_identity_must_match_declared_osm_identity(self) -> None:
        bad = candidate("midi-parking-source-drift", 288509378, 288509378)
        bad["source_element"]["id"] = 408211693
        refresh_digest(bad)
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source element identity"):
            module.validate(data, snapshot(), False)

    def test_source_element_digest_drift_is_rejected(self) -> None:
        bad = candidate("midi-parking-digest-drift", 288509378, 288509378)
        bad["source_element"]["tags"]["parking:right"] = "diagonal"
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source element SHA-256"):
            module.validate(data, snapshot(), False)

    def test_invalid_source_element_version_is_rejected(self) -> None:
        bad = candidate("midi-parking-version-drift", 288509378, 288509378)
        bad["source_element"]["version"] = 0
        refresh_digest(bad)
        data = registry([bad], False)
        with self.assertRaisesRegex(ValueError, "source element version"):
            module.validate(data, snapshot(), False)

    def test_declared_ready_cannot_override_computed_readiness(self) -> None:
        data = registry([candidate("midi-parking-only-one", 288509378, 288509378)], True)
        with self.assertRaisesRegex(ValueError, "runtime_ready drift"):
            module.validate(data, snapshot(), False)


if __name__ == "__main__":
    unittest.main()
