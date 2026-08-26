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
        (root / "data/qa").mkdir(parents=True)
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
        witness = {
            "schema": "grand-bruxelles-automatic-road-player-visual-gate-v1",
            "evidence": {"resolution": [1280, 720], "witness_road_osm_id": 2},
            "source_contract": {
                "lookup_mode": "deterministic_runtime_index",
                "source_path": "res://data/osm/source.json",
                "source_sha256": digest,
                "ground_collision_proven": True,
                "source_sightline_clear": True,
                "road_axis_alignment": 0.97,
            },
            "human_review": {
                "status": "keep",
                "full_frame_inspected": True,
                "road_identity_matches_frame": True,
                "blocking_reasons": [],
            },
            "authorization": {
                "qa_witness_accepted": True,
                "playability_claimed": False,
                "destination_advertisable": False,
                "jouable_authorized": False,
            },
        }
        (root / "data/qa/player_witness.json").write_text(json.dumps(witness), encoding="utf-8")
        contract = root / "contract.json"
        contract.write_text(json.dumps({
            "schema": audit.CONTRACT_SCHEMA,
            "integration_floor_sha": "1" * 40,
            "runtime_index": "data/runtime/index.json",
            "source_document": "data/osm/source.json",
            "source_sha256": digest,
            "accepted_player_witness": {
                "path": "data/qa/player_witness.json",
                "zone": "anneessens",
                "osm_id": 2,
                "required_resolution": [1280, 720],
            },
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
        self.assertEqual("1" * 40, result["integration_floor_sha"])
        self.assertEqual(audit.EXPECTED_ZONES, {item["zone"] for item in result["representatives"]})
        self.assertEqual(4, len(result["representatives"]))
        self.assertEqual(2, result["accepted_player_witness"]["osm_id"])
        self.assertTrue(result["accepted_player_witness"]["qa_witness_accepted"])
        self.assertFalse(result["accepted_player_witness"]["destination_advertisable"])

    def test_red_if_legacy_production_base_returns(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        payload = json.loads(contract.read_text(encoding="utf-8"))
        payload["production_base_sha"] = "2" * 40
        contract.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "legacy production_base_sha is forbidden"):
            audit.validate(root, contract)

    def test_red_if_integration_floor_is_not_exact_git_sha(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        payload = json.loads(contract.read_text(encoding="utf-8"))
        payload["integration_floor_sha"] = "fixture"
        contract.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "integration_floor_sha"):
            audit.validate(root, contract)

    def test_red_if_witness_advertises_destination(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        path = root / "data/qa/player_witness.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["authorization"]["destination_advertisable"] = True
        path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "accepted player witness must remain QA-only"):
            audit.validate(root, contract)

    def test_red_if_witness_road_identity_drifts(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        path = root / "data/qa/player_witness.json"
        payload = json.loads(path.read_text(encoding="utf-8"))
        payload["evidence"]["witness_road_osm_id"] = 3
        path.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "accepted player witness road mismatch"):
            audit.validate(root, contract)

    def test_red_on_duplicate_corridor_zone(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        payload = json.loads(contract.read_text(encoding="utf-8"))
        payload["representatives"][-1]["zone"] = "midi"
        contract.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "duplicate representative zone midi"):
            audit.validate(root, contract)

    def test_red_on_unexpected_corridor_zone(self):
        tempdir, root, contract = self.fixture()
        self.addCleanup(tempdir.cleanup)
        payload = json.loads(contract.read_text(encoding="utf-8"))
        payload["representatives"][-1]["zone"] = "elsewhere"
        contract.write_text(json.dumps(payload), encoding="utf-8")
        with self.assertRaisesRegex(SystemExit, "corridor zone coverage mismatch"):
            audit.validate(root, contract)

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
