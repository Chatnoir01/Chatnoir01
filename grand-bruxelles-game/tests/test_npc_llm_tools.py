from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SERVER_PATH = ROOT / "tools" / "npc_llm_server.py"
DOWNLOAD_PATH = ROOT / "tools" / "download_npc_llm.py"
MANIFEST_PATH = ROOT / "data" / "ai" / "npc_llm_model.json"


def _load_module(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class NpcLlmToolsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = _load_module("npc_llm_server", SERVER_PATH)
        cls.download = _load_module("download_npc_llm", DOWNLOAD_PATH)
        cls.manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    def test_model_manifest_is_pinned_and_external(self):
        self.assertEqual(self.manifest["repo_id"], "Qwen/Qwen3-0.6B")
        self.assertEqual(self.manifest["revision"], "c1899de289a04d12100db370d81485cdf75e47ca")
        self.assertEqual(self.manifest["license"], "apache-2.0")
        self.assertEqual(self.manifest["local_dir"], "models/qwen3-0.6b")
        self.assertEqual(len(self.manifest["revision"]), 40)
        self.assertFalse((ROOT / self.manifest["local_dir"] / "model.safetensors").exists())
        gitignore = (ROOT.parent / ".gitignore").read_text(encoding="utf-8")
        self.assertIn("grand-bruxelles-game/models/", gitignore)

    def test_download_plan_uses_exact_revision(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            plan = self.download.download_plan(self.manifest, Path(temp_dir))
        self.assertEqual(plan["repo_id"], "Qwen/Qwen3-0.6B")
        self.assertEqual(plan["revision"], self.manifest["revision"])
        self.assertTrue(str(plan["destination"]).endswith("models/qwen3-0.6b"))

    def test_server_prompt_forces_persona_blackboard_and_two_lines(self):
        request = self.server.validate_request({
            "npc_id": "npc-jette-01",
            "persona": {"name": "Nora", "zone": "jette"},
            "blackboard": {
                "threat": 0.7,
                "health": 66.0,
                "police_nearby": False,
                "distance_to_player": 1.3,
                "zone": "jette",
            },
            "memory": [{"user": "Salut", "action": "idle", "line": "Salut."}],
            "user_message": "Pourquoi tu recules ?",
        })
        messages = self.server.build_messages(request)
        self.assertEqual(messages[0]["role"], "system")
        system = messages[0]["content"]
        self.assertIn("Tu es Nora", system)
        self.assertIn("Tu n'es pas une IA", system)
        self.assertIn("action: <idle|walk|alert|defend|fight|flee|hurt>", system)
        self.assertIn("line: <phrase française courte>", system)
        self.assertIn("jette", messages[-1]["content"])
        self.assertIn("66.0", messages[-1]["content"])

    def test_request_validation_isolated_and_bounded(self):
        with self.assertRaises(self.server.RequestError):
            self.server.validate_request({"npc_id": "../other", "persona": {}, "blackboard": {}, "memory": [], "user_message": "x"})
        with self.assertRaises(self.server.RequestError):
            self.server.validate_request({"npc_id": "npc-1", "persona": {"name": "N", "zone": "jette"}, "blackboard": {}, "memory": [], "user_message": "x" * 321})
        valid = self.server.validate_request({
            "npc_id": "npc-1",
            "persona": {"name": "Nora", "zone": "jette"},
            "blackboard": {},
            "memory": [
                {"user": str(i), "action": "idle", "line": "ok"}
                for i in range(8)
            ],
            "user_message": "Salut",
        })
        self.assertEqual(len(valid["memory"]), 4)

    def test_smoke_output_contract_parser(self):
        parsed = self.server.parse_two_line_output("action: defend\nline: Recule, s'il te plaît.")
        self.assertEqual(parsed["action"], "defend")
        self.assertEqual(parsed["line"], "Recule, s'il te plaît.")
        with self.assertRaises(self.server.RequestError):
            self.server.parse_two_line_output("Je vais réfléchir longtemps.")


if __name__ == "__main__":
    unittest.main()
