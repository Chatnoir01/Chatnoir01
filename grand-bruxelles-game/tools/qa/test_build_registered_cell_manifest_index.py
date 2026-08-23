#!/usr/bin/env python3
import json
import tempfile
import unittest
from pathlib import Path

from build_registered_cell_manifest_index import build

BASE = "76900d64381e426478564f715792fcbb3a8992b6"


def manifest(**overrides):
    doc = {
        "format": "grand-bruxelles-cell-maturity-v1",
        "cell_id": "bxl-e149000-n169000-s500",
        "crs": "EPSG:31370",
        "bbox": [149000.0, 169000.0, 149500.0, 169500.0],
        "maturity": {"state": "data_ready", "gates": {"runtime_geometry": False, "collisions": False}},
        "provenance": {"source_records_present": True},
        "geometry": {"authoritative_geometry_ready": True},
    }
    doc.update(overrides)
    return doc


class RegisteredCellManifestIndexTest(unittest.TestCase):
    def _build(self, doc):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            d = root / "data" / "cell_manifests"
            d.mkdir(parents=True)
            (d / "bxl-e149000-n169000-s500.json").write_text(json.dumps(doc))
            return build(d, root, BASE)

    def test_green_is_evidence_only(self):
        out = self._build(manifest())
        self.assertEqual(out["registered_cell_count"], 1)
        self.assertEqual(out["destination_readiness"], "REGISTERED_CELL_INDEX_EVIDENCE_ONLY")
        self.assertFalse(out["runtime_directory_scan_authorized"])
        self.assertFalse(out["road_crosswalk_authorized"])
        for key in ("runtime_mount_authorized", "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized", "jouable_promotion_authorized"):
            self.assertFalse(out[key])
            self.assertFalse(out["entries"][0][key])

    def test_rejects_open_runtime_gate(self):
        doc = manifest()
        doc["maturity"]["gates"]["runtime_geometry"] = True
        with self.assertRaisesRegex(RuntimeError, "maturity gate must remain boolean false"):
            self._build(doc)

    def test_rejects_future_non_boolean_gate(self):
        doc = manifest()
        doc["maturity"]["gates"]["future_gate"] = "false"
        with self.assertRaisesRegex(RuntimeError, "maturity gate must remain boolean false"):
            self._build(doc)

    def test_rejects_runtime_ready_state(self):
        doc = manifest()
        doc["maturity"]["state"] = "runtime_ready"
        with self.assertRaisesRegex(RuntimeError, "not evidence-only data_ready"):
            self._build(doc)

    def test_rejects_bbox_identity_drift(self):
        with self.assertRaisesRegex(RuntimeError, "bbox does not match cell id"):
            self._build(manifest(bbox=[149001.0, 169000.0, 149500.0, 169500.0]))


if __name__ == "__main__":
    unittest.main()
