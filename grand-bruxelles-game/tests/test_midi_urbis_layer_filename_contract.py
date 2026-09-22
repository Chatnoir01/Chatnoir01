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


class MidiUrbisLayerFilenameContract(unittest.TestCase):
    def test_locked_layer_pairs_are_complete_and_unambiguous(self) -> None:
        """Fail closed if a locked Midi layer loses or gains an ambiguous pair member."""
        expected = {
            *(f"{layer}.geojson" for layer in LAYERS),
            *(f"{layer}.game.json" for layer in LAYERS),
        }
        present = {
            path.name
            for path in MIDI.iterdir()
            if path.is_file()
            and (path.name.endswith(".geojson") or path.name.endswith(".game.json"))
            and path.name.removesuffix(".geojson").removesuffix(".game.json") in LAYERS
        }
        self.assertEqual(
            present,
            expected,
            "locked Midi UrbIS layer pair filenames changed; update accounting explicitly",
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
