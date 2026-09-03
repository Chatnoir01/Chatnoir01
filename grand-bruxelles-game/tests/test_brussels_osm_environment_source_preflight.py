import unittest
from pathlib import Path

RUNTIME = Path(__file__).parents[1] / "game" / "scripts" / "brussels_osm_environment_runtime.gd"


def _source() -> str:
    return RUNTIME.read_text(encoding="utf-8")


def _function_body(source: str, signature: str) -> str:
    return source.split(signature, 1)[1].split("\nfunc ", 1)[0]


class BrusselsOsmEnvironmentSourcePreflightTest(unittest.TestCase):
    def test_document_rows_are_preflighted_before_points_mutate(self) -> None:
        source = _source()
        load = _function_body(source, "func _load_points() -> bool:")
        self.assertIn("_collect_validated_points", load)
        self.assertLess(load.index("_collect_validated_points"), load.index("_points = validated_points"))

    def test_preflight_is_fail_closed(self) -> None:
        source = _source()
        self.assertIn("func _collect_validated_points(document: Dictionary) -> Variant:", source)
        load = _function_body(source, "func _load_points() -> bool:")
        self.assertIn("var validated_points: Variant = _collect_validated_points(document)", load)
        self.assertIn("if validated_points == null:", load)
        self.assertIn("return false", load.split("if validated_points == null:", 1)[1])

    def test_osm_identity_is_positive_integral_exact_and_unique(self) -> None:
        source = _source()
        parser = _function_body(source, "func _collect_validated_points(document: Dictionary) -> Variant:")
        self.assertIn("typeof(osm_id_value) not in [TYPE_FLOAT, TYPE_INT]", parser)
        self.assertIn("is_finite(osm_id_number)", parser)
        self.assertIn("osm_id_number <= 0.0", parser)
        self.assertIn("osm_id_number > MAX_EXACT_JSON_INTEGER", parser)
        self.assertIn("floor(osm_id_number) != osm_id_number", parser)
        self.assertIn("seen_osm_ids.has(osm_id)", parser)
        self.assertIn("seen_osm_ids[osm_id] = true", parser)

    def test_positions_are_numeric_and_finite(self) -> None:
        source = _source()
        parser = _function_body(source, "func _collect_validated_points(document: Dictionary) -> Variant:")
        self.assertIn("position.size() != 2", parser)
        self.assertIn("typeof(x_value) not in [TYPE_FLOAT, TYPE_INT]", parser)
        self.assertIn("typeof(z_value) not in [TYPE_FLOAT, TYPE_INT]", parser)
        self.assertIn("is_finite(x)", parser)
        self.assertIn("is_finite(z)", parser)

    def test_malformed_rows_cannot_be_skipped_into_partial_rendering(self) -> None:
        source = _source()
        parser = _function_body(source, "func _collect_validated_points(document: Dictionary) -> Variant:")
        self.assertIn("if not row_variant is Dictionary:", parser)
        malformed = parser.split("if not row_variant is Dictionary:", 1)[1].split("var row :=", 1)[0]
        self.assertIn("return null", malformed)
        self.assertNotIn("continue", malformed)


if __name__ == "__main__":
    unittest.main()
