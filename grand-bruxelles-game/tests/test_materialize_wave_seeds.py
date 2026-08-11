from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "tools" / "materialize_wave_seeds.py"
SPEC = importlib.util.spec_from_file_location("materialize_wave_seeds", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class MaterializeWaveSeedsTests(unittest.TestCase):
    def test_load_valid_batch_and_build_exact_command(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "seeds.json"
            payload = {
                "format": MODULE.FORMAT,
                "wave": "R3",
                "seed_count": 1,
                "seeds": [
                    {
                        "zone_id": "forest",
                        "cell_id": "bxl-e147000-n168500-s500",
                        "bbox": [147000, 168500, 147500, 169000],
                    }
                ],
            }
            path.write_text(json.dumps(payload), encoding="utf-8")
            loaded = MODULE.load_seed_batch(path)
            self.assertEqual(loaded["wave"], "R3")
            command = MODULE.command_for_seed(loaded["seeds"][0], Path("out"), 3)
            self.assertIn("bxl-e147000-n168500-s500", command)
            self.assertIn("147000.0,168500.0,147500.0,169000.0", command)
            self.assertIn("out/bxl-e147000-n168500-s500", command)
            self.assertTrue(any("build_urbis_cell.py" in item for item in command))

    def test_duplicate_global_ids_are_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "seeds.json"
            seed = {
                "zone_id": "a",
                "cell_id": "bxl-e147000-n168500-s500",
                "bbox": [147000, 168500, 147500, 169000],
            }
            path.write_text(
                json.dumps(
                    {
                        "format": MODULE.FORMAT,
                        "seed_count": 2,
                        "seeds": [seed, {**seed, "zone_id": "b"}],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                MODULE.load_seed_batch(path)

    def test_invalid_cell_id_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "seeds.json"
            path.write_text(
                json.dumps(
                    {
                        "format": MODULE.FORMAT,
                        "seed_count": 1,
                        "seeds": [
                            {"zone_id": "x", "cell_id": "local-001", "bbox": [0, 0, 500, 500]}
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                MODULE.load_seed_batch(path)

    def test_seed_count_mismatch_is_rejected(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            path = Path(temp_dir) / "seeds.json"
            path.write_text(
                json.dumps(
                    {
                        "format": MODULE.FORMAT,
                        "seed_count": 2,
                        "seeds": [
                            {
                                "zone_id": "x",
                                "cell_id": "bxl-e1000-n1000-s500",
                                "bbox": [1000, 1000, 1500, 1500],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            with self.assertRaises(ValueError):
                MODULE.load_seed_batch(path)


if __name__ == "__main__":
    unittest.main()
