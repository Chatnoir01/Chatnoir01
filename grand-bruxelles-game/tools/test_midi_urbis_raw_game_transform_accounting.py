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

# Locked project Lambert72 -> game bridge already established by the Midi
# source/provenance receipts. This test does not infer or refit an origin from
# the transformed payload it is validating.
ORIGIN_EASTING_M = 147868.29422791934
ORIGIN_NORTHING_M = 169538.62414926197
ABS_TOL_M = 1e-9


def _load(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        document = json.load(handle)
    if not isinstance(document, dict) or document.get("type") != "FeatureCollection":
        raise AssertionError(f"{path}: expected FeatureCollection")
    features = document.get("features")
    if not isinstance(features, list) or not features:
        raise AssertionError(f"{path}: expected non-empty features")
    return document


def _by_id(document: dict, path: Path) -> dict[str, dict]:
    result = {}
    for feature in document["features"]:
        if not isinstance(feature, dict):
            raise AssertionError(f"{path}: feature must be an object")
        feature_id = feature.get("id")
        if not isinstance(feature_id, str) or not feature_id:
            raise AssertionError(f"{path}: feature id must be a non-empty string")
        if feature_id in result:
            raise AssertionError(f"{path}: duplicate feature id {feature_id}")
        result[feature_id] = feature
    return result


def _assert_transformed_coordinates(
    case: unittest.TestCase,
    raw,
    game,
    *,
    layer: str,
    feature_id: str,
    path: str = "coordinates",
) -> None:
    if not isinstance(raw, list) or not isinstance(game, list):
        case.fail(f"{layer}: {feature_id} {path} must be arrays")
    case.assertEqual(len(raw), len(game), f"{layer}: {feature_id} {path} arity changed")

    raw_is_position = all(
        isinstance(value, (int, float)) and not isinstance(value, bool) for value in raw
    )
    game_is_position = all(
        isinstance(value, (int, float)) and not isinstance(value, bool) for value in game
    )
    case.assertEqual(raw_is_position, game_is_position, f"{layer}: {feature_id} {path} topology changed")

    if raw_is_position:
        case.assertGreaterEqual(len(raw), 2, f"{layer}: {feature_id} {path} position arity")
        case.assertTrue(all(math.isfinite(value) for value in raw), f"{layer}: {feature_id} raw non-finite")
        case.assertTrue(all(math.isfinite(value) for value in game), f"{layer}: {feature_id} game non-finite")
        expected_x = raw[0] - ORIGIN_EASTING_M
        expected_y = ORIGIN_NORTHING_M - raw[1]
        case.assertTrue(
            math.isclose(game[0], expected_x, rel_tol=0.0, abs_tol=ABS_TOL_M),
            f"{layer}: {feature_id} {path}[0] violates locked Lambert72->game X bridge",
        )
        case.assertTrue(
            math.isclose(game[1], expected_y, rel_tol=0.0, abs_tol=ABS_TOL_M),
            f"{layer}: {feature_id} {path}[1] violates locked Lambert72->game Y bridge",
        )
        case.assertEqual(
            raw[2:],
            game[2:],
            f"{layer}: {feature_id} {path} non-XY ordinates changed during XY bridge",
        )
        return

    case.assertTrue(raw, f"{layer}: {feature_id} {path} must not be empty")
    for index, (raw_child, game_child) in enumerate(zip(raw, game)):
        _assert_transformed_coordinates(
            case,
            raw_child,
            game_child,
            layer=layer,
            feature_id=feature_id,
            path=f"{path}[{index}]",
        )


class MidiUrbisRawGameTransformAccounting(unittest.TestCase):
    def test_game_coordinates_follow_locked_lambert72_bridge(self) -> None:
        for layer in LAYERS:
            raw_path = MIDI / f"{layer}.geojson"
            game_path = MIDI / f"{layer}.game.json"
            with self.subTest(layer=layer):
                raw_by_id = _by_id(_load(raw_path), raw_path)
                game_by_id = _by_id(_load(game_path), game_path)
                self.assertEqual(set(raw_by_id), set(game_by_id))
                for feature_id in sorted(raw_by_id):
                    raw_geometry = raw_by_id[feature_id].get("geometry")
                    game_geometry = game_by_id[feature_id].get("geometry")
                    self.assertIsInstance(raw_geometry, dict, f"{layer}: {feature_id} raw geometry")
                    self.assertIsInstance(game_geometry, dict, f"{layer}: {feature_id} game geometry")
                    self.assertEqual(raw_geometry.get("type"), game_geometry.get("type"))
                    _assert_transformed_coordinates(
                        self,
                        raw_geometry.get("coordinates"),
                        game_geometry.get("coordinates"),
                        layer=layer,
                        feature_id=feature_id,
                    )

    def test_non_geometry_feature_semantics_are_preserved_exactly(self) -> None:
        for layer in LAYERS:
            raw_path = MIDI / f"{layer}.geojson"
            game_path = MIDI / f"{layer}.game.json"
            with self.subTest(layer=layer):
                raw_by_id = _by_id(_load(raw_path), raw_path)
                game_by_id = _by_id(_load(game_path), game_path)
                self.assertEqual(set(raw_by_id), set(game_by_id))
                for feature_id in sorted(raw_by_id):
                    raw_feature = raw_by_id[feature_id]
                    game_feature = game_by_id[feature_id]
                    self.assertEqual(raw_feature.get("type"), "Feature")
                    self.assertEqual(game_feature.get("type"), "Feature")
                    self.assertEqual(
                        raw_feature.get("geometry_name"),
                        game_feature.get("geometry_name"),
                        f"{layer}: {feature_id} geometry_name changed during conversion",
                    )
                    self.assertEqual(
                        raw_feature.get("properties"),
                        game_feature.get("properties"),
                        f"{layer}: {feature_id} properties changed during coordinate conversion",
                    )
                    self.assertEqual(
                        raw_feature.get("bbox"),
                        game_feature.get("bbox"),
                        f"{layer}: {feature_id} source bbox accounting changed during conversion",
                    )


if __name__ == "__main__":
    unittest.main()
