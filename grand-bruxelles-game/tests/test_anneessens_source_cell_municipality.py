#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path

from shapely.geometry import box, mapping

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/qa/measure_anneessens_source_cell_municipality.py"


def load_module():
    spec = importlib.util.spec_from_file_location("anneessens_municipality", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("cannot import Anneessens municipality preflight")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def municipality_feature(stable_id: str, nis: str, geom):
    return {
        "type": "Feature",
        "id": f"transport-{stable_id}",
        "properties": {"INSPIRE_ID": stable_id, "NISCODE": nis, "NAME_FRE": stable_id},
        "geometry": mapping(geom),
    }


def main() -> int:
    module = load_module()
    measurement_path = ROOT / "data/provenance/anneessens_urbis_source_cell.measurement.json"
    measurement = json.loads(measurement_path.read_text(encoding="utf-8"))
    module.validate_measurement(measurement)
    module.validate_persisted_source(ROOT)

    bad = copy.deepcopy(measurement)
    bad["source_semantic_sha256"] = "0" * 64
    try:
        module.validate_measurement(bad)
    except RuntimeError:
        pass
    else:
        raise AssertionError("semantic source drift must fail closed")

    bad = copy.deepcopy(measurement)
    bad["registration_authorized"] = True
    try:
        module.validate_measurement(bad)
    except RuntimeError:
        pass
    else:
        raise AssertionError("registration rail opening must fail closed")

    engine = module._load_module(ROOT / "tools/qa/measure_road_cell_municipality_preflight.py")
    min_x, min_y, max_x, max_y = module.BBOX
    full = {
        "type": "FeatureCollection",
        "features": [municipality_feature("single", "99999", box(min_x - 10, min_y - 10, max_x + 10, max_y + 10))],
    }
    single = engine.analyze_municipality_coverage(module.BBOX, full)
    assert single["status"] == "MUNICIPALITY_PROVEN_SINGLE"
    assert single["municipality_niscode"] == "99999"
    assert abs(single["intersection_coverage_sum"] - 1.0) <= 1e-9
    assert single["registration_authorized"] is False

    mid_x = (min_x + max_x) / 2.0
    boundary = {
        "type": "FeatureCollection",
        "features": [
            municipality_feature("west", "11111", box(min_x, min_y, mid_x, max_y)),
            municipality_feature("east", "22222", box(mid_x, min_y, max_x, max_y)),
        ],
    }
    split = engine.analyze_municipality_coverage(module.BBOX, boundary)
    assert split["status"] == "HOLD_MUNICIPALITY_BOUNDARY_CELL"
    assert split["municipality_id"] is None
    assert len(split["intersections"]) == 2
    assert abs(split["intersection_coverage_sum"] - 1.0) <= 1e-9
    assert split["road_cell_mapping_authorized"] is False
    assert split["jouable_promotion_authorized"] is False

    # A dominant municipality must not become an inferred assignment. This
    # mirrors the real Anneessens measurement, where Saint-Gilles covers
    # roughly 64.6% while Anderlecht and Bruxelles still intersect the cell.
    dominant_x = min_x + (max_x - min_x) * 0.65
    majority_boundary = {
        "type": "FeatureCollection",
        "features": [
            municipality_feature("majority", "33333", box(min_x, min_y, dominant_x, max_y)),
            municipality_feature("minority", "44444", box(dominant_x, min_y, max_x, max_y)),
        ],
    }
    majority = engine.analyze_municipality_coverage(module.BBOX, majority_boundary)
    assert majority["status"] == "HOLD_MUNICIPALITY_BOUNDARY_CELL"
    assert majority["municipality_id"] is None
    assert majority["municipality_niscode"] is None
    assert majority["coverage_ratio"] > 0.6
    assert len(majority["intersections"]) == 2
    assert majority["registration_authorized"] is False
    assert majority["road_cell_mapping_authorized"] is False
    assert majority["runtime_mount_authorized"] is False
    assert majority["rendered_geometry_authorized"] is False
    assert majority["collision_authorized"] is False
    assert majority["safe_spawn_authorized"] is False
    assert majority["jouable_promotion_authorized"] is False

    print("ANNEESSENS_MUNICIPALITY_REGRESSIONS_OK source_lock=true single=true boundary_hold=true majority_inference_rejected=true rails_closed=true")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
