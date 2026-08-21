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


perf = load("terrain_performance_gate_test", HERE / "terrain_performance_gate.py")
streaming = perf.streaming_mod
gate = perf.gate_mod


def write(path: Path, payload: dict) -> None:
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def streaming_probe() -> dict:
    probe = {
        "format": streaming.PROBE_FORMAT,
        "cell_id": CELL,
        "crs": perf.CRS,
        "engine_version": perf.ENGINE_VERSION,
        "bindings": {
            "terrain_lod_evidence_digest": "a" * 64,
            "terrain_runtime_candidate_digest": "b" * 64,
            "secondary_height_validation_digest": "c" * 64,
            "runtime_candidate_digest": "d" * 64,
        },
        "candidate_files": {
            "manifest": "res://fixture/manifest.json",
            "runtime_cell": "res://fixture/runtime/cell.game.json",
            "runtime_network": "res://fixture/runtime/network.game.json",
        },
        "candidate_output_sha256": {
            "manifest.json": "1" * 64,
            "runtime/cell.game.json": "2" * 64,
            "runtime/network.game.json": "3" * 64,
        },
        "world_center": [100.0, 0.0, 200.0],
        "expected": {"buildings": 2, "street_surfaces": 2, "street_segments": 1},
        "streaming_config": {},
        "policy": {"runtime_promotion_allowed": False},
    }
    probe["probe_digest"] = streaming._digest(probe)
    return probe


def result(probe: dict, p95: float = 15.0) -> dict:
    return {
        "format": perf.RESULT_FORMAT,
        "cell_id": CELL,
        "probe_digest": probe["probe_digest"],
        "engine_version": perf.ENGINE_VERSION,
        "renderer": perf.RENDERER,
        "measurement_complete": True,
        "metrics": {
            "warmup_frames": 60,
            "sample_frames": 180,
            "wall_frame_ms_avg": 10.0,
            "wall_frame_ms_p95": p95,
            "draw_calls_max": 100,
            "objects_in_frame_max": 200,
            "primitives_in_frame_max": 5000,
            "static_memory_mib_max": 256.0,
            "stream_total_ms": 12,
            "stream_max_phase_ms": 4,
            "render_metrics_available": True,
            "collision_claimed_false": True,
        },
    }


def budget() -> dict:
    return {
        "format": perf.BUDGET_FORMAT,
        "engine_version": perf.ENGINE_VERSION,
        "renderer": perf.RENDERER,
        "minimum_sample_frames": 180,
        "thresholds": {
            "wall_frame_ms_avg_max": 12.0,
            "wall_frame_ms_p95_max": 16.0,
            "draw_calls_max": 100,
            "objects_in_frame_max": 200,
            "primitives_in_frame_max": 5000,
            "static_memory_mib_max": 256.0,
        },
        "provenance": "synthetic-test-budget-only-not-production-policy",
    }


def main() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        stream_path = root / "stream.json"
        write(stream_path, streaming_probe())

        no_budget_probe = perf.prepare(stream_path)
        probe_path = root / "probe.json"
        result_path = root / "result.json"
        write(probe_path, no_budget_probe)
        write(result_path, result(no_budget_probe))
        blocked = perf.finalize(probe_path, result_path)
        row = blocked["gates"]["performance"]
        assert row["passed"] is False
        assert row["status"] == "blocked_no_versioned_per_cell_budget"
        assert blocked["policy"]["global_workflow_green_is_not_cell_proof"] is True
        assert gate._validate_measurement_bundle(blocked, CELL, no_budget_probe["bindings"])["performance"]["passed"] is False

        budget_path = root / "budget.json"
        write(budget_path, budget())
        budgeted_probe = perf.prepare(stream_path, budget_path)
        write(probe_path, budgeted_probe)
        write(result_path, result(budgeted_probe, 16.0))
        passed = perf.finalize(probe_path, result_path)
        assert passed["gates"]["performance"]["passed"] is True
        assert passed["gates"]["performance"]["budget_checks"]["wall_frame_ms_p95_max"] is True

        write(result_path, result(budgeted_probe, 16.001))
        failed = perf.finalize(probe_path, result_path)
        assert failed["gates"]["performance"]["passed"] is False
        assert failed["gates"]["performance"]["status"] == "failed_versioned_per_cell_performance_budget"

        stale = result(budgeted_probe)
        stale["probe_digest"] = "e" * 64
        write(result_path, stale)
        try:
            perf.finalize(probe_path, result_path)
        except ValueError as exc:
            assert "stale against exact probe" in str(exc)
        else:
            raise AssertionError("stale performance result must fail closed")

        tampered = copy.deepcopy(budgeted_probe)
        tampered["world_center"][0] += 1.0
        write(probe_path, tampered)
        write(result_path, result(budgeted_probe))
        try:
            perf.finalize(probe_path, result_path)
        except ValueError as exc:
            assert "probe digest mismatch" in str(exc)
        else:
            raise AssertionError("tampered performance probe must fail closed")

    print("TERRAIN_PERFORMANCE_GATE_GUARDRAILS_OK exact_binding=true measured=true no_budget=blocked threshold_boundary=true stale=rejected tamper=rejected runtime_promotion=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
