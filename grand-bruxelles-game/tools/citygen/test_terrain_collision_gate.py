#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
import os
import tempfile
from pathlib import Path

try:
    import numpy as np
except ImportError as exc:
    raise SystemExit(f"numpy missing in runner: {exc}")

HERE = Path(__file__).resolve().parent
PROJECT_GODOT = HERE.parents[1] / "project.godot"
CELL = "bxl-e149000-n169000-s500"
BBOX = (149000.0, 169000.0, 149010.0, 169010.0)
SPACING = 2.0


def load(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise RuntimeError(path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


candidate_mod = load("terrain_candidate_collision_test", HERE / "build_cell_terrain_runtime_candidate.py")
readiness_mod = load("terrain_readiness_collision_test", HERE / "build_terrain_runtime_readiness.py")
collision_mod = load("terrain_collision_gate_test", HERE / "terrain_collision_gate.py")


def write(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def _strip_autoload_entries(text: str) -> tuple[str, int]:
    """Remove only [autoload] entries while preserving every other project section."""
    output: list[str] = []
    in_autoload = False
    removed = 0
    for line in text.splitlines(keepends=True):
        stripped = line.strip()
        if stripped == "[autoload]":
            output.append(line)
            in_autoload = True
            continue
        if in_autoload and stripped.startswith("[") and stripped.endswith("]"):
            if not output[-1].endswith("\n\n"):
                output.append("\n")
            output.append(line)
            in_autoload = False
            continue
        if in_autoload:
            if stripped and not stripped.startswith(";"):
                removed += 1
            continue
        output.append(line)
    if in_autoload:
        output.append("\n")
    return "".join(output), removed


def _isolate_ci_collision_probe_from_autoloads() -> None:
    """Make the CI fixture test only the collision script, never unrelated game autoloads.

    This mutates only GitHub Actions' ephemeral checkout. Local test runs are left untouched.
    The normal Game CI still loads the complete project independently.
    """
    if os.environ.get("GITHUB_ACTIONS") != "true":
        return
    original = PROJECT_GODOT.read_text(encoding="utf-8")
    isolated, removed = _strip_autoload_entries(original)
    if removed < 1:
        raise AssertionError("CI collision isolation expected at least one project autoload")
    if "[autoload]" not in isolated or "[display]" not in isolated or "[physics]" not in isolated:
        raise AssertionError("CI collision isolation damaged the project section structure")
    PROJECT_GODOT.write_text(isolated, encoding="utf-8")
    print(f"TERRAIN_COLLISION_CI_AUTOLOAD_ISOLATION_OK removed={removed} project={PROJECT_GODOT}")


def make_candidate(grid: np.ndarray) -> dict:
    encoding, decoded = candidate_mod._encode_heightfield(np.asarray(grid, dtype=np.float64))
    result = {
        "format": candidate_mod.FORMAT,
        "cell_id": CELL,
        "crs": candidate_mod.CRS,
        "bbox_epsg31370": list(BBOX),
        "spacing_m": SPACING,
        "shape": [int(grid.shape[0]), int(grid.shape[1])],
        "sample_count": int(grid.size),
        "topology": {
            "includes_all_four_canonical_cell_edges": True,
            "columns_increase_easting": True,
            "rows_increase_northing": True,
            "godot_world_z_decreases_with_northing": True,
            "shared_edge_coordinates_are_exact": True,
        },
        "source": {
            "kind": "official_validated_DTM",
            "terrain_lod_evidence_digest": "a" * 64,
            "raster_validation_digest": "9" * 64,
            "selected_level_p95_abs_error_m": 0.05,
            "selected_level_vertex_error_evaluated": True,
        },
        "height_encoding": encoding,
        "decoded_height_min_m": round(float(decoded.min()), 6),
        "decoded_height_max_m": round(float(decoded.max()), 6),
        "authorization": {
            "candidate_only": True,
            "terrain_runtime_authorized": False,
            "collision_authorized": False,
            "runtime_mount_authorized": False,
            "jouable_promotion_authorized": False,
        },
        "status": "qa_terrain_runtime_candidate_pending_measured_gates",
    }
    digest_view = copy.deepcopy(result)
    digest_view["height_encoding"].pop("payload_base64", None)
    result["candidate_digest"] = candidate_mod._digest(digest_view)
    return result


def make_base(grid: np.ndarray, root: Path) -> tuple[Path, Path, Path, Path]:
    terrain = {
        "format": readiness_mod.TERRAIN_LOD_FORMAT,
        "cell_id": CELL,
        "crs": readiness_mod.CRS,
        "selection": {"selected_resolution_m": SPACING, "canonical_edge_alignment_required": True},
        "runtime_approved": False,
        "evidence_digest": "a" * 64,
    }
    terrain_candidate = make_candidate(grid)
    secondary = {
        "format": readiness_mod.SECONDARY_FORMAT,
        "cell_id": CELL,
        "crs": readiness_mod.CRS,
        "secondary_validation_complete": True,
        "runtime_promotion_allowed": False,
        "validation_digest": "b" * 64,
    }
    runtime = {
        "format": readiness_mod.CANDIDATE_FORMAT,
        "cell_id": CELL,
        "sealed": {"production_discovery_eligible": False, "requires_explicit_validated_promotion": True},
        "safety": {"runtime_mount_authorized": False, "collision_generated": False},
        "candidate_digest": "c" * 64,
    }
    paths = (
        root / "terrain_lod_evidence.json",
        root / "terrain_runtime_candidate.json",
        root / "secondary_height_validation.json",
        root / "candidate.json",
    )
    for path, payload in zip(paths, (terrain, terrain_candidate, secondary, runtime)):
        write(path, payload)
    return paths


def synthetic_godot_result(probe: dict, passed: bool = True) -> dict:
    raw_samples = probe.get("raycast_samples")
    assert isinstance(raw_samples, list) and len(raw_samples) >= 4
    raycast_samples = []
    for sample in raw_samples:
        raycast_samples.append({
            "sample_id": sample["sample_id"],
            "row": sample["row"],
            "column": sample["column"],
            "expected_height_m": sample["expected_height_m"],
            "hit": passed,
            "hit_height_m": sample["expected_height_m"] if passed else None,
            "abs_error_m": 0.0 if passed else None,
            "maximum_abs_error_m": sample["maximum_abs_error_m"],
        })
    metrics = {
        "map_width": probe["map_width"],
        "map_depth": probe["map_depth"],
        "map_data_count": probe["map_width"] * probe["map_depth"],
        "shape_created": True,
        "shape_rid_valid": True,
        "body_inside_tree": True,
        "shape_min_height_m": probe["decoded_height_min_m"],
        "shape_max_height_m": probe["decoded_height_max_m"],
        "raycast_samples": raycast_samples,
        "raycast_sample_count": len(raycast_samples),
        "raycast_max_abs_error_m": 0.0 if passed else None,
        "collision_scale_xyz_m": probe["spacing_m"],
        "height_data_prescale_inverse_spacing": True,
    }
    return {
        "format": collision_mod.RESULT_FORMAT,
        "cell_id": probe["cell_id"],
        "probe_digest": probe["probe_digest"],
        "engine_version": collision_mod.ENGINE_VERSION,
        "passed": passed,
        "status": "passed_heightmap_shape_staticbody_multiraycast" if passed else "failed_heightmap_shape_staticbody_multiraycast",
        "metrics": metrics,
    }


def run_python_guardrails(emit_probe_root: Path | None) -> None:
    stripped, removed = _strip_autoload_entries(
        "[application]\nname=\"fixture\"\n\n[autoload]\nA=\"*res://a.gd\"\nB=\"*res://b.gd\"\n\n[display]\nwidth=1280\n"
    )
    assert removed == 2
    assert "A=\"*res://a.gd\"" not in stripped and "B=\"*res://b.gd\"" not in stripped
    assert "[application]" in stripped and "[autoload]" in stripped and "[display]" in stripped and "width=1280" in stripped

    rows, cols = np.mgrid[0:6, 0:6]
    grid = 40.0 + 0.25 * cols + 0.10 * rows
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        terrain_path, candidate_path, secondary_path, runtime_path = make_base(grid, root)
        probe = collision_mod.prepare(terrain_path, candidate_path, secondary_path, runtime_path)
        assert probe["map_width"] == 6 and probe["map_depth"] == 6
        assert probe["policy"]["rows_reversed_for_godot_world_z"] is True
        assert probe["policy"]["asymmetric_multi_sample_orientation_proof"] is True
        assert probe["policy"]["collision_authorized"] is False
        assert len(probe["raycast_samples"]) == 5
        assert len({(row["row"], row["column"]) for row in probe["raycast_samples"]}) == 5
        decoded = candidate_mod.decode_heightfield(json.loads(candidate_path.read_text()))
        assert probe["map_data"][:6] == [round(float(value), 6) for value in decoded[-1, :]], probe["map_data"][:6]

        probe_path = root / "probe.json"
        write(probe_path, probe)
        passed_result_path = root / "godot-passed.json"
        write(passed_result_path, synthetic_godot_result(probe, True))
        bundle = collision_mod.finalize(probe_path, passed_result_path)
        row = bundle["gates"]["collisions"]
        assert row["passed"] is True
        assert row["status"] == "passed_godot_4_7_1_heightmap_shape_multiraycast"
        assert row["metrics"]["raycast_sample_count"] == 5
        assert all(item["checks"]["raycast_hit"] for item in row["metrics"]["sample_checks"])
        assert bundle["policy"]["asymmetric_multi_sample_orientation_proof_required"] is True
        assert bundle["policy"]["runtime_promotion_allowed"] is False

        failed_result_path = root / "godot-failed.json"
        write(failed_result_path, synthetic_godot_result(probe, False))
        failed_bundle = collision_mod.finalize(probe_path, failed_result_path)
        assert failed_bundle["gates"]["collisions"]["passed"] is False

        stale = synthetic_godot_result(probe, True)
        stale["probe_digest"] = "d" * 64
        stale_path = root / "godot-stale.json"
        write(stale_path, stale)
        try:
            collision_mod.finalize(probe_path, stale_path)
        except ValueError as exc:
            assert "stale against exact probe" in str(exc)
        else:
            raise AssertionError("stale Godot collision result must fail closed")

        tampered = copy.deepcopy(probe)
        tampered["map_data"][0] += 1.0
        tampered_path = root / "tampered-probe.json"
        write(tampered_path, tampered)
        try:
            collision_mod.finalize(tampered_path, passed_result_path)
        except ValueError as exc:
            assert "probe digest mismatch" in str(exc)
        else:
            raise AssertionError("tampered collision probe must fail closed")

        if emit_probe_root is not None:
            emit_probe_root.mkdir(parents=True, exist_ok=True)
            write(emit_probe_root / f"{CELL}.json", probe)
            _isolate_ci_collision_probe_from_autoloads()

    print(
        "TERRAIN_COLLISION_GATE_GUARDRAILS_OK exact_candidate=true even_heightmap=true row_orientation=locked "
        "multiraycast=5 asymmetric_orientation=true autoload_isolation=ci_only godot_binding=exact "
        "negative_measurement=persisted stale=rejected tamper=rejected collision_authorized=false runtime_promotion=false"
    )


def verify_godot_results(probe_root: Path, result_root: Path, measurement_root: Path | None) -> None:
    probes = sorted(probe_root.glob("*.json"))
    if not probes:
        raise SystemExit("no collision probes to verify")
    passed = 0
    for probe_path in probes:
        result_path = result_root / probe_path.name
        if not result_path.is_file():
            raise AssertionError(f"missing Godot result for {probe_path.name}")
        bundle = collision_mod.finalize(probe_path, result_path)
        row = bundle["gates"]["collisions"]
        assert row["passed"] is True, row
        assert row["metrics"]["raycast_sample_count"] >= 4
        assert all(row["metrics"]["contract_checks"].values()), row["metrics"]["contract_checks"]
        passed += 1
        if measurement_root is not None:
            write(measurement_root / probe_path.name, bundle)
    print(f"TERRAIN_COLLISION_GODOT_RESULT_VERIFIED probes={len(probes)} passed={passed} multiraycast=true engine=4.7.1 runtime_promotion=false")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--emit-probe-root", type=Path)
    parser.add_argument("--verify-probe-root", type=Path)
    parser.add_argument("--godot-result-root", type=Path)
    parser.add_argument("--measurement-root", type=Path)
    args = parser.parse_args()
    run_python_guardrails(args.emit_probe_root)
    if args.verify_probe_root is not None or args.godot_result_root is not None:
        if args.verify_probe_root is None or args.godot_result_root is None:
            raise SystemExit("--verify-probe-root and --godot-result-root must be supplied together")
        verify_godot_results(args.verify_probe_root, args.godot_result_root, args.measurement_root)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
