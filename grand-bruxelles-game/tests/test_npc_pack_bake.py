from __future__ import annotations

import importlib.util, unittest
from pathlib import Path

MODULE_PATH = Path(__file__).resolve().parents[1] / "tools" / "bake_npc_pack.py"
SPEC = importlib.util.spec_from_file_location("bake_npc_pack", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
MOD = importlib.util.module_from_spec(SPEC); SPEC.loader.exec_module(MOD)

class NpcPackBakeTest(unittest.TestCase):
    def source(self, count: int = 20):
        lines = [f"Réplique numéro {i}." for i in range(count)]
        dialogue = {"greeting": lines[:4], "smalltalk": lines[4:8], "warning": lines[8:12], "hurt": lines[12:16], "police": lines[16:]}
        return {"generator": {"provider": "local_qwen", "model": "Qwen/Qwen3-0.6B", "revision": "c1899de289a04d12100db370d81485cdf75e47ca"}, "profiles": [{"id": "midi_resident_01", "zone": "midi", "locale": "fr-BE", "archetype": "civilian", "persona": {"name": "Nora", "summary": "Habitante de Bruxelles qui évite les conflits."}, "thresholds": {"fear": .55, "aggression": .2, "flee_health": .3}, "dialogue": dialogue}]}

    def test_bakes_complete_llm_draft(self):
        baked = MOD.bake_payload(self.source())
        self.assertEqual(baked["schema"], "grand-bruxelles-npc-pack-v1")
        self.assertEqual(baked["generator"]["mode"], "offline_llm_bake")
        self.assertEqual(baked["generator"]["model"], "Qwen/Qwen3-0.6B")
        self.assertEqual(len(baked["generator"]["source_sha256"]), 64)
        profile = baked["profiles"][0]
        self.assertEqual(profile["thresholds"]["fear"], .55)
        self.assertEqual(sum(len(v) for v in profile["dialogue"].values()), 20)

    def test_rejects_short_or_oversized_dialogue(self):
        with self.assertRaises(MOD.BakeError): MOD.bake_payload(self.source(19))
        source = self.source(20); source["profiles"][0]["dialogue"]["police"] += [f"Extra {i}." for i in range(21)]
        with self.assertRaises(MOD.BakeError): MOD.bake_payload(source)

    def test_rejects_invalid_threshold(self):
        source = self.source(); source["profiles"][0]["thresholds"]["aggression"] = 1.2
        with self.assertRaises(MOD.BakeError): MOD.bake_payload(source)

if __name__ == "__main__": unittest.main()
