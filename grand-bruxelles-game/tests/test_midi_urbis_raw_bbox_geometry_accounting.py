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


def _positions(value, path: Path, feature_id: str):
    if not isinstance(value, list) or not value:
        raise AssertionError(f"{path}: {feature_id} coordinates must be non-empty arrays")
    if all(isinstance(item, (int, float)) and not isinstance(item, bool) for item in value):
        if len(value) < 2 or not all(math.isfinite(item) for item in value):
            raise AssertionError(f"{path}: {feature_id} position must have >=2 finite numbers")
        yield value
        return
    if any(isinstance(item, (int, float, bool)) for item in value):
        raise AssertionError(f"{path}: {feature_id} coordinates mix positions and nested arrays")
    for child in value:
        yield from _positions(child, path, feature_id)


def _bbox_from_geometry(feature: dict, path: Path) -> list[float]:
    feature_id = feature.get("id", "<missing-id>")
    geometry = feature.get("geometry")
    if not isinstance(geometry, dict):
        raise AssertionError(f"{path}: {feature_id} has no geometry object")
    positions = list(_positions(geometry.get("coordinates"), path, feature_id))
    xs = [position[0] for position in positions]
    ys = [position[1] for position in positions]
    return [min(xs), min(ys), max(xs), max(ys)]


class MidiUrbisRawBboxGeometryAccounting(unittest.TestCase):
    def test_raw_feature_bbox_is_exact_geometry_extrema(self) -> None:
        for layer in LAYERS:
            path = MIDI / f"{layer}.geojson"
            with self.subTest(layer=layer):
                with path.open("r", encoding="utf-8") as handle:
                    document = json.load(handle)
                self.assertEqual(document.get("type"), "FeatureCollection")
                features = document.get("features")
                self.assertIsInstance(features, list)
                self.assertTrue(features)
                for feature in features:
                    feature_id = feature.get("id", "<missing-id>")
                    bbox = feature.get("bbox")
                    self.assertIsInstance(bbox, list, f"{layer}: {feature_id} bbox missing")
                    self.assertEqual(len(bbox), 4, f"{layer}: {feature_id} bbox arity")
                    self.assertTrue(
                        all(
                            isinstance(value, (int, float))
                            and not isinstance(value, bool)
                            and math.isfinite(value)
                            for value in bbox
                        ),
                        f"{layer}: {feature_id} bbox must contain finite JSON numbers",
                    )
                    self.assertEqual(
                        bbox,
                        _bbox_from_geometry(feature, path),
                        f"{layer}: {feature_id} bbox is not the exact raw geometry envelope",
                    )


if __name__ == "__main__":
    unittest.main()
