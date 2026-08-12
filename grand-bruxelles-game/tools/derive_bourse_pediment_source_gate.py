#!/usr/bin/env python3
"""Decide whether UrbIS3D contains a defensible front-pediment envelope.

The Brussels heritage inventory establishes the semantic fact that the boulevard
façade has six Corinthian columns carrying a triangular pediment. This tool does
not invent its dimensions. It projects authoritative UrbIS3D wall/roof vertices
into the already-reviewed Bourse front basis and only emits a candidate when a
front-depth slice contains a centered apex plus symmetric left/right shoulders
with source-backed rise.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any, Iterable


SCHEMA = "grand-bruxelles-bourse-pediment-source-gate-v1"


def _iter_unique_vertices(hero: dict[str, Any], allowed: set[str]) -> Iterable[tuple[float, float, float]]:
    seen: set[tuple[float, float, float]] = set()
    for face in hero.get("faces", []):
        if not isinstance(face, dict) or str(face.get("type", "")) not in allowed:
            continue
        for triangle in face.get("triangles", []):
            if not isinstance(triangle, list) or len(triangle) != 3:
                continue
            for raw in triangle:
                if not isinstance(raw, list) or len(raw) != 3:
                    continue
                point = (float(raw[0]), float(raw[1]), float(raw[2]))
                key = tuple(round(v, 4) for v in point)
                if key not in seen:
                    seen.add(key)
                    yield point


def _project(point: tuple[float, float, float], plane: tuple[float, float], tangent: tuple[float, float], forward: tuple[float, float]) -> dict[str, float]:
    dx = point[0] - plane[0]
    dz = point[2] - plane[1]
    return {
        "x_m": point[0],
        "y_m": point[1],
        "z_m": point[2],
        "tangent_m": dx * tangent[0] + dz * tangent[1],
        "depth_m": dx * forward[0] + dz * forward[1],
    }


def _top_per_bin(points: list[dict[str, float]], t_min: float, t_max: float, bins: int = 41) -> list[dict[str, float] | None]:
    width = (t_max - t_min) / bins
    out: list[dict[str, float] | None] = []
    for i in range(bins):
        left = t_min + i * width
        right = t_max if i == bins - 1 else left + width
        candidates = [p for p in points if left <= p["tangent_m"] <= right]
        out.append(None if not candidates else max(candidates, key=lambda p: p["y_m"]))
    return out


def _median(values: list[float]) -> float:
    if not values:
        return math.nan
    values = sorted(values)
    mid = len(values) // 2
    if len(values) % 2:
        return values[mid]
    return (values[mid - 1] + values[mid]) * 0.5


def derive_from_projected(points: list[dict[str, float]], t_min: float, t_max: float, depth_band_m: float) -> dict[str, Any]:
    selected = [p for p in points if abs(p["depth_m"]) <= depth_band_m and t_min <= p["tangent_m"] <= t_max]
    profile = _top_per_bin(selected, t_min, t_max)
    active = [p for p in profile if p is not None]
    span = t_max - t_min
    if span <= 0 or len(active) < 9:
        return {"defensible": False, "reason": "insufficient_front_profile", "depth_band_m": depth_band_m, "active_bins": len(active)}

    center_t = (t_min + t_max) * 0.5
    apex = max(active, key=lambda p: (p["y_m"], -abs(p["tangent_m"] - center_t)))
    apex_offset = abs(apex["tangent_m"] - center_t)

    # Shoulder windows intentionally occupy the outer-middle façade, avoiding
    # both the extreme corners and the central apex region.
    left = [p for p in active if t_min + 0.12 * span <= p["tangent_m"] <= t_min + 0.36 * span]
    right = [p for p in active if t_max - 0.36 * span <= p["tangent_m"] <= t_max - 0.12 * span]
    if len(left) < 2 or len(right) < 2:
        return {"defensible": False, "reason": "missing_source_shoulders", "depth_band_m": depth_band_m, "active_bins": len(active)}

    left_y = _median([p["y_m"] for p in left])
    right_y = _median([p["y_m"] for p in right])
    base_y = (left_y + right_y) * 0.5
    rise = apex["y_m"] - base_y
    shoulder_delta = abs(left_y - right_y)

    left_peak = max(left, key=lambda p: p["y_m"])
    right_peak = max(right, key=lambda p: p["y_m"])
    apex_centered = apex_offset <= 0.20 * span
    source_rise = rise >= 1.25
    shoulders_level = shoulder_delta <= 1.25
    apex_above_both = apex["y_m"] >= max(left_peak["y_m"], right_peak["y_m"]) + 0.65

    defensible = bool(apex_centered and source_rise and shoulders_level and apex_above_both)
    reason = "source_triangle_envelope_detected" if defensible else "front_source_profile_not_uniquely_triangular"
    return {
        "defensible": defensible,
        "reason": reason,
        "depth_band_m": depth_band_m,
        "active_bins": len(active),
        "front_span_m": span,
        "apex": apex,
        "apex_center_offset_m": apex_offset,
        "left_shoulder_y_m": left_y,
        "right_shoulder_y_m": right_y,
        "shoulder_delta_m": shoulder_delta,
        "base_y_m": base_y,
        "rise_m": rise,
        "checks": {
            "apex_centered": apex_centered,
            "source_rise": source_rise,
            "shoulders_level": shoulders_level,
            "apex_above_both": apex_above_both,
        },
    }


def analyze(hero: dict[str, Any], candidate: dict[str, Any]) -> dict[str, Any]:
    if hero.get("schema") != "grand-bruxelles-urbis-hero-mesh-v1":
        raise ValueError("unsupported hero schema")
    if candidate.get("schema") != "grand-bruxelles-bourse-portico-articulation-candidate-v1":
        raise ValueError("unsupported candidate schema")
    source = candidate.get("source_contract", {})
    fact = str(source.get("heritage_front_fact", ""))
    if "six Corinthian columns" not in fact or "triangular pediment" not in fact:
        raise ValueError("heritage pediment fact missing")

    env = candidate["authoritative_front_envelope"]
    plane = tuple(float(v) for v in env["plane_point_game_x_z"])
    tangent = tuple(float(v) for v in env["tangent_x_z"])
    forward = tuple(float(v) for v in env["toward_camera_x_z"])
    t_min = float(env["tangent_min_m"])
    t_max = float(env["tangent_max_m"])
    ent_top = float(candidate["provisional_visualization"]["entablature_center_y_m"]) + float(candidate["provisional_visualization"]["entablature_height_m"]) * 0.5

    projected = [
        _project(p, plane, tangent, forward)
        for p in _iter_unique_vertices(hero, {"WALLSURFACE", "ROOFSURFACE"})
        if p[1] >= ent_top - 0.75
    ]
    bands = [derive_from_projected(projected, t_min, t_max, band) for band in (2.0, 4.0, 6.0, 8.0)]
    defensible = [b for b in bands if b.get("defensible")]

    # A single lucky depth slice is not sufficient. Require agreement in at
    # least two adjacent front bands so deeper dome geometry cannot masquerade
    # as the front pediment.
    accepted: dict[str, Any] | None = None
    for first, second in zip(bands, bands[1:]):
        if first.get("defensible") and second.get("defensible"):
            if abs(float(first["apex"]["y_m"]) - float(second["apex"]["y_m"])) <= 0.75:
                accepted = first
                break

    return {
        "schema": SCHEMA,
        "hero_id": hero.get("hero_id"),
        "source": {
            "crs": hero.get("source", {}).get("crs"),
            "package_sha256": hero.get("source", {}).get("package_sha256"),
            "heritage_source": source.get("heritage_source"),
            "heritage_fact": fact,
        },
        "front_basis": {
            "plane_point_game_x_z": list(plane),
            "tangent_x_z": list(tangent),
            "toward_camera_x_z": list(forward),
            "tangent_min_m": t_min,
            "tangent_max_m": t_max,
            "entablature_top_y_m": ent_top,
        },
        "projected_source_vertex_count": len(projected),
        "depth_band_results": bands,
        "defensible_band_count": len(defensible),
        "pediment_candidate": accepted,
        "pediment_geometry_approved_for_runtime_overlay": False,
        "runtime_approved": False,
        "realism_complete": False,
        "status": "source_envelope_candidate_found_manual_visual_gate_required" if accepted else "source_profile_insufficient_do_not_invent_pediment",
        "next_gate": "If candidate exists, render it as a separate provisional overlay and inspect deterministic geotagged capture; otherwise keep current runtime unchanged and move to next unowned major mismatch.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--hero", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    report = analyze(json.loads(args.hero.read_text()), json.loads(args.candidate.read_text()))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
