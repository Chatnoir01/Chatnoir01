#!/usr/bin/env python3
import importlib.util
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools" / "measure_bourse_runtime_gap.py"
spec = importlib.util.spec_from_file_location("measure_bourse_runtime_gap", TOOL)
measure = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(measure)


def main() -> int:
    assert math.isclose(measure.point_segment_distance((5.0, 3.0), (0.0, 0.0), (10.0, 0.0)), 3.0)
    assert math.isclose(measure.point_segment_distance((-2.0, 0.0), (0.0, 0.0), (10.0, 0.0)), 2.0)
    assert measure.percentile([0.0, 10.0, 20.0], 0.5) == 10.0

    transform = measure.load_world_transform()
    world = measure.lambert_to_world(measure.probe.BOURSE_CENTER, transform)
    # Existing OSM Bourse detail anchor is (81.54, -664.58); independent UrbIS transform must agree within a few metres.
    assert math.hypot(world[0] - 81.54, world[1] - (-664.58)) < 2.5, world

    sample_city = {
        "roads": [
            {"osm_id": 1, "name": "sample", "class": "tertiary", "width": 5.0, "points": [[0, 0], [10, 0]]}
        ]
    }
    segments = measure.runtime_road_segments(sample_city)
    assert len(segments) == 1
    assert measure.runtime_width(sample_city["roads"][0]) == 7.2
    assert math.isclose(measure.procedural_outer_half_width(sample_city["roads"][0]), 5.55)

    print("BOURSE_RUNTIME_GAP_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
