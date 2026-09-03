import unittest
from pathlib import Path

RUNTIME = Path(__file__).parents[1] / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"


def _source() -> str:
    return RUNTIME.read_text(encoding="utf-8")


def _function_body(source: str, signature: str) -> str:
    return source.split(signature, 1)[1].split("\nfunc ", 1)[0]


class AnneessensOsmFurnitureSourceGuardTest(unittest.TestCase):
    def test_tree_points_are_validated_before_runtime_root_is_created(self) -> None:
        source = _source()
        build = _function_body(source, "func _build_once() -> void:")
        self.assertIn("_collect_validated_tree_points", build)
        self.assertLess(build.index("_collect_validated_tree_points"), build.index("_root = Node3D.new()"))

    def test_validation_result_can_fail_closed_with_null(self) -> None:
        source = _source()
        self.assertIn("func _collect_validated_tree_points(data: Dictionary) -> Variant:", source)
        build = _function_body(source, "func _build_once() -> void:")
        self.assertIn("var validated_tree_points: Variant = _collect_validated_tree_points(data)", build)
        self.assertIn("if validated_tree_points == null:", build)
        self.assertIn("var tree_points := validated_tree_points as Array", build)

    def test_json_numeric_osm_identity_is_positive_integral_exact_and_unique(self) -> None:
        source = _source()
        parser = _function_body(source, "func _collect_validated_tree_points(data: Dictionary) -> Variant:")
        self.assertIn("typeof(osm_id_value) not in [TYPE_FLOAT, TYPE_INT]", parser)
        self.assertIn("is_finite(osm_id_number)", parser)
        self.assertIn("osm_id_number <= 0.0", parser)
        self.assertIn("osm_id_number > MAX_EXACT_JSON_INTEGER", parser)
        self.assertIn("floor(osm_id_number) != osm_id_number", parser)
        self.assertIn("seen_osm_ids.has(osm_id)", parser)
        self.assertIn("seen_osm_ids[osm_id] = true", parser)

    def test_tree_coordinates_are_numeric_and_finite_before_materialization(self) -> None:
        source = _source()
        parser = _function_body(source, "func _collect_validated_tree_points(data: Dictionary) -> Variant:")
        self.assertIn("TYPE_FLOAT", parser)
        self.assertIn("TYPE_INT", parser)
        self.assertIn("is_finite(x)", parser)
        self.assertIn("is_finite(z)", parser)

    def test_invalid_tree_source_aborts_instead_of_materializing_partial_furniture(self) -> None:
        source = _source()
        build = _function_body(source, "func _build_once() -> void:")
        self.assertIn("if validated_tree_points == null:", build)
        self.assertIn("return", build.split("if validated_tree_points == null:", 1)[1].split("_root = Node3D.new()", 1)[0])
        self.assertNotIn("_add_tree(int(point.get(\"osm_id\", 0))", build)


if __name__ == "__main__":
    unittest.main()
