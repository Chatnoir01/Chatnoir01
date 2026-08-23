import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools/source_factory/measure_brussels_sidewalk_horizontal_overlap.py"
MEASUREMENT_PATH = ROOT / "data/provenance/brussels_sidewalk_horizontal_overlap_measurement.json"


def _load_tool():
    spec = importlib.util.spec_from_file_location("sidewalk_overlap_measure", TOOL_PATH)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_official_generic_sidewalk_horizontal_overlap_is_measured_and_fail_closed():
    tool = _load_tool()
    measured = tool.measure()
    assert measured["inputs"]["generic_sidewalk_count"] == 430
    assert measured["inputs"]["official_feature_count"] == 3158
    assert measured["horizontal_only"] is True
    assert measured["algorithm"]["target_sample_spacing_m"] == 0.25
    assert measured["algorithm"]["area_is_estimate"] is True
    for key in (
        "curb_height_authorized",
        "vertical_profile_authorized",
        "runtime_geometry_authorized",
        "runtime_replacement_authorized",
        "jouable_promotion_authorized",
        "measurement_alone_authorizes_runtime",
    ):
        assert measured["policy"][key] is False

    assert MEASUREMENT_PATH.exists(), "persisted sidewalk horizontal-overlap measurement lock missing"
    persisted = json.loads(MEASUREMENT_PATH.read_text(encoding="utf-8"))
    assert persisted == measured, "persisted sidewalk overlap measurement drifted from exact current inputs"


if __name__ == "__main__":
    test_official_generic_sidewalk_horizontal_overlap_is_measured_and_fail_closed()
    print("OFFICIAL_SIDEWALK_HORIZONTAL_OVERLAP_OK")
