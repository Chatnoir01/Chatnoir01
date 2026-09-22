import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
MIDI = ROOT / "data" / "urbis" / "midi"
LAYERS = (
    "buildings",
    "street_axes",
    "street_surfaces",
    "train_network",
    "tram_network",
)


class MidiUrbisCollectionFeatureCountAccounting(unittest.TestCase):
    def test_collection_feature_counts_and_order_are_pair_equal(self) -> None:
        """Keep deterministic accounting and source feature order across raw/game pairs."""
        counts = {}
        for layer in LAYERS:
            raw_path = MIDI / f"{layer}.geojson"
            game_path = MIDI / f"{layer}.game.json"
            with self.subTest(layer=layer):
                raw = json.loads(raw_path.read_text(encoding="utf-8"))
                game = json.loads(game_path.read_text(encoding="utf-8"))
                raw_features = raw.get("features")
                game_features = game.get("features")
                self.assertIsInstance(raw_features, list)
                self.assertIsInstance(game_features, list)
                self.assertGreater(len(raw_features), 0)
                self.assertEqual(
                    len(raw_features),
                    len(game_features),
                    f"{layer}: raw/game feature-count accounting diverged",
                )

                # Identity-set checks elsewhere reject additions/deletions. Preserve the
                # source ordering too: a coordinate-only transform must not reorder the
                # locked source features, because that would make generated artifacts
                # non-reproducible even when their identity sets remain equal.
                raw_ids = [feature.get("id") for feature in raw_features]
                game_ids = [feature.get("id") for feature in game_features]
                self.assertEqual(
                    raw_ids,
                    game_ids,
                    f"{layer}: coordinate conversion reordered source features",
                )
                counts[layer] = len(raw_features)

        # This assertion deliberately keeps all five layers in the accounting domain;
        # it catches accidental edits to LAYERS that would silently reduce coverage.
        self.assertEqual(set(counts), set(LAYERS))


if __name__ == "__main__":
    unittest.main()
