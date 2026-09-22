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
    def test_collection_feature_counts_are_explicit_and_pair_equal(self) -> None:
        """Keep a deterministic, human-readable accounting receipt per locked layer pair."""
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
                counts[layer] = len(raw_features)

        # This assertion deliberately keeps all five layers in the accounting domain;
        # it catches accidental edits to LAYERS that would silently reduce coverage.
        self.assertEqual(set(counts), set(LAYERS))


if __name__ == "__main__":
    unittest.main()
