from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "bake_npc_dialogues.py"
SPEC = importlib.util.spec_from_file_location("bake_npc_dialogues", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class NpcDialogueBakeTest(unittest.TestCase):
    def _source(self):
        return {
            "generator": {"provider": "test", "model": "fixture", "run_id": "run-1"},
            "personas": [
                {
                    "id": "jette_local_01",
                    "zone": "jette",
                    "locale": "fr-BE",
                    "intents": {
                        "smalltalk": ["Je rentre chez moi."],
                        "greeting": ["Bonjour.", "Salut."],
                    },
                },
                {
                    "id": "midi_local_01",
                    "zone": "midi",
                    "locale": "nl-BE",
                    "intents": {
                        "greeting": ["Dag."],
                    },
                },
            ],
        }

    def test_bake_is_canonical_and_offline(self):
        source = self._source()
        source_bytes = json.dumps(source, ensure_ascii=False, sort_keys=True).encode("utf-8")
        first = MODULE.bake_payload(source, source_bytes)
        second = MODULE.bake_payload(source, source_bytes)
        self.assertEqual(first, second)
        self.assertEqual(first["schema"], "grand-bruxelles-npc-dialogue-v1")
        self.assertEqual(first["generator"]["mode"], "offline_llm_bake")
        self.assertEqual([row["id"] for row in first["personas"]], ["jette_local_01", "midi_local_01"])
        self.assertEqual(first["personas"][0]["intents"]["greeting"], ["Bonjour.", "Salut."])
        self.assertEqual(len(first["generator"]["source_sha256"]), 64)

    def test_duplicate_generated_line_is_rejected(self):
        source = self._source()
        source["personas"][0]["intents"]["greeting"] = ["Salut.", "Salut."]
        with self.assertRaises(MODULE.BakeError):
            MODULE.bake_payload(source)

    def test_overlong_generated_line_is_rejected(self):
        source = self._source()
        source["personas"][0]["intents"]["greeting"] = ["x" * 181]
        with self.assertRaises(MODULE.BakeError):
            MODULE.bake_payload(source)

    def test_runtime_mode_cannot_be_supplied_by_source(self):
        source = self._source()
        source["generator"]["mode"] = "runtime_network"
        baked = MODULE.bake_payload(source)
        self.assertEqual(baked["generator"]["mode"], "offline_llm_bake")


if __name__ == "__main__":
    unittest.main()
