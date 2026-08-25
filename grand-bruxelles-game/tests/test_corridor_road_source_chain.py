import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "tools/qa/audit_corridor_road_source_chain.py"
spec = importlib.util.spec_from_file_location("corridor_source_chain", SCRIPT)
audit = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audit)


class TestCorridorRoadSourceChain(unittest.TestCase):
    def fixture(self, bad_sha=False):
        tempdir = tempfile.TemporaryDirectory()
        root = Path(tempdir.name)
        (root / "data/osm").mkdir(parents=True)
        (root / "data/runtime").mkdir(parents=True)
        rows = [
            ("midi", "Fonsny", "primary"),
            ("anneessens", "Lemonnier", "tertiary"),
            ("bourse", "Orts", "residential"),
            ("grand_place", "Amigo", "living_street"),
        ]
        roads = []
        representatives = []
        for road_id, (zone, name, road_class) in enumerate(rows, 1):
            roads.append({"osm_id": road_id, "name": name, "class": road_class, "drivable": True, "points": [[0, 0], [1, 1]]})
            representatives.append({"zone": zone, "osm_id": road_id, "name": name, "class": road_class})
        source = root / "data/osm/source.json"
        source.write_text(json.dumps({"roads": roads}, separators=(",", ":")), encoding="utf-8")
        digest = audit.sha256(source)
        index = {
            "format": "grand-bruxelles-road-runtime-index-v1",
            "source_lookup_only": True,
            "authorization": {"source_lookup_only": True, **{key: False for key in audit.PLAYABILITY_KEYS}},
            "documents": [{"path": "data/osm/source.json", "sha256": "0" * 64 if bad_sha else digest, "road_ids": [1, 2, 3, 4]}],
        }
        (root / "data/runtime/index.json").write_text(json.dumps(index), encoding="utf-8")
        contract = root / "contract.json"
        contract.write_text(json.dumps({
            "schema": "grand-bruxelles-corridor-road-source-chain-contract-v2",
            "production_base_sha": "fixture",
            "runtime_index": "data/runtime/index.json",
            "source_document": "data/osm/source.json",
            "source_sha256": digest,
            "representatives": representatives,
        }), encoding="utf-8")
        return tempdir, root, contract

    def refresh_source_sha(self, root):
        source_path = root / "data/osm/source.json"
        index_path = root / "data/runtime/index.json"
        index = json.loads(index_path.read_text(encoding="utf-8"))
        index["documents"][0]["sha256"] = audit.sha256(source_path)
        index_path.write_text(json.dumps(index), encoding="utf-8")

    def test_green_exact_source_chain(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        result = audit.validate(root, contract)
        self.assertFalse(result["playability_claimed"])
        self.assertTrue(result["source_sha_locked"])
        self.assertEqual(4, len(result["representatives"]))

    def test_red_on_source_sha_drift(self):
        tempdir, root, contract = self.fixture(bad_sha=True)
        self.addCleanup(tempdir.cleanup)
        with self.assertRaises(SystemExit):
            audit.validate(root, contract)

    def test_red_on_coordinated_source_and_index_drift(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        source_path = root / "data/osm/source.json"
        source = json.loads(source_path.read_text(encoding="utf-8"))
        source["roads"][0]["name"] = "Mutated Fonsny"
        source_path.write_text(json.dumps(source, separators=(",", ":")), encoding="utf-8")
        self.refresh_source_sha(root)
        with self.assertRaisesRegex(SystemExit, "locked source sha mismatch"):
            audit.validate(root, contract)

    def test_red_if_source_registry_self_authorizes_playability(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        index_path = root / "data/runtime/index.json"
        index = json.loads(index_path.read_text(encoding="utf-8"))
        index["authorization"]["safe_spawn_authorized"] = True
        index_path.write_text(json.dumps(index), encoding="utf-8")
        with self.assertRaises(SystemExit):
            audit.validate(root, contract)

    def test_red_on_degenerate_source_polyline(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        source_path = root / "data/osm/source.json"
        source = json.loads(source_path.read_text(encoding="utf-8"))
        source["roads"][0]["points"] = [[4.0, 7.0], [4.0, 7.0], [4.0, 7.0]]
        source_path.write_text(json.dumps(source, separators=(",", ":")), encoding="utf-8")
        self.refresh_source_sha(root)
        with self.assertRaisesRegex(SystemExit, "locked source sha mismatch"):
            audit.validate(root, contract)

    def test_red_on_duplicate_runtime_document_path(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        index_path = root / "data/runtime/index.json"
        index = json.loads(index_path.read_text(encoding="utf-8"))
        conflicting = dict(index["documents"][0])
        index["documents"].append(conflicting)
        index_path.write_text(json.dumps(index), encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "duplicate runtime source document paths"):
            audit.validate(root, contract)


if __name__ == "__main__":
    unittest.main()
