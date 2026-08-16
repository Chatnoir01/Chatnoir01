#!/usr/bin/env python3
import importlib.util

from pathlib import Path

HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("validate_rasters", HERE / "validate_cell_elevation_rasters.py")
mod = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mod)


def meta(tile="149169"):
    min_e,min_n,max_e,max_n=mod.tile_bbox(tile)
    return {
        "width":1000,"height":1000,"count":1,"crs_epsg":31370,
        "bounds":[float(min_e),float(min_n),float(max_e),float(max_n)],
        "resolution":[1.0,1.0],"transform":[1.0,0.0,float(min_e),0.0,-1.0,float(max_n)],
    }

m=meta(); mod.validate_raster_metadata("149169",m)
for bad,needle in [({**m,"crs_epsg":4326},"expected EPSG"),({**m,"bounds":[0,0,1000,1000]},"do not match"),({**m,"resolution":[1.0,2.0]},"non-square")]:
    try:
        mod.validate_raster_metadata("149169",bad)
    except ValueError as exc:
        assert needle in str(exc)
    else:
        raise AssertionError(f"bad raster metadata accepted: {bad}")

dsm={"kind":"dsm","rasters":[{"tile":"149169","raster":meta()}]}
dtm={"kind":"dtm","rasters":[{"tile":"149169","raster":meta()}]}
mod.validate_pair_alignment(dsm,dtm)
dtm_bad={"kind":"dtm","rasters":[{"tile":"149169","raster":{**meta(),"transform":[2.0,0.0,149000.0,0.0,-2.0,170000.0]}}]}
try:
    mod.validate_pair_alignment(dsm,dtm_bad)
except ValueError as exc:
    assert "transform mismatch" in str(exc)
else:
    raise AssertionError("misaligned DSM/DTM pair must fail closed")

assert mod.tile_bbox("149169")== (149000,169000,150000,170000)
try:
    mod.tile_bbox("bad")
except ValueError:
    pass
else:
    raise AssertionError("invalid tile code must fail closed")

print("CELL_ELEVATION_RASTER_VALIDATION_GUARDRAILS_OK crs=true bounds=true alignment=true gates_unpromoted=true")
