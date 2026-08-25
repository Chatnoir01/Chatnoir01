#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from build_driveway_registered_cell_crosswalk import load_registered_cells


GATES = {
    "runtime_geometry": False,
    "collisions": False,
    "streaming": False,
    "terrain": False,
    "heights": False,
    "photo_match": False,
    "performance": False,
}


def manifest_root(base: Path, *, prefixed: bool = False) -> Path:
    root = base / ("grand-bruxelles-game" if prefixed else "") / "data" / "cell_manifests"
    root.mkdir(parents=True, exist_ok=True)
    return root


def write_manifest(root: Path, *, state: str = "data_ready", gates: dict[str, bool] | None = None) -> None:
    payload = {
        "format": "grand-bruxelles-cell-maturity-v1",
        "cell_id": "bxl-e149000-n169000-s500",
        "crs": "EPSG:31370",
        "bbox": [149000.0, 169000.0, 149500.0, 169500.0],
        "maturity": {"state": state, "gates": dict(GATES if gates is None else gates)},
    }
    (root / "bxl-e149000-n169000-s500.json").write_text(json.dumps(payload), encoding="utf-8")


class RegisteredCellFailClosedTest(unittest.TestCase):
    def test_source_only_data_ready_manifest_is_accepted(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = manifest_root(Path(tmp))
            write_manifest(root)
            rows = load_registered_cells(root)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["maturity_state"], "data_ready")
            self.assertEqual(
                rows[0]["manifest_path"],
                "data/cell_manifests/bxl-e149000-n169000-s500.json",
            )
            self.assertTrue(all(value is False for value in rows[0]["maturity_gates"].values()))

    def test_manifest_path_is_independent_of_repository_prefix(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp)
            plain_root = manifest_root(base / "plain")
            prefixed_root = manifest_root(base / "prefixed", prefixed=True)
            write_manifest(plain_root)
            write_manifest(prefixed_root)
            plain = load_registered_cells(plain_root)
            prefixed = load_registered_cells(prefixed_root)
            self.assertEqual(plain, prefixed)
            self.assertEqual(
                plain[0]["manifest_path"],
                "data/cell_manifests/bxl-e149000-n169000-s500.json",
            )

    def test_noncanonical_manifest_root_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            write_manifest(root)
            with self.assertRaisesRegex(RuntimeError, "manifest root must end in data/cell_manifests"):
                load_registered_cells(root)

    def test_runtime_ready_gate_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = manifest_root(Path(tmp))
            gates = dict(GATES)
            gates["runtime_geometry"] = True
            write_manifest(root, gates=gates)
            with self.assertRaisesRegex(RuntimeError, "maturity gate opened unexpectedly"):
                load_registered_cells(root)

    def test_non_data_ready_state_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            root = manifest_root(Path(tmp))
            write_manifest(root, state="runtime_ready")
            with self.assertRaisesRegex(RuntimeError, "maturity state drift"):
                load_registered_cells(root)


if __name__ == "__main__":
    unittest.main()
