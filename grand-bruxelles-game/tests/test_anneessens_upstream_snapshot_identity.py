import hashlib
import unittest
from pathlib import Path

ROOT = Path(__file__).parents[1]
RUNTIME = ROOT / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"
UPSTREAM = ROOT / "data" / "osm" / "vertical_slice_01.game.json"
EXPECTED_SHA256 = "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398"


def _source() -> str:
    return RUNTIME.read_text(encoding="utf-8")


def _function_body(source: str, signature: str) -> str:
    return source.split(signature, 1)[1].split("\nfunc ", 1)[0]


class AnneessensUpstreamSnapshotIdentityTest(unittest.TestCase):
    def test_pinned_upstream_bytes_match_canonical_digest(self) -> None:
        self.assertTrue(UPSTREAM.is_file(), "pinned OSM upstream snapshot is missing")
        digest = hashlib.sha256(UPSTREAM.read_bytes()).hexdigest()
        self.assertEqual(EXPECTED_SHA256, digest)

    def test_runtime_hashes_actual_upstream_snapshot_before_source_backed_root(self) -> None:
        source = _source()
        self.assertIn(
            "func _validate_upstream_snapshot_identity(path: String = UPSTREAM_PATH) -> Variant:",
            source,
        )
        validator = _function_body(
            source,
            "func _validate_upstream_snapshot_identity(path: String = UPSTREAM_PATH) -> Variant:",
        )
        self.assertIn("HashingContext.HASH_SHA256", validator)
        self.assertIn("EXPECTED_UPSTREAM_SHA256", validator)
        self.assertIn("FileAccess.open(path, FileAccess.READ)", validator)

        build = _function_body(source, "func _build_once() -> void:")
        self.assertIn("_validate_upstream_snapshot_identity()", build)
        self.assertLess(
            build.index("_validate_upstream_snapshot_identity()"),
            build.index("_root = Node3D.new()"),
        )
        self.assertIn("if upstream_snapshot_identity_value == null:", build)

    def test_source_backed_receipt_uses_measured_snapshot_digest(self) -> None:
        source = _source()
        build = _function_body(source, "func _build_once() -> void:")
        self.assertIn('upstream_snapshot_identity["sha256"]', build)
        self.assertIn('_root.set_meta("upstream_snapshot_identity_validated", true)', build)
        self.assertIn('_root.set_meta("upstream_source_sha256", str(upstream_snapshot_identity["sha256"]))', build)


if __name__ == "__main__":
    unittest.main()
