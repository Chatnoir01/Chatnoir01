import json
import math
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
    return document


def _feature_ids(document: dict, path: Path) -> list[str]:
    if document.get("type") != "FeatureCollection":
        raise AssertionError(f"{path}: expected FeatureCollection")
    features = document.get("features")
    if not isinstance(features, list) or not features:
        raise AssertionError(f"{path}: features must be a non-empty array")
    ids = []
    for feature in features:
        if not isinstance(feature, dict):
            raise AssertionError(f"{path}: every feature must be an object")
        feature_id = feature.get("id")
        if not isinstance(feature_id, str) or not feature_id:
            raise AssertionError(f"{path}: every feature must have a non-empty string id")
        if not isinstance(feature.get("geometry"), dict):
            raise AssertionError(f"{path}: feature {feature_id} has no geometry object")
        ids.append(feature_id)
    if len(ids) != len(set(ids)):
        raise AssertionError(f"{path}: duplicate feature ids")
    return ids


class MidiUrbisRawGamePairAccounting(unittest.TestCase):
    def test_raw_and_game_layers_have_exact_feature_identity_sets(self) -> None:
        for layer in LAYERS:
            with self.subTest(layer=layer):
                raw_path = MIDI / f"{layer}.geojson"
                game_path = MIDI / f"{layer}.game.json"
                self.assertTrue(raw_path.is_file(), raw_path)
                self.assertTrue(game_path.is_file(), game_path)

                raw = _load(raw_path)
                game = _load(game_path)
                raw_ids = _feature_ids(raw, raw_path)
                game_ids = _feature_ids(game, game_path)

                self.assertEqual(len(raw_ids), len(game_ids))
                self.assertEqual(set(raw_ids), set(game_ids))

    def test_raw_feature_bboxes_are_finite_and_ordered(self) -> None:
        for layer in LAYERS:
            raw_path = MIDI / f"{layer}.geojson"
            raw = _load(raw_path)
            for feature in raw["features"]:
                bbox = feature.get("bbox")
                self.assertIsInstance(bbox, list, f"{raw_path}: {feature['id']} bbox")
                self.assertEqual(len(bbox), 4, f"{raw_path}: {feature['id']} bbox")
                self.assertTrue(
                    all(isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value) for value in bbox),
                    f"{raw_path}: {feature['id']} bbox must be finite numeric",
                )
                self.assertLessEqual(bbox[0], bbox[2], f"{raw_path}: {feature['id']} bbox x order")
                self.assertLessEqual(bbox[1], bbox[3], f"{raw_path}: {feature['id']} bbox y order")


if __name__ == "__main__":
    unittest.main()
