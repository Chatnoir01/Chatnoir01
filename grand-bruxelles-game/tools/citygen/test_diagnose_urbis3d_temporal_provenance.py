#!/usr/bin/env python3
"""Regression contract for read-only UrbIS3D temporal provenance diagnostics."""
from __future__ import annotations

import importlib.util
from pathlib import Path

MODULE_PATH = Path(__file__).with_name("diagnose_urbis3d_temporal_provenance.py")
spec = importlib.util.spec_from_file_location("urbis3d_temporal_provenance", MODULE_PATH)
assert spec and spec.loader
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

rows = [
    {
        "INSPIRE_ID": "face-a",
        "BUSOLID_ID": "solid-1",
        "TYPE": "GROUNDSURFACE",
        "BEGINGENERATION": "2020-05-01T00:00:00",
        "ENDGENERATION": None,
        "SOURCEURI": "https://example.invalid/source-a",
        "SOURCETYPE": "PLAN",
        "SOURCEID": "A",
    },
    {
        "INSPIRE_ID": "face-b",
        "BUSOLID_ID": "solid-1",
        "TYPE": "ROOFSURFACE",
        "BEGINGENERATION": "2023-06-15T12:00:00",
        "ENDGENERATION": "",
        "SOURCEURI": "https://example.invalid/source-b",
        "SOURCETYPE": "PHOTOGRAMMETRY",
        "SOURCEID": "B",
    },
    {
        "INSPIRE_ID": "face-c",
        "BUSOLID_ID": "solid-1",
        "TYPE": "WALLSURFACE",
        "BEGINGENERATION": "unparseable-source-value",
        "ENDGENERATION": "2024-01-02T00:00:00",
        "SOURCEURI": None,
        "SOURCETYPE": "PHOTOGRAMMETRY",
        "SOURCEID": "B",
    },
]

result = module.summarize_face_metadata(rows, reference_date="2021-10-09")
assert result["face_count"] == 3
assert result["type_counts"] == {"GROUNDSURFACE": 1, "ROOFSURFACE": 1, "WALLSURFACE": 1}
assert result["begin_generation_values"] == [
    "2020-05-01T00:00:00",
    "2023-06-15T12:00:00",
    "unparseable-source-value",
]
assert result["end_generation_values"] == ["2024-01-02T00:00:00"]
assert result["source_type_values"] == ["PHOTOGRAMMETRY", "PLAN"]
assert result["source_id_values"] == ["A", "B"]
assert result["parseable_begin_generation_count"] == 2
assert result["begin_generation_after_reference_count"] == 1
assert result["unparseable_begin_generation_count"] == 1
assert result["reference_date"] == "2021-10-09"
assert result["policy"]["database_lifecycle_metadata_only"] is True
assert result["policy"]["physical_change_inference_allowed"] is False
assert result["policy"]["construction_date_inference_allowed"] is False
assert result["policy"]["automatic_resolution_allowed"] is False
assert result["policy"]["runtime_approved"] is False
assert result["policy"]["thresholds_changed"] is False
print("URBIS3D_TEMPORAL_PROVENANCE_TEST_OK faces=3 post_reference=1 physical_change_inference=false runtime=false")
