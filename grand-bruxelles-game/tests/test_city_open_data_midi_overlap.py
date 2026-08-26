#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/citygen/classify_city_open_data_midi_overlap.py"
SNAPSHOT = ROOT / "data/provenance/midi_city_open_data_zone_overlap.snapshot.json"

spec = importlib.util.spec_from_file_location("midi_open_data", TOOL)
assert spec and spec.loader
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)

assert mod.bboxes_intersect([0, 0, 1, 1], [1, 1, 2, 2])
assert not mod.bboxes_intersect([0, 0, 1, 1], [2, 2, 3, 3])

fixture_overlap = {
    "dataset_id": "fixture-overlap",
    "features": ["geo"],
    "fields": [{"type": "geo_point_2d"}],
    "metas": {"default": {
        "title": "Neutral title",
        "geometry_types": ["Point"],
        "bbox": {"type": "Feature", "geometry": {"type": "Polygon", "coordinates": [[
            [mod.MIDI_BBOX_WGS84[0], mod.MIDI_BBOX_WGS84[1]],
            [mod.MIDI_BBOX_WGS84[2], mod.MIDI_BBOX_WGS84[1]],
            [mod.MIDI_BBOX_WGS84[2], mod.MIDI_BBOX_WGS84[3]],
            [mod.MIDI_BBOX_WGS84[0], mod.MIDI_BBOX_WGS84[3]],
            [mod.MIDI_BBOX_WGS84[0], mod.MIDI_BBOX_WGS84[1]],
        ]]}, "properties": {}},
    }},
}
row = mod.classify_dataset(fixture_overlap)
assert row["status"] == "OVERLAP_PROVEN"

fixture_title_only = {
    "dataset_id": "midi-in-title-is-not-evidence",
    "features": [],
    "fields": [{"type": "text"}],
    "metas": {"default": {"title": "Midi station", "geometry_types": None, "bbox": None}},
}
assert mod.is_geospatial_candidate(fixture_title_only) is False

fixture_outside = {
    "dataset_id": "fixture-outside",
    "features": ["geo"],
    "fields": [{"type": "geo_shape"}],
    "metas": {"default": {
        "geometry_types": ["Polygon"],
        "bbox": {"type": "Feature", "geometry": {"type": "Polygon", "coordinates": [[
            [10.0, 10.0], [11.0, 10.0], [11.0, 11.0], [10.0, 11.0], [10.0, 10.0],
        ]]}, "properties": {}},
    }},
}
row = mod.classify_dataset(fixture_outside)
assert row["status"] == "UNRESOLVED"
assert "not_proof_of_real_world_absence" in row["reason"]

snapshot = json.loads(SNAPSHOT.read_text(encoding="utf-8"))
mod.validate_snapshot(snapshot)
for key, value in mod.CLOSED_RAILS.items():
    assert snapshot["authorization"][key] is value, key

print(f"MIDI_CITY_OPEN_DATA_TEST_OK status={snapshot['status']} rails=closed")
