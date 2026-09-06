#!/usr/bin/env python3
"""Fail-closed contract for staged Midi City Machine geometry.

Normalized City Machine outputs are valid engineering inputs, but availability of
source geometry is not permission to replace the canonical playable Midi render.
This test freezes that boundary until a dedicated visual/collision promotion is
accepted.
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
BUILDER = PROJECT / "game/scripts/urbis_midi_builder.gd"
BUILDINGS = PROJECT / "data/urbis/midi/buildings.game.json"
STREET_SURFACES = PROJECT / "data/urbis/midi/street_surfaces.game.json"

EXPECTED_ORIGIN_E = 147868.29422791934
EXPECTED_ORIGIN_N = 169538.62414926197
EPSILON_M = 1e-5


def read_json(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    assert isinstance(value, dict), path
    return value


def exterior_points(feature: dict[str, Any]) -> list[list[float]]:
    geometry = feature.get("geometry") or {}
    coordinates = geometry.get("coordinates") or []
    geometry_type = geometry.get("type")
    if geometry_type == "Polygon":
        return coordinates[0]
    if geometry_type == "MultiPolygon":
        return coordinates[0][0]
    raise AssertionError(f"unsupported geometry type: {geometry_type!r}")


def inferred_origin(feature: dict[str, Any]) -> tuple[float, float]:
    bbox = feature.get("bbox") or []
    assert len(bbox) == 4, "normalized feature must retain Lambert72 bbox evidence"
    points = exterior_points(feature)
    xs = [float(point[0]) for point in points]
    zs = [float(point[1]) for point in points]

    # Normalized contract: X = E - originE, Z = originN - N.
    e_candidates = [float(bbox[0]) - min(xs), float(bbox[2]) - max(xs)]
    n_candidates = [float(bbox[3]) + min(zs), float(bbox[1]) + max(zs)]
    assert max(e_candidates) - min(e_candidates) < EPSILON_M, e_candidates
    assert max(n_candidates) - min(n_candidates) < EPSILON_M, n_candidates
    return sum(e_candidates) / 2.0, sum(n_candidates) / 2.0


def feature_collection(path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    data = read_json(path)
    assert data.get("type") == "FeatureCollection", path
    features = data.get("features") or []
    assert isinstance(features, list) and features, path
    assert all(isinstance(feature, dict) for feature in features), path
    return data, features


def main() -> int:
    builder = BUILDER.read_text(encoding="utf-8")

    # Canonical runtime remains the currently approved Midi geometry. Merely
    # committing normalized City Machine files must never auto-promote them.
    legacy_runtime = 'res://data/urbis/midi/midi_runtime.game.json'
    assert legacy_runtime in builder, "canonical Midi runtime source changed without promotion"
    assert "const MIDI_WORLD" in builder, "canonical Midi anchor changed without promotion"
    assert "MIDI_WORLD +" in builder, "canonical Midi transform changed without promotion"
    assert "res://data/urbis/midi/buildings.game.json" not in builder
    assert "res://data/urbis/midi/street_surfaces.game.json" not in builder

    _, building_features = feature_collection(BUILDINGS)
    _, surface_features = feature_collection(STREET_SURFACES)
    building_origin = inferred_origin(building_features[0])
    surface_origin = inferred_origin(surface_features[0])

    for label, origin in [("buildings", building_origin), ("street_surfaces", surface_origin)]:
        assert abs(origin[0] - EXPECTED_ORIGIN_E) < EPSILON_M, (label, origin)
        assert abs(origin[1] - EXPECTED_ORIGIN_N) < EPSILON_M, (label, origin)

    assert abs(building_origin[0] - surface_origin[0]) < EPSILON_M
    assert abs(building_origin[1] - surface_origin[1]) < EPSILON_M

    # Preserve the measured blast-radius evidence in the contract: normalized
    # coverage is materially broader than the currently approved canonical set,
    # so it requires its own visual/collision promotion instead of silent wiring.
    assert len(surface_features) > 1270, len(surface_features)
    assert len(building_features) > 2750, len(building_features)

    print(
        "CITY_MACHINE_MIDI_STAGED_OK "
        f"origin_e={building_origin[0]:.9f} origin_n={building_origin[1]:.9f} "
        f"surfaces={len(surface_features)} buildings={len(building_features)} "
        "canonical_runtime=legacy normalized_geometry=staged promotion_required=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
