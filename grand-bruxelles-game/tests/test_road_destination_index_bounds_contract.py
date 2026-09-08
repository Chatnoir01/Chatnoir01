import importlib.util
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/city_machine/build_road_destination_index.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("build_road_destination_index", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def test_checked_bounds_rejects_degenerate_source_extent():
    module = _load_module()
    for bounds in ([1.0, 2.0, 1.0, 4.0], [1.0, 2.0, 3.0, 2.0]):
        try:
            module._checked_bounds(bounds, "source bounds_m")
        except ValueError as exc:
            assert "degenerate" in str(exc)
        else:
            raise AssertionError("source bounds must have positive extent on both axes")
