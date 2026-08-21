#!/usr/bin/env python3
"""Production-readiness audit for City Machine outputs.

G7-G12 are deliberately distinct from the deterministic G1-G6 rebuild gates:
missing production evidence is reported as BLOCKED, structural corruption as FAIL.
Use --require-ready to turn any BLOCKED gate into a non-zero promotion guard.
"""
from __future__ import annotations

import argparse
import math
import sys
from typing import Any, Iterable

import city_machine as cm

PRODUCTION_GATES = [
    "G7_generated_ownership",
    "G8_landmark_non_regression",
    "G9_collision_solidity",
    "G10_geometry_outliers",
    "G11_streaming_mount",
    "G12_performance_evidence",
]


class ReadinessError(cm.MachineError):
    pass


def _result(gate: str, status: str, detail: str) -> dict[str, str]:
    print(f"CITY_MACHINE_READINESS {status} {gate} detail={detail}", flush=True)
    return {"gate": gate, "status": status, "detail": detail}


def _data_output_owners(registry: dict[str, Any], zone_id: str, profile: dict[str, Any]) -> dict[str, str]:
    owners: dict[str, str] = {}
    for row in registry.get("layers", []):
        if not isinstance(row, dict) or zone_id not in row.get("enabled_zones", []):
            continue
        owner = str(row.get("layer_id", ""))
        for raw in row.get("outputs", []):
            path = str(raw)
            if not path.startswith("data/"):
                continue
            if path in owners:
                raise ReadinessError(f"generated output has multiple owners: {path} ({owners[path]}, {owner})")
            owners[path] = owner
    finish = str((profile.get("finish_materials") or {}).get("output", ""))
    if finish:
        if finish in owners:
            raise ReadinessError(f"finish material output already owned by {owners[finish]}: {finish}")
        owners[finish] = "finish_materials"
    return owners


def gate_g7(registry: dict[str, Any], zone_id: str, profile: dict[str, Any]) -> dict[str, str]:
    owners = _data_output_owners(registry, zone_id, profile)
    if not owners:
        raise ReadinessError("no generated data outputs are owned")
    missing = [path for path in owners if not cm.p(path).is_file()]
    if missing:
        raise ReadinessError(f"owned generated outputs missing: {missing}")
    runtime_script = str(profile.get("runtime_script", ""))
    runtime_scene = str(profile.get("runtime_scene", ""))
    if runtime_script in owners or runtime_scene in owners:
        raise ReadinessError("authored runtime file incorrectly claimed as generated output")
    return _result("G7_generated_ownership", "PASS", f"owned_outputs={len(owners)} unique=true authored_runtime_protected=true")


def _selector_tokens(selector: str) -> list[str]:
    return [token.strip() for token in selector.split("+") if token.strip()]


def gate_g8(profile: dict[str, Any]) -> dict[str, str]:
    text = cm.p(profile["runtime_script"]).read_text(encoding="utf-8")
    overrides = (profile.get("finish_materials") or {}).get("authored_overrides", [])
    if not isinstance(overrides, list) or not overrides:
        return _result("G8_landmark_non_regression", "BLOCKED", "no authored landmark guard registered")
    guarded: list[str] = []
    missing: list[str] = []
    for row in overrides:
        if not isinstance(row, dict):
            continue
        selector = str(row.get("selector", ""))
        owner = str(row.get("owner", ""))
        tokens = _selector_tokens(selector)
        guarded.extend(tokens)
        missing.extend(token for token in tokens if token not in text)
        owner_token = owner.split("::", 1)[-1].strip()
        if owner_token and owner_token not in text:
            missing.append(owner_token)
    if missing:
        raise ReadinessError(f"landmark guard tokens disappeared from runtime: {sorted(set(missing))}")
    return _result("G8_landmark_non_regression", "PASS", f"guarded={','.join(sorted(set(guarded)))} policy=authored_override")


def gate_g9(profile: dict[str, Any]) -> dict[str, str]:
    text = cm.p(profile["runtime_script"]).read_text(encoding="utf-8")
    ground_ok = "JettePhase2ReferenceGroundCollision" in text and "CollisionShape3D.new()" in text
    building_ok = any(token in text for token in (
        "JetteOfficialBuildingsCollision",
        "_build_building_collision",
        "create_trimesh_shape()",
        "create_convex_shape()",
    ))
    if not ground_ok:
        raise ReadinessError("reference ground collision contract disappeared")
    if not building_ok:
        return _result("G9_collision_solidity", "BLOCKED", "ground_collision=true building_collision=false owner=Laeken/Jette-runtime")
    return _result("G9_collision_solidity", "PASS", "ground_collision=true building_collision=true")


def _iter_xy(value: Any) -> Iterable[tuple[float, float]]:
    if isinstance(value, list):
        if len(value) >= 2 and isinstance(value[0], (int, float)) and isinstance(value[1], (int, float)):
            yield float(value[0]), float(value[1])
            return
        for item in value:
            yield from _iter_xy(item)


def _outside_distance(x: float, z: float, bounds: tuple[float, float, float, float]) -> float:
    xmin, zmin, xmax, zmax = bounds
    dx = max(xmin - x, 0.0, x - xmax)
    dz = max(zmin - z, 0.0, z - zmax)
    return math.hypot(dx, dz)


def gate_g10(profile: dict[str, Any], manifest: dict[str, Any]) -> dict[str, str]:
    root = cm.p(profile["source_root"])
    bounds = cm.game_bounds(manifest)
    # WFS bbox queries can return long crossing features whose vertices extend
    # beyond the bbox. This gate catches CRS/origin-scale disasters, not valid
    # boundary overhang, so the limit is intentionally city-scale.
    max_distance = 5000.0
    points = 0
    worst = 0.0
    nonfinite = 0
    gross = 0
    for slug in profile.get("materialized_slugs", []):
        document = cm.read_json(root / f"{slug}.game.json")
        features = document.get("features", [])
        if not isinstance(features, list):
            raise ReadinessError(f"runtime layer features missing: {slug}")
        for feature in features:
            if not isinstance(feature, dict):
                continue
            geometry = feature.get("geometry") or {}
            if not isinstance(geometry, dict):
                continue
            for x, z in _iter_xy(geometry.get("coordinates", [])):
                points += 1
                if not (math.isfinite(x) and math.isfinite(z)):
                    nonfinite += 1
                    continue
                distance = _outside_distance(x, z, bounds)
                worst = max(worst, distance)
                if distance > max_distance:
                    gross += 1
    if points == 0:
        raise ReadinessError("no runtime geometry coordinates found")
    if nonfinite or gross:
        raise ReadinessError(f"geometry outliers nonfinite={nonfinite} gross={gross} worst={worst:.2f}m")
    return _result("G10_geometry_outliers", "PASS", f"points={points} gross=0 nonfinite=0 worst_bbox_overhang={worst:.2f}m limit={max_distance:.0f}m")


def gate_g11(profile: dict[str, Any]) -> dict[str, str]:
    streaming = profile.get("streaming") or {}
    status = str(streaming.get("status", "missing"))
    authorized = streaming.get("runtime_mount_authorized") is True
    cell_size = streaming.get("cell_size_m")
    if status not in {"wired", "ready"} or not authorized:
        return _result("G11_streaming_mount", "BLOCKED", f"status={status} runtime_mount_authorized={str(authorized).lower()} cell_size_m={cell_size}")
    if not isinstance(cell_size, (int, float)) or not 100 <= float(cell_size) <= 1000:
        raise ReadinessError(f"invalid streaming cell_size_m={cell_size}")
    return _result("G11_streaming_mount", "PASS", f"status={status} runtime_mount_authorized=true cell_size_m={cell_size}")


def gate_g12(profile: dict[str, Any], manifest: dict[str, Any]) -> dict[str, str]:
    evidence = profile.get("performance_evidence")
    total_features = sum(
        int((manifest.get("layers") or {}).get(slug, {}).get("features", 0))
        for slug in profile.get("materialized_slugs", [])
    )
    if not isinstance(evidence, dict) or evidence.get("status") != "measured":
        return _result("G12_performance_evidence", "BLOCKED", f"measured_web_budget=false source_features={total_features}")
    frame_ms = evidence.get("p95_frame_ms_web")
    budget_ms = evidence.get("max_p95_frame_ms_web")
    if not isinstance(frame_ms, (int, float)) or not isinstance(budget_ms, (int, float)):
        raise ReadinessError("performance evidence missing numeric p95/budget")
    if float(frame_ms) > float(budget_ms):
        return _result("G12_performance_evidence", "BLOCKED", f"p95_frame_ms_web={float(frame_ms):.2f} budget={float(budget_ms):.2f}")
    return _result("G12_performance_evidence", "PASS", f"p95_frame_ms_web={float(frame_ms):.2f} budget={float(budget_ms):.2f} source_features={total_features}")


def run(zone_id: str, require_ready: bool = False) -> int:
    registry = cm.load_registry()
    catalog = cm.read_json(cm.CATALOG)
    cm.resolve_zone(catalog, zone_id)
    profile = (registry.get("zone_profiles") or {}).get(zone_id)
    if not profile:
        raise ReadinessError(f"zone '{zone_id}' is not enabled in city_machine")
    manifest = cm.source_contract(profile)

    print(f"CITY_MACHINE_READINESS_START zone={zone_id} require_ready={str(require_ready).lower()}", flush=True)
    results = [
        gate_g7(registry, zone_id, profile),
        gate_g8(profile),
        gate_g9(profile),
        gate_g10(profile, manifest),
        gate_g11(profile),
        gate_g12(profile, manifest),
    ]
    blocked = [row for row in results if row["status"] == "BLOCKED"]
    passed = [row for row in results if row["status"] == "PASS"]
    print(
        f"CITY_MACHINE_READINESS_END zone={zone_id} pass={len(passed)} blocked={len(blocked)} "
        f"promotion={'blocked' if blocked else 'candidate'}",
        flush=True,
    )
    if require_ready and blocked:
        return 4
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zone", required=True)
    parser.add_argument("--require-ready", action="store_true")
    args = parser.parse_args()
    try:
        return run(args.zone, args.require_ready)
    except (OSError, ValueError, cm.GateError, cm.MachineError, ReadinessError) as exc:
        print(f"CITY_MACHINE_READINESS_FAIL {exc}", file=sys.stderr, flush=True)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
