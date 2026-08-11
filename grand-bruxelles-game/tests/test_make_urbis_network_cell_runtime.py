from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "make_urbis_network_cell_runtime.py"
SPEC = importlib.util.spec_from_file_location("make_urbis_network_cell_runtime", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MakeUrbisNetworkCellRuntimeTests(unittest.TestCase):
    def test_crossing_segment_is_clipped_to_cell(self) -> None:
        clipped = MODULE.clip_segment([-10.0, 250.0], [510.0, 250.0], (0.0, 0.0, 500.0, 500.0))
        self.assertIsNotNone(clipped)
        start, end = clipped
        self.assertEqual(start, [0.0, 250.0])
        self.assertEqual(end, [500.0, 250.0])

    def test_outside_segment_is_rejected(self) -> None:
        self.assertIsNone(
            MODULE.clip_segment([-10.0, -10.0], [-5.0, -5.0], (0.0, 0.0, 500.0, 500.0))
        )

    def test_network_runtime_contains_clipped_street_segment(self) -> None:
        street = {
            "features": [
                {
                    "id": "road-1",
                    "properties": {"INSPIRE_ID": "road-1", "STRNAMEFRE": "Rue Test"},
                    "geometry": {
                        "type": "LineString",
                        "coordinates": [[147400.0, 169750.0], [148100.0, 169750.0]],
                    },
                }
            ]
        }
        empty = {"features": []}
        runtime = MODULE.build_runtime(
            street,
            empty,
            empty,
            (147500.0, 169500.0, 148000.0, 170000.0),
            "cell-test",
        )
        self.assertEqual(runtime["stats"]["street_segments"], 1)
        segment = runtime["street_axes"][0]
        self.assertEqual(segment["street_fr"], "Rue Test")
        self.assertEqual(len(segment["points"]), 2)


if __name__ == "__main__":
    unittest.main()
