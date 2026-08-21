#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import math
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("runtime_candidate", HERE / "build_runtime_candidate_bundle.py")
mod = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(mod)

CELL_ID = "bxl-e149000-n169000-s500"
BBOX = [149000.0, 169000.0, 149500.0, 169500.0]
LAYERS = {
    "buildings": ("urbisvector:Buildings", "raw/buildings.geojson"),
    "street_surfaces": ("urbisvector:StreetSurfaces", "raw/street_surfaces.geojson"),
    "street_axes": ("urbisvector:StreetAxes", "raw/street_axes.geojson"),
    "tram_network": ("urbisvector:TramNetwork", "raw/tram_network.geojson"),
    "train_network": ("urbisvector:TrainNetwork", "raw/train_network.geojson"),
}


def feature(fid, geometry, **props):
    return {
        "type": "Feature",
        "properties": {"INSPIRE_ID": fid, **props},
        "geometry": geometry,
    }


def polygon(points):
    return {"type": "Polygon", "coordinates": [[*points, points[0]]]}


def line(points):
    return {"type": "LineString", "coordinates": points}


def collection(layer_name, features):
    return {
        "type": "FeatureCollection",
        "features": features,
        "numberReturned": len(features),
        "grand_bruxelles_source": {
            "authority": "Paradigm / Brussels-Capital Region",
            "service": "https://geoservices-urbis.irisnet.be/geoserver/urbisvector/wfs",
            "layer": layer_name,
            "crs": "EPSG:31370",
            "bbox": BBOX,
            "cell_id": CELL_ID,
            "ownership": "fixture",
        },
    }


def write_source(root: Path) -> Path:
    cell = root / CELL_ID
    docs = {
        "buildings": collection(
            LAYERS["buildings"][0],
            [
                feature(
                    "building-1",
                    polygon([[149020,169020],[149060,169020],[149060,169060],[149020,169060]]),
                    AREA=1600,
                )
            ],
        ),
        "street_surfaces": collection(
            LAYERS["street_surfaces"][0],
            [
                feature(
                    "surface-crossing-west",
                    polygon([[148950,169080],[149080,169080],[149080,169120],[148950,169120]]),
                    AREA=5200,
                    TYPE="S",
                    LVL=0,
                    STRNAMEFRE="Rue Test",
                    STRNAMEDUT="Teststraat",
                )
            ],
        ),
        "street_axes": collection(
            LAYERS["street_axes"][0],
            [feature("street-crossing-west", line([[148900,169100],[149100,169100]]), TYPE="S")],
        ),
        "tram_network": collection(
            LAYERS["tram_network"][0],
            [feature("rail-tw", line([[149050,169150],[149450,169150]]), TYPE="TW")],
        ),
        "train_network": collection(
            LAYERS["train_network"][0],
            [
                # Deliberate duplicate TW geometry must dedupe across public rail layers.
                feature("rail-tw-duplicate", line([[149050,169150],[149450,169150]]), TYPE="TW"),
                feature("rail-rw", line([[149050,169180],[149450,169180]]), TYPE="RW"),
            ],
        ),
    }
    manifest_layers = {}
    for logical_name, (wfs_name, relative) in LAYERS.items():
        path = cell / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(docs[logical_name], separators=(",", ":")) + "\n", encoding="utf-8")
        manifest_layers[logical_name] = {
            "wfs_name": wfs_name,
            "features": len(docs[logical_name]["features"]),
            "file": relative,
        }
    manifest = {
        "format": "grand-bruxelles-urbis-source-cell-v1",
        "cell_id": CELL_ID,
        "crs": "EPSG:31370",
        "bbox": BBOX,
        "layers": manifest_layers,
        "promotion": "source_only_no_runtime_mutation",
    }
    (cell / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return cell


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    cell_dir = write_source(root)
    out_a = root / "candidate-a"
    out_b = root / "candidate-b"

    first = mod.build(cell_dir, out_a)
    second = mod.build(cell_dir, out_b)

    assert first["format"] == "grand-bruxelles-runtime-candidate-bundle-v1"
    assert first["candidate_digest"] == second["candidate_digest"]
    assert first["output_sha256"] == second["output_sha256"]
    assert first["safety"]["official_plan_geometry_only"] is True
    assert first["safety"]["building_height_invented"] is False
    assert first["safety"]["collision_generated"] is False
    assert first["safety"]["runtime_mount_authorized"] is False
    assert first["safety"]["jouable_promotion_authorized"] is False

    manifest = json.loads((out_a / "manifest.json").read_text())
    runtime = json.loads((out_a / "runtime" / "cell.game.json").read_text())
    network = json.loads((out_a / "runtime" / "network.game.json").read_text())

    assert manifest["format"] == "grand-bruxelles-urbis-built-cell-v1"
    assert manifest["authorization"]["candidate_only"] is True
    assert manifest["authorization"]["runtime_mount_authorized"] is False
    assert runtime["format"] == "grand-bruxelles-urbis-cell-runtime-v1"
    assert network["format"] == "grand-bruxelles-urbis-network-cell-runtime-v2"

    assert len(runtime["buildings"]) == 1
    building = runtime["buildings"][0]
    assert "height" not in building
    assert building["height_source"] == "absent_pending_validated_height_contract"
    assert building["visual_height_available"] is False

    # Locked Lambert72 -> current game world transform.
    origin_world = mod._world_point(149000.0, 169000.0)
    assert origin_world == [463.206, 1166.464], origin_world
    first_building_point = building["footprint"][0]
    assert first_building_point == mod._world_point(149020.0, 169020.0)

    # Crossing surface is clipped exactly at the cell boundary before world conversion.
    assert len(runtime["street_surfaces"]) == 1
    surface_points = runtime["street_surfaces"][0]["polygon"]
    west_world_x = mod._world_point(149000.0, 169000.0)[0]
    east_world_x = mod._world_point(149500.0, 169000.0)[0]
    assert min(point[0] for point in surface_points) >= west_world_x - 1e-6
    assert max(point[0] for point in surface_points) <= east_world_x + 1e-6
    assert math.isclose(min(point[0] for point in surface_points), west_world_x, abs_tol=1e-6)

    # Crossing street segment is clipped at the same western boundary.
    assert network["stats"]["street_segments"] == 1
    street_points = network["street_axes"][0]["points"]
    assert math.isclose(min(point[0] for point in street_points), west_world_x, abs_tol=1e-6)

    # Rail TYPE is authoritative and duplicate TW geometry across rail layers is deduped.
    assert network["stats"]["tram_segments"] == 1, network["stats"]
    assert network["stats"]["train_segments"] == 1, network["stats"]
    assert network["stats"]["unclassified_rail_segments"] == 0
    assert network["tram_network"][0]["type"] == "TW"
    assert network["train_network"][0]["type"] == "RW"

    assert manifest["runtime"]["geometry_stats"]["buildings"] == 1
    assert manifest["runtime"]["geometry_stats"]["street_surfaces"] == 1
    assert manifest["runtime"]["network_stats"] == network["stats"]

    # Fail closed when a declared required source payload disappears.
    (cell_dir / "raw" / "street_axes.geojson").unlink()
    try:
        mod.build(cell_dir, root / "bad-candidate")
    except ValueError as exc:
        assert "required source payload missing" in str(exc)
    else:
        raise AssertionError("missing StreetAxes source must fail closed")

print(
    "BUILD_RUNTIME_CANDIDATE_BUNDLE_OK deterministic=true layers=5 clipping=true "
    "no_fake_heights=true collision=false runtime_mount=false rail_dedupe=true fail_closed=true"
)
