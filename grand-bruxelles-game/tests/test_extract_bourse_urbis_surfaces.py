#!/usr/bin/env python3
import importlib.util
import json
import math
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL_PATH = ROOT / "tools" / "extract_bourse_urbis_surfaces.py"
spec = importlib.util.spec_from_file_location("extract_bourse_urbis_surfaces", TOOL_PATH)
extractor = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(extractor)


def make_feature(inspire_id: str, type_code: str, offset: float) -> dict:
    east, north = extractor.BOURSE_CENTER
    ring = [
        [east + offset, north + offset],
        [east + offset + 5.0, north + offset],
        [east + offset + 5.0, north + offset + 4.0],
        [east + offset, north + offset],
    ]
    return {
        "type": "Feature",
        "geometry": {"type": "Polygon", "coordinates": [ring]},
        "properties": {
            "INSPIRE_ID": inspire_id,
            "TYPE": type_code,
            "AREA": 20,
            "LVL": 0,
            "STRNAMEFRE": "Place de la Bourse",
            "STRNAMEDUT": "Beursplein",
        },
    }


def main() -> int:
    transform = (147868.29422791934, 169538.62414926197, -668.5, 627.84)
    payload = {
        "type": "FeatureCollection",
        "features": [
            make_feature("https://databrussels.be/id/streetsurface/22358", "I", 0.0),
            make_feature("https://databrussels.be/id/streetsurface/151495", "SW", 10.0),
            make_feature("https://databrussels.be/id/streetsurface/152281", "SW", 20.0),
            make_feature("https://databrussels.be/id/streetsurface/not-target", "S", 30.0),
        ],
    }
    surfaces = extractor.extract_target_surfaces(payload, transform)
    assert len(surfaces) == 3
    assert {item["inspire_id"] for item in surfaces} == extractor.TARGET_IDS
    assert all(item["street_name_fr"] == "Place de la Bourse" for item in surfaces)
    assert all(item["street_name_nl"] == "Beursplein" for item in surfaces)
    assert all(item["source_rings_epsg31370"][0][0] == item["source_rings_epsg31370"][0][-1] for item in surfaces)
    assert all(item["world_rings_xz"][0][0] == item["world_rings_xz"][0][-1] for item in surfaces)

    world = extractor.to_world_xz(extractor.BOURSE_CENTER[0], extractor.BOURSE_CENTER[1], transform)
    expected_x = extractor.BOURSE_CENTER[0] - transform[0] + transform[2]
    expected_z = -(extractor.BOURSE_CENTER[1] - transform[1]) + transform[3]
    assert math.isclose(world[0], expected_x, abs_tol=1e-9)
    assert math.isclose(world[1], expected_z, abs_tol=1e-9)

    with tempfile.TemporaryDirectory() as tmp:
        evidence = Path(tmp) / "axis.json"
        evidence.write_text(json.dumps({
            "world_coordinate_evidence": {
                "lambert72_origin": [transform[0], transform[1]],
                "world_origin_xz": [transform[2], transform[3]],
            }
        }), encoding="utf-8")
        output = extractor.build_output(payload, "abc123", evidence)
        assert output["runtime_approved"] is False
        assert output["realism_complete"] is False
        assert output["next_runtime_step"].startswith("acquire adjacent official street surfaces")
        assert len(output["surfaces"]) == 3
        assert output["source"]["license"] == "CC0-1.0"
        assert output["source"]["request_bbox_epsg31370"] == list(extractor.probe_bbox())

    assert extractor.transform_source_label(extractor.AXIS_EVIDENCE) == "data/urbis/bourse_street_axes.game.json"

    missing_payload = {"type": "FeatureCollection", "features": payload["features"][:-2]}
    try:
        extractor.extract_target_surfaces(missing_payload, transform)
    except RuntimeError:
        pass
    else:
        raise AssertionError("missing target StreetSurface must be rejected")

    wrong_name = make_feature("https://databrussels.be/id/streetsurface/22358", "I", 0.0)
    wrong_name["properties"]["STRNAMEFRE"] = "Wrong"
    try:
        extractor.extract_target_surfaces({"type": "FeatureCollection", "features": [wrong_name]}, transform)
    except ValueError:
        pass
    else:
        raise AssertionError("wrong street identity must be rejected")

    print("BOURSE_URBIS_SURFACE_EXTRACT_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
