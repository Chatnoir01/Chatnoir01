#!/usr/bin/env python3
"""Regression contract for read-only UrbIS3D temporal lifecycle diagnostics."""
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("diagnose_urbis3d_temporal_provenance.py")
spec = importlib.util.spec_from_file_location("urbis3d_temporal_provenance", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

# Mirrors the exact lifecycle field family observed in the production-selected
# UrbISBuildings3D GeoPackage: BEGINLIFE / ENDLIFE. No per-face SOURCE* fields
# are invented when the distributed schema does not contain them.
rows = [
    {
        "INSPIRE_ID": "face-a",
        "BUSOLID_ID": "solid-1",
        "TYPE": "GROUNDSURFACE",
        "BEGINLIFE": "2020-05-01T00:00:00",
        "ENDLIFE": None,
    },
    {
        "INSPIRE_ID": "face-b",
        "BUSOLID_ID": "solid-1",
        "TYPE": "ROOFSURFACE",
        "BEGINLIFE": "2023-06-15T12:00:00",
        "ENDLIFE": "",
    },
    {
        "INSPIRE_ID": "face-c",
        "BUSOLID_ID": "solid-1",
        "TYPE": "WALLSURFACE",
        "BEGINLIFE": "unparseable-source-value",
        "ENDLIFE": "2024-01-02T00:00:00",
    },
]

result = module.summarize_face_metadata(rows, reference_date="2021-10-09")
assert result["face_count"] == 3
assert result["type_counts"] == {"GROUNDSURFACE": 1, "ROOFSURFACE": 1, "WALLSURFACE": 1}
assert result["begin_life_values"] == [
    "2020-05-01T00:00:00",
    "2023-06-15T12:00:00",
    "unparseable-source-value",
]
assert result["end_life_values"] == ["2024-01-02T00:00:00"]
assert result["parseable_begin_life_count"] == 2
assert result["begin_life_after_reference_count"] == 1
assert result["unparseable_begin_life_count"] == 1
assert result["reference_date"] == "2021-10-09"
assert result["lifecycle_fields"] == {"begin": "BEGINLIFE", "end": "ENDLIFE"}
assert result["policy"]["database_lifecycle_metadata_only"] is True
assert result["policy"]["physical_change_inference_allowed"] is False
assert result["policy"]["construction_date_inference_allowed"] is False
assert result["policy"]["per_face_source_provenance_inference_allowed"] is False
assert result["policy"]["automatic_resolution_allowed"] is False
assert result["policy"]["runtime_approved"] is False
assert result["policy"]["thresholds_changed"] is False
print("URBIS3D_TEMPORAL_PROVENANCE_TEST_OK faces=3 post_reference=1 fields=BEGINLIFE/ENDLIFE physical_change_inference=false runtime=false")
