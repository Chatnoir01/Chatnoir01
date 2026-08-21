#!/usr/bin/env python3
from __future__ import annotations

import copy
import importlib.util
import json
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
CELL = "bxl-e149000-n169000-s500"


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


photo = load("terrain_photo_match_gate_test", HERE / "terrain_photo_match_gate.py")
streaming = photo.streaming_mod
gate = photo.gate_mod


def write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def stream_probe() -> dict:
    probe = {
        "format": streaming.PROBE_FORMAT,
        "cell_id": CELL,
        "crs": photo.CRS,
        "engine_version": streaming.ENGINE_VERSION,
        "bindings": {
            "terrain_lod_evidence_digest": "a" * 64,
            "terrain_runtime_candidate_digest": "b" * 64,
            "secondary_height_validation_digest": "c" * 64,
            "runtime_candidate_digest": "d" * 64,
        },
        "candidate_files": {},
        "candidate_output_sha256": {},
        "world_center": [0.0, 0.0, 0.0],
        "expected": {},
        "streaming_config": {},
        "policy": {"runtime_promotion_allowed": False},
    }
    probe["probe_digest"] = streaming._digest(probe)
    return probe


def reference(binding=None, complete=False, screenshot=None) -> dict:
    scores = {field: (4.0 if complete else None) for field in photo.photo_mod.SCORE_FIELDS}
    row = {
        "id": "fixture-photo",
        "hero_location": "Fixture",
        "zone": "fixture",
        "reference": {
            "source_page": "https://example.com/photo",
            "captured_at": "2026-01-01",
            "author": "Fixture",
            "license": "CC0-1.0",
            "distribution_policy": "test-only",
            "camera_notes": "fixture",
        },
        "viewpoint": {
            "description": "fixture viewpoint",
            "game_camera_transform": ({"position":[0,1,0],"rotation_degrees":[0,0,0],"fov_degrees":60,"status":"approved"} if complete else None),
            "game_screenshot": screenshot,
        },
        "scores": scores,
        "mismatches": ([] if complete else [{"severity":"blocker","action":"finish exact comparison"}]),
        "realism_complete": complete,
    }
    if binding is not None:
        row["citygen_binding"] = binding
    return row


def manifest(ref: dict) -> dict:
    return {
        "schema_version": 1,
        "score_scale": {
            "min": 0,
            "max": 5,
            "passing_average": 4.0,
            "critical_fields": ["silhouette","building_placement","height_roofline","street_width","landmark_alignment"],
        },
        "references": [ref],
    }


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "project.godot").write_text("[application]\n", encoding="utf-8")
        stream_path = root / "stream.json"
        probe = stream_probe()
        write(stream_path, probe)
        manifest_path = root / "data/qa/photo_match/manifest.json"

        write(manifest_path, manifest(reference()))
        blocked = photo.build(stream_path, manifest_path)
        row = blocked["gates"]["photo_match"]
        assert row["passed"] is False
        assert row["status"] == "blocked_no_exact_cell_photo_reference"
        assert gate._validate_measurement_bundle(blocked, CELL, probe["bindings"])["photo_match"]["passed"] is False

        binding = {"cell_id": CELL, "crs": photo.CRS, **probe["bindings"]}
        write(manifest_path, manifest(reference(binding=binding)))
        incomplete = photo.build(stream_path, manifest_path)
        assert incomplete["gates"]["photo_match"]["status"] == "blocked_exact_reference_not_realism_complete"

        screenshot = root / "artifacts/photo-match/fixture.png"
        screenshot.parent.mkdir(parents=True, exist_ok=True)
        screenshot.write_bytes(b"fixture")
        write(manifest_path, manifest(reference(binding=binding, complete=True, screenshot="artifacts/photo-match/fixture.png")))
        passed = photo.build(stream_path, manifest_path)
        assert passed["gates"]["photo_match"]["passed"] is True
        assert passed["gates"]["photo_match"]["metrics"]["selected_score_average"] == 4.0

        stale = copy.deepcopy(binding)
        stale["runtime_candidate_digest"] = "e" * 64
        write(manifest_path, manifest(reference(binding=stale)))
        try:
            photo.build(stream_path, manifest_path)
        except ValueError as exc:
            assert "stale against exact cell artifacts" in str(exc)
        else:
            raise AssertionError("stale photo-match binding must fail closed")

    print("TERRAIN_PHOTO_MATCH_GATE_GUARDRAILS_OK threshold=4.0 exact_binding=true incomplete=blocked stale=rejected realism_complete=required runtime_promotion=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
