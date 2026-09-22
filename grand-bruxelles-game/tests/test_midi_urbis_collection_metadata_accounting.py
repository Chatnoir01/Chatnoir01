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


def _load(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        document = json.load(handle)
    if not isinstance(document, dict):
        raise AssertionError(f"{path}: top level must be an object")
    if document.get("type") != "FeatureCollection":
        raise AssertionError(f"{path}: expected FeatureCollection")
    if not isinstance(document.get("features"), list) or not document["features"]:
        raise AssertionError(f"{path}: expected non-empty features")
    return document


class MidiUrbisCollectionMetadataAccounting(unittest.TestCase):
    def test_raw_and_game_collection_metadata_is_preserved_exactly(self) -> None:
        for layer in LAYERS:
            raw_path = MIDI / f"{layer}.geojson"
            game_path = MIDI / f"{layer}.game.json"
            with self.subTest(layer=layer):
                raw = _load(raw_path)
                game = _load(game_path)

                # Coordinate conversion is authorized only inside each feature's
                # geometry. Collection-level source metadata (current or future
                # CRS/name/bbox/provenance fields) must not be dropped, added,
                # or rewritten by the raw -> game conversion.
                raw_metadata = {key: value for key, value in raw.items() if key != "features"}
                game_metadata = {key: value for key, value in game.items() if key != "features"}
                self.assertEqual(
                    raw_metadata,
                    game_metadata,
                    f"{layer}: collection metadata changed during coordinate conversion",
                )


if __name__ == "__main__":
    unittest.main()
