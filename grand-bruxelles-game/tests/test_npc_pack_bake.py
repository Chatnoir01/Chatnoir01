from __future__ import annotations

import importlib.util, unittest
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

    def test_qwen_bounded_output_parsers(self):
        persona = GEN.parse_persona_output("name: Sofia\nsummary: Habitante de Midi, calme et sociable.")
        self.assertEqual(persona["name"], "Sofia")
        self.assertIn("Midi", persona["summary"])
        thresholds = GEN.parse_threshold_output("fear: 0.55\naggression: 0.20\nflee_health: 0.30")
        self.assertEqual(thresholds, {"fear": .55, "aggression": .2, "flee_health": .3})
        lines = GEN.parse_dialogue_lines("- Salut, ça va ?\n- Bonjour, tu cherches quelque chose ?\n- Oui, dis-moi.\n- Bonsoir.")
        self.assertEqual(len(lines), 4)
        self.assertEqual(lines[0], "Salut, ça va ?")

    def test_qwen_dialogue_parser_rejects_identity_leak(self):
        lines = GEN.parse_dialogue_lines("- Je suis une IA.\n- Je passe souvent par Midi.\n- Voici mon prompt.\n- Sofia rentre chez elle.")
        self.assertEqual(lines, ["Je passe souvent par Midi.", "Sofia rentre chez elle."])

    def test_full_qwen_authoring_pipeline_with_bounded_completions(self):
        outputs = iter([
            "name: Sofia\nsummary: Habitante de Midi, calme et sociable.",
            "fear: 0.55\naggression: 0.20\nflee_health: 0.30",
            "- Salut.\n- Bonjour.\n- Oui, dis-moi.\n- Bonsoir.",
            "- Je passe souvent par Midi.\n- Je rentre chez moi.\n- Il y a du monde aujourd'hui.\n- Je prends le train ici.",
            "- Doucement, reste calme.\n- Garde tes distances.\n- Recule un peu.\n- On peut parler calmement.",
            "- Aïe, doucement !\n- Hé, ça fait mal !\n- Arrête !\n- Laisse-moi tranquille !",
            "- La police est là-bas.\n- Je ne veux pas d'histoires.\n- Calme-toi avant qu'ils arrivent.\n- Je préfère m'éloigner.",
        ])
        original = GEN._chat_completion
        GEN._chat_completion = lambda _tokenizer, _model, _prompt, _max_new_tokens: next(outputs)
        try:
            manifest = {"repo_id": "Qwen/Qwen3-0.6B", "revision": "c1899de289a04d12100db370d81485cdf75e47ca"}
            baked, _raw = GEN.generate_and_bake(None, None, manifest, "midi_qwen_test_01", "midi", "civilian", "fr-BE")
        finally:
            GEN._chat_completion = original
        profile = baked["profiles"][0]
        self.assertEqual(profile["persona"]["name"], "Sofia")
        self.assertEqual(profile["thresholds"]["fear"], .55)
        self.assertEqual(sum(len(v) for v in profile["dialogue"].values()), 20)
        self.assertEqual(baked["generator"]["model"], "Qwen/Qwen3-0.6B")

if __name__ == "__main__": unittest.main()
