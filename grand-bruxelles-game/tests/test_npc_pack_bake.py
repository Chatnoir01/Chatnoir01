from __future__ import annotations

import importlib.util, json, unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BAKER_PATH = ROOT / "tools" / "bake_npc_pack.py"
GENERATOR_PATH = ROOT / "tools" / "generate_npc_pack_qwen.py"

def load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module); return module

MOD = load_module("bake_npc_pack", BAKER_PATH)
GEN = load_module("generate_npc_pack_qwen", GENERATOR_PATH)

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

    def test_qwen_generator_prompt_requires_full_pack(self):
        prompt = GEN.build_prompt("midi_qwen_01", "midi", "civilian", "fr-BE")
        self.assertIn('"fear": 0.0', prompt)
        self.assertIn('"aggression": 0.0', prompt)
        self.assertIn("exactement 20 phrases", prompt)
        self.assertIn('"greeting": [4 phrases]', prompt)
        self.assertIn("midi_qwen_01", prompt)

    def test_qwen_json_extraction_and_identity_gate(self):
        fixture = self.source()
        fixture.pop("generator", None)
        raw = "```json\n" + json.dumps(fixture, ensure_ascii=False) + "\n```"
        parsed = GEN.extract_json_object(raw)
        GEN.validate_generated_identity(parsed, "midi_resident_01", "midi", "civilian", "fr-BE")
        parsed["profiles"][0]["zone"] = "jette"
        with self.assertRaises(MOD.BakeError):
            GEN.validate_generated_identity(parsed, "midi_resident_01", "midi", "civilian", "fr-BE")

    def test_qwen_metadata_is_pinned_before_bake(self):
        draft = self.source(); draft.pop("generator", None)
        manifest = {"repo_id": "Qwen/Qwen3-0.6B", "revision": "c1899de289a04d12100db370d81485cdf75e47ca"}
        enriched = GEN.attach_generator_metadata(draft, manifest)
        baked = MOD.bake_payload(enriched)
        self.assertEqual(baked["generator"]["model"], manifest["repo_id"])
        self.assertEqual(baked["generator"]["revision"], manifest["revision"])

if __name__ == "__main__": unittest.main()
