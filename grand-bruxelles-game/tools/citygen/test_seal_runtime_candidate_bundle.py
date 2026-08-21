#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
BUILD_SPEC = importlib.util.spec_from_file_location("runtime_candidate", HERE / "build_runtime_candidate_bundle.py")
build_mod = importlib.util.module_from_spec(BUILD_SPEC)
assert BUILD_SPEC and BUILD_SPEC.loader
BUILD_SPEC.loader.exec_module(build_mod)
SEAL_SPEC = importlib.util.spec_from_file_location("seal_candidate", HERE / "seal_runtime_candidate_bundle.py")
seal_mod = importlib.util.module_from_spec(SEAL_SPEC)
assert SEAL_SPEC and SEAL_SPEC.loader
SEAL_SPEC.loader.exec_module(seal_mod)

CELL_ID = "bxl-e149000-n169000-s500"
BBOX = [149000.0, 169000.0, 149500.0, 169500.0]
LAYERS = {
    "buildings": ("urbisvector:Buildings", "raw/buildings.geojson"),
    "street_surfaces": ("urbisvector:StreetSurfaces", "raw/street_surfaces.geojson"),
    "street_axes": ("urbisvector:StreetAxes", "raw/street_axes.geojson"),
    "tram_network": ("urbisvector:TramNetwork", "raw/tram_network.geojson"),
    "train_network": ("urbisvector:TrainNetwork", "raw/train_network.geojson"),
}


def feature(fid: str, geometry: dict, **props) -> dict:
    return {"type": "Feature", "properties": {"INSPIRE_ID": fid, **props}, "geometry": geometry}


def collection(layer: str, features: list[dict]) -> dict:
    return {
        "type": "FeatureCollection",
        "features": features,
        "numberReturned": len(features),
        "grand_bruxelles_source": {
            "authority": "Paradigm / Brussels-Capital Region",
            "service": "fixture",
            "layer": layer,
            "crs": "EPSG:31370",
            "bbox": BBOX,
            "cell_id": CELL_ID,
            "ownership": "fixture",
        },
    }


def polygon(points: list[list[float]]) -> dict:
    return {"type": "Polygon", "coordinates": [[*points, points[0]]]}


def line(points: list[list[float]]) -> dict:
    return {"type": "LineString", "coordinates": points}


def write_source(root: Path) -> Path:
    cell = root / CELL_ID
    docs = {
        "buildings": collection(LAYERS["buildings"][0], [feature("building-1", polygon([[149020,169020],[149060,169020],[149060,169060],[149020,169060]]), AREA=1600)]),
        "street_surfaces": collection(LAYERS["street_surfaces"][0], [feature("surface-1", polygon([[149010,169080],[149100,169080],[149100,169120],[149010,169120]]), AREA=3600, TYPE="S", LVL=0)]),
        "street_axes": collection(LAYERS["street_axes"][0], [feature("street-1", line([[149010,169100],[149200,169100]]), TYPE="S")]),
        "tram_network": collection(LAYERS["tram_network"][0], [feature("tram-1", line([[149020,169150],[149220,169150]]), TYPE="TW")]),
        "train_network": collection(LAYERS["train_network"][0], [feature("train-1", line([[149020,169180],[149220,169180]]), TYPE="RW")]),
    }
    manifest_layers = {}
    for logical, (wfs_name, relative) in LAYERS.items():
        path = cell / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(docs[logical], separators=(",", ":")) + "\n", encoding="utf-8")
        manifest_layers[logical] = {"wfs_name": wfs_name, "features": len(docs[logical]["features"]), "file": relative}
    manifest = {
        "format": "grand-bruxelles-urbis-source-cell-v1",
        "cell_id": CELL_ID,
        "crs": "EPSG:31370",
        "bbox": BBOX,
        "layers": manifest_layers,
        "promotion": "source_only_no_runtime_mutation",
    }
    (cell / "manifest.json").write_text(json.dumps(manifest, sort_keys=True) + "\n", encoding="utf-8")
    return cell


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp)
    source = write_source(root)
    bundle = root / "candidate"
    build_mod.build(source, bundle)

    pre_manifest = json.loads((bundle / "manifest.json").read_text())
    assert pre_manifest["format"] == seal_mod.PRODUCTION_BUILT_FORMAT
    assert pre_manifest["authorization"]["runtime_mount_authorized"] is False

    sealed = seal_mod.seal(bundle)
    manifest = json.loads((bundle / "manifest.json").read_text())
    runtime = json.loads((bundle / "runtime" / "cell.game.json").read_text())
    assert manifest["format"] == seal_mod.CANDIDATE_BUILT_FORMAT
    assert manifest["promotion"]["production_discovery_eligible"] is False
    assert manifest["promotion"]["requires_explicit_validated_promotion"] is True
    assert sealed["sealed"]["production_discovery_eligible"] is False
    assert sealed["output_sha256"]["manifest.json"] == seal_mod._sha(bundle / "manifest.json")
    assert all("height" not in building for building in runtime["buildings"])
    assert runtime["authorization"]["runtime_mount_authorized"] is False
    assert runtime["authorization"]["collision_authorized"] is False

    try:
        seal_mod.seal(bundle)
    except ValueError as exc:
        assert "root manifest format drift" in str(exc)
    else:
        raise AssertionError("already-sealed candidate must fail closed")

    unsafe = root / "unsafe"
    build_mod.build(source, unsafe)
    unsafe_manifest = json.loads((unsafe / "manifest.json").read_text())
    unsafe_manifest["authorization"]["runtime_mount_authorized"] = True
    (unsafe / "manifest.json").write_text(json.dumps(unsafe_manifest, sort_keys=True) + "\n", encoding="utf-8")
    try:
        seal_mod.seal(unsafe)
    except ValueError as exc:
        assert "runtime_mount_authorized" in str(exc)
    else:
        raise AssertionError("unsafe runtime authorization must fail closed")

print("SEAL_RUNTIME_CANDIDATE_OK candidate_root=true production_discovery=false unsafe_authorization_rejected=true double_seal_rejected=true independent_from_terrain=true")
