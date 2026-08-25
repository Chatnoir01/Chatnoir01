#!/usr/bin/env python3
from __future__ import annotations

import json
import tempfile
from pathlib import Path

from measure_urbis_source_cell_semantic_lock import measure_cell


def write_cell(root: Path, feature_id: str, x: float) -> None:
    root.mkdir(parents=True, exist_ok=True)
    layers = {}
    for logical, wfs, filename in [
        ("buildings", "urbisvector:Buildings", "raw/buildings.geojson"),
        ("street_surfaces", "urbisvector:StreetSurfaces", "raw/street_surfaces.geojson"),
        ("street_axes", "urbisvector:StreetAxes", "raw/street_axes.geojson"),
        ("tram_network", "urbisvector:TramNetwork", "raw/tram_network.geojson"),
        ("train_network", "urbisvector:TrainNetwork", "raw/train_network.geojson"),
    ]:
        feature = {
            "type": "Feature",
            "id": feature_id,
            "properties": {"INSPIRE_ID": f"urn:test:{logical}"},
            "geometry": {"type": "Point", "coordinates": [x, 170100.0]},
        }
        path = root / filename
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({"type": "FeatureCollection", "features": [feature]}, separators=(",", ":")) + "\n")
        layers[logical] = {
            "wfs_name": wfs,
            "features": 1,
            "ownership": "canonical_centroid_global_500m_cell" if logical == "buildings" else "bbox_intersection_source_unclipped",
            "file": filename,
        }
    manifest = {
        "format": "grand-bruxelles-urbis-source-cell-v1",
        "cell_id": root.name,
        "crs": "EPSG:31370",
        "bbox": [147500.0, 170000.0, 148000.0, 170500.0],
        "layers": layers,
        "promotion": "source_only_no_runtime_mutation",
        "source_digest": "test-source-digest",
    }
    maturity = {
        "format": "grand-bruxelles-cell-maturity-v1",
        "maturity": {
            "state": "data_ready",
            "gates": {
                "source_requirements": True,
                "verification": True,
                "crs": True,
                "runtime_geometry": False,
                "collisions": False,
                "streaming": False,
                "terrain": False,
                "heights": False,
                "photo_match": False,
                "performance": False,
            },
        },
    }
    (root / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    (root / "maturity.json").write_text(json.dumps(maturity, indent=2, sort_keys=True) + "\n")


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        base = Path(tmp)
        a = base / "a" / "bxl-e147500-n170000-s500"
        b = base / "b" / "bxl-e147500-n170000-s500"
        c = base / "c" / "bxl-e147500-n170000-s500"
        write_cell(a, "volatile.1", 147600.0)
        write_cell(b, "volatile.999", 147600.0)
        write_cell(c, "volatile.1", 147601.0)
        ma = measure_cell(a)
        mb = measure_cell(b)
        mc = measure_cell(c)
        assert ma["maturity_state"] == "data_ready"
        assert ma["source_semantic_sha256"] == mb["source_semantic_sha256"], "transport Feature.id must not affect semantic identity"
        assert ma["source_semantic_sha256"] != mc["source_semantic_sha256"], "geometry drift must affect semantic identity"
        assert ma["registration_authorized"] is False
        assert ma["runtime_mount_authorized"] is False
        assert ma["jouable_promotion_authorized"] is False
        assert set(ma["layers"]) == {"buildings", "street_surfaces", "street_axes", "tram_network", "train_network"}

        broken = json.loads((a / "maturity.json").read_text())
        broken["maturity"]["gates"]["runtime_geometry"] = True
        (a / "maturity.json").write_text(json.dumps(broken, indent=2, sort_keys=True) + "\n")
        try:
            measure_cell(a)
        except ValueError as exc:
            assert "runtime_geometry" in str(exc)
        else:
            raise AssertionError("runtime_geometry=true must fail closed")
    print("URBIS_SOURCE_CELL_SEMANTIC_MEASUREMENT_TEST_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
