from pathlib import Path

RUNTIME = Path(__file__).parents[1] / "game" / "scripts" / "anneessens_osm_furniture_runtime.gd"


def _source() -> str:
    return RUNTIME.read_text(encoding="utf-8")


def _function_body(source: str, signature: str) -> str:
    return source.split(signature, 1)[1].split("\nfunc ", 1)[0]


def test_tree_points_are_validated_before_runtime_root_is_created() -> None:
    source = _source()
    build = _function_body(source, "func _build_once() -> void:")
    assert "_collect_validated_tree_points" in build
    assert build.index("_collect_validated_tree_points") < build.index("_root = Node3D.new()")


def test_tree_osm_identity_is_strict_positive_unique_integer() -> None:
    source = _source()
    parser = _function_body(source, "func _collect_validated_tree_points(data: Dictionary) -> Array:")
    assert "typeof(osm_id_value) != TYPE_INT" in parser
    assert "osm_id <= 0" in parser
    assert "seen_osm_ids.has(osm_id)" in parser
    assert "seen_osm_ids[osm_id] = true" in parser


def test_tree_coordinates_are_numeric_and_finite_before_materialization() -> None:
    source = _source()
    parser = _function_body(source, "func _collect_validated_tree_points(data: Dictionary) -> Array:")
    assert "TYPE_FLOAT" in parser
    assert "TYPE_INT" in parser
    assert "is_finite(x)" in parser
    assert "is_finite(z)" in parser


def test_invalid_tree_source_aborts_instead_of_materializing_partial_furniture() -> None:
    source = _source()
    build = _function_body(source, "func _build_once() -> void:")
    assert "if validated_tree_points == null:" in build
    assert "return" in build.split("if validated_tree_points == null:", 1)[1].split("_root = Node3D.new()", 1)[0]
    assert "_add_tree(int(point.get(\"osm_id\", 0))" not in build
