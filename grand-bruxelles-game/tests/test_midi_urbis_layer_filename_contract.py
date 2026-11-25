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
NON_PAIR_GAME_FILES = {"midi_runtime.game.json"}


class MidiUrbisLayerFilenameContract(unittest.TestCase):
    def test_locked_layer_pairs_are_complete_and_unambiguous(self) -> None:
        """Fail closed if the locked Midi source-pair inventory changes implicitly."""
        expected = {
            *(f"{layer}.geojson" for layer in LAYERS),
            *(f"{layer}.game.json" for layer in LAYERS),
        }

        # Inspect the complete source-shaped inventory rather than filtering by LAYERS.
        # Otherwise a newly added/renamed *.geojson or *.game.json would be excluded by
        # the very allow-list this test is supposed to protect and could escape review.
        present = {
            path.name
            for path in MIDI.iterdir()
            if path.is_file()
            and (
                path.name.endswith(".geojson")
                or (
                    path.name.endswith(".game.json")
                    and path.name not in NON_PAIR_GAME_FILES
                )
            )
        }
        self.assertEqual(
            present,
            expected,
            "Midi UrbIS source-pair inventory changed; account for every new/renamed pair explicitly",
        )

        for layer in LAYERS:
            for suffix in (".geojson", ".game.json"):
                path = MIDI / f"{layer}{suffix}"
                with self.subTest(layer=layer, suffix=suffix):
                    document = json.loads(path.read_text(encoding="utf-8"))
                    self.assertEqual(document.get("type"), "FeatureCollection")
                    self.assertIsInstance(document.get("features"), list)
                    self.assertTrue(document["features"])


if __name__ == "__main__":
    unittest.main()
