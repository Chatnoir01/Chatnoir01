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


def _bbox(feature: dict, path: Path) -> list[float]:
    bbox = feature.get("bbox")
    feature_id = feature.get("id", "<missing-id>")
    if not isinstance(bbox, list) or len(bbox) != 4:
        raise AssertionError(f"{path}: {feature_id} bbox must be a 4-number array")
    if not all(
        isinstance(value, (int, float))
        and not isinstance(value, bool)
        and math.isfinite(value)
        for value in bbox
    ):
        raise AssertionError(f"{path}: {feature_id} bbox must be finite numeric")
    if bbox[0] > bbox[2] or bbox[1] > bbox[3]:
        raise AssertionError(f"{path}: {feature_id} bbox must be ordered")
    return bbox


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

    def test_raw_and_game_bboxes_are_finite_ordered_and_identical_by_feature(self) -> None:
        for layer in LAYERS:
            with self.subTest(layer=layer):
                raw_path = MIDI / f"{layer}.geojson"
                game_path = MIDI / f"{layer}.game.json"
                raw = _load(raw_path)
                game = _load(game_path)
                raw_by_id = {feature["id"]: feature for feature in raw["features"]}
                game_by_id = {feature["id"]: feature for feature in game["features"]}

                self.assertEqual(set(raw_by_id), set(game_by_id))
                for feature_id in sorted(raw_by_id):
                    raw_bbox = _bbox(raw_by_id[feature_id], raw_path)
                    game_bbox = _bbox(game_by_id[feature_id], game_path)
                    self.assertEqual(
                        raw_bbox,
                        game_bbox,
                        f"{layer}: transformed feature {feature_id} changed source bbox accounting",
                    )


if __name__ == "__main__":
    unittest.main()
