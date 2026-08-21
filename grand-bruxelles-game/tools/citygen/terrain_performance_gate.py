#!/usr/bin/env python3
"""Build fail-closed per-cell terrain performance gate measurements.

The exact sealed candidate is inherited from the already validated streaming probe.
A measurement is always recorded, but it can only pass when an explicit versioned
per-cell budget is supplied. The repository-wide Performance Baseline is useful
measurement evidence, not an authorization threshold.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import importlib.util
import json
import math
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent


def _load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"cannot import {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


streaming_mod = _load("terrain_performance_streaming", HERE / "terrain_streaming_gate.py")
gate_mod = _load("terrain_performance_evidence", HERE / "build_terrain_runtime_gate_evidence.py")

PROBE_FORMAT = "grand-bruxelles-terrain-performance-godot-probe-v1"
RESULT_FORMAT = "grand-bruxelles-terrain-performance-godot-result-v1"
BUDGET_FORMAT = "grand-bruxelles-terrain-performance-budget-v1"
MEASUREMENT_FORMAT = gate_mod.MEASUREMENT_FORMAT
CRS = streaming_mod.CRS
ENGINE_VERSION = streaming_mod.ENGINE_VERSION
RENDERER = "gl_compatibility"
BUDGET_KEYS = (
    "wall_frame_ms_avg_max",
    "wall_frame_ms_p95_max",
    "draw_calls_max",
    "objects_in_frame_max",
    "primitives_in_frame_max",
    "static_memory_mib_max",
)
METRIC_FOR_BUDGET = {
    "wall_frame_ms_avg_max": "wall_frame_ms_avg",
    "wall_frame_ms_p95_max": "wall_frame_ms_p95",
    "draw_calls_max": "draw_calls_max",
    "objects_in_frame_max": "objects_in_frame_max",
    "primitives_in_frame_max": "primitives_in_frame_max",
    "static_memory_mib_max": "static_memory_mib_max",
}


def _read(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"expected JSON object: {path}")
    return value


def _digest(value: Any) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    return hashlib.sha256(raw).hexdigest()


def _require_number(name: str, value: Any, *, minimum: float = 0.0) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise ValueError(f"{name} must be numeric")
    number = float(value)
    if not math.isfinite(number) or number < minimum:
        raise ValueError(f"{name} must be finite and >= {minimum}")
    return number


def _validate_budget(value: dict[str, Any]) -> dict[str, Any]:
    if value.get("format") != BUDGET_FORMAT:
        raise ValueError("unsupported terrain performance budget")
    if value.get("engine_version") != ENGINE_VERSION or value.get("renderer") != RENDERER:
        raise ValueError("terrain performance budget engine/renderer mismatch")
    thresholds = value.get("thresholds")
    if not isinstance(thresholds, dict) or set(thresholds) != set(BUDGET_KEYS):
        raise ValueError("terrain performance budget threshold set mismatch")
    normalized = {key: _require_number(f"thresholds.{key}", thresholds[key]) for key in BUDGET_KEYS}
    if int(value.get("minimum_sample_frames", 0)) < 60:
        raise ValueError("terrain performance budget minimum_sample_frames must be >= 60")
    result = copy.deepcopy(value)
    result["thresholds"] = normalized
    return result


def prepare(streaming_probe_path: Path, budget_path: Path | None = None) -> dict[str, Any]:
    streaming_probe = _read(streaming_probe_path)
    cell_id = streaming_mod._validate_probe(streaming_probe)
    budget = None
    budget_digest = None
    if budget_path is not None:
        budget = _validate_budget(_read(budget_path))
        budget_digest = _digest(budget)

    probe = {
        "format": PROBE_FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "engine_version": ENGINE_VERSION,
        "renderer": RENDERER,
        "bindings": copy.deepcopy(streaming_probe["bindings"]),
        "candidate_files": copy.deepcopy(streaming_probe["candidate_files"]),
        "candidate_output_sha256": copy.deepcopy(streaming_probe["candidate_output_sha256"]),
        "world_center": copy.deepcopy(streaming_probe["world_center"]),
        "expected": copy.deepcopy(streaming_probe["expected"]),
        "measurement_config": {
            "warmup_frames": 60,
            "sample_frames": 180,
            "max_load_frames": 180,
            "viewport_width": 1280,
            "viewport_height": 720,
        },
        "budget": budget,
        "budget_digest": budget_digest,
        "policy": {
            "exact_streaming_probe_reused": True,
            "repository_wide_performance_baseline_is_not_cell_authorization": True,
            "versioned_budget_required_to_pass": True,
            "production_runtime_index_used": False,
            "runtime_promotion_allowed": False,
        },
    }
    probe["probe_digest"] = _digest(probe)
    return probe


def _validate_probe(probe: dict[str, Any]) -> str:
    if probe.get("format") != PROBE_FORMAT or probe.get("crs") != CRS:
        raise ValueError("unsupported terrain performance probe")
    if probe.get("engine_version") != ENGINE_VERSION or probe.get("renderer") != RENDERER:
        raise ValueError("terrain performance probe engine/renderer drift")
    cell_id = probe.get("cell_id")
    if not isinstance(cell_id, str) or not cell_id.startswith("bxl-"):
        raise ValueError("terrain performance probe cell identity missing")
    digest = probe.get("probe_digest")
    if not isinstance(digest, str) or len(digest) != 64:
        raise ValueError("terrain performance probe digest missing")
    view = copy.deepcopy(probe)
    view.pop("probe_digest", None)
    if _digest(view) != digest:
        raise ValueError("terrain performance probe digest mismatch")
    if probe.get("budget") is None:
        if probe.get("budget_digest") is not None:
            raise ValueError("terrain performance probe has digest without budget")
    else:
        budget = _validate_budget(probe["budget"])
        if _digest(budget) != probe.get("budget_digest"):
            raise ValueError("terrain performance budget digest mismatch")
    return cell_id


def finalize(probe_path: Path, result_path: Path) -> dict[str, Any]:
    probe = _read(probe_path)
    cell_id = _validate_probe(probe)
    result = _read(result_path)
    if result.get("format") != RESULT_FORMAT or result.get("cell_id") != cell_id:
        raise ValueError("Godot performance result identity/format mismatch")
    if result.get("probe_digest") != probe.get("probe_digest"):
        raise ValueError("Godot performance result is stale against exact probe")
    if result.get("engine_version") != ENGINE_VERSION or result.get("renderer") != RENDERER:
        raise ValueError("Godot performance result engine/renderer drift")
    metrics = result.get("metrics")
    if not isinstance(metrics, dict):
        raise ValueError("Godot performance result metrics missing")
    config = probe["measurement_config"]
    if int(metrics.get("sample_frames", -1)) != int(config["sample_frames"]):
        raise ValueError("Godot performance result sample count mismatch")
    if result.get("measurement_complete") is not True:
        raise ValueError("Godot performance measurement is incomplete")

    normalized_metrics: dict[str, Any] = {
        "warmup_frames": int(metrics.get("warmup_frames", -1)),
        "sample_frames": int(metrics.get("sample_frames", -1)),
        "wall_frame_ms_avg": _require_number("metrics.wall_frame_ms_avg", metrics.get("wall_frame_ms_avg")),
        "wall_frame_ms_p95": _require_number("metrics.wall_frame_ms_p95", metrics.get("wall_frame_ms_p95")),
        "draw_calls_max": int(_require_number("metrics.draw_calls_max", metrics.get("draw_calls_max"))),
        "objects_in_frame_max": int(_require_number("metrics.objects_in_frame_max", metrics.get("objects_in_frame_max"))),
        "primitives_in_frame_max": int(_require_number("metrics.primitives_in_frame_max", metrics.get("primitives_in_frame_max"))),
        "static_memory_mib_max": _require_number("metrics.static_memory_mib_max", metrics.get("static_memory_mib_max")),
        "stream_total_ms": int(_require_number("metrics.stream_total_ms", metrics.get("stream_total_ms"))),
        "stream_max_phase_ms": int(_require_number("metrics.stream_max_phase_ms", metrics.get("stream_max_phase_ms"))),
        "render_metrics_available": metrics.get("render_metrics_available") is True,
        "collision_claimed_false": metrics.get("collision_claimed_false") is True,
    }
    if normalized_metrics["warmup_frames"] != int(config["warmup_frames"]):
        raise ValueError("Godot performance warmup count mismatch")

    budget = probe.get("budget")
    checks: dict[str, bool] = {}
    if budget is None:
        passed = False
        status = "blocked_no_versioned_per_cell_budget"
    elif not normalized_metrics["render_metrics_available"] or not normalized_metrics["collision_claimed_false"]:
        passed = False
        status = "failed_per_cell_render_measurement_contract"
    else:
        thresholds = budget["thresholds"]
        if normalized_metrics["sample_frames"] < int(budget["minimum_sample_frames"]):
            passed = False
            status = "failed_insufficient_performance_samples"
        else:
            for budget_key, metric_key in METRIC_FOR_BUDGET.items():
                checks[budget_key] = float(normalized_metrics[metric_key]) <= float(thresholds[budget_key])
            passed = all(checks.values())
            status = "passed_versioned_per_cell_performance_budget" if passed else "failed_versioned_per_cell_performance_budget"

    row = {
        "cell_id": cell_id,
        "gate": "performance",
        "passed": passed,
        "status": status,
        "source": "godot_4_7_1_exact_sealed_candidate_performance_probe",
        "budget_digest": probe.get("budget_digest"),
        "budget_checks": checks,
        "metrics": normalized_metrics,
    }
    row["measurement_digest"] = _digest(row)
    bundle = {
        "format": MEASUREMENT_FORMAT,
        "cell_id": cell_id,
        "crs": CRS,
        "bindings": copy.deepcopy(probe["bindings"]),
        "gates": {"performance": row},
        "policy": {
            "exact_per_cell_measurement": True,
            "versioned_budget_required_to_pass": True,
            "global_workflow_green_is_not_cell_proof": True,
            "production_runtime_index_used": False,
            "runtime_promotion_allowed": False,
        },
    }
    bundle["measurement_bundle_digest"] = _digest(bundle)
    return bundle


def main() -> int:
    parser = argparse.ArgumentParser()
    sub = parser.add_subparsers(dest="command", required=True)
    prep = sub.add_parser("prepare")
    prep.add_argument("--streaming-probe", type=Path, required=True)
    prep.add_argument("--budget", type=Path)
    prep.add_argument("--output", type=Path, required=True)
    fin = sub.add_parser("finalize")
    fin.add_argument("--probe", type=Path, required=True)
    fin.add_argument("--godot-result", type=Path, required=True)
    fin.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        if args.command == "prepare":
            payload = prepare(args.streaming_probe, args.budget)
            label = f"TERRAIN_PERFORMANCE_PROBE_OK cell={payload['cell_id']} budget={'present' if payload['budget'] else 'missing'} runtime_promotion=false"
        else:
            payload = finalize(args.probe, args.godot_result)
            row = payload["gates"]["performance"]
            label = f"TERRAIN_PERFORMANCE_GATE_OK cell={payload['cell_id']} passed={str(row['passed']).lower()} status={row['status']} runtime_promotion=false"
    except Exception as exc:
        print(f"TERRAIN_PERFORMANCE_GATE_ERROR: {exc}")
        return 1
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(label)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
