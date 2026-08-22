#!/usr/bin/env python3
"""Fail-closed proof for the Midi City Machine onboarding candidate.

This tool proves that the committed normalized UrbIS layers already use the
Grand Bruxelles global game frame. It never mutates the City Machine registry
and never authorizes runtime/JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
DEFAULT_CANDIDATE = PROJECT / "data/qa/city_machine/midi_onboarding_candidate.json"
EXPECTED_ORIGIN_E = 147868.29422791934
EXPECTED_ORIGIN_N = 169538.62414926197
TOLERANCE_M = 1e-4
REQUIRED_SLUGS = ("buildings", "street_surfaces", "street_axes")


class CandidateError(RuntimeError):
    pass


def read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CandidateError(f"cannot read {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise CandidateError(f"expected JSON object: {path}")
    return value


def project_path(raw: str) -> Path:
    path = (PROJECT / raw).resolve()
    root = PROJECT.resolve()
    if path != root and root not in path.parents:
        raise CandidateError(f"path escapes project: {raw}")
    return path


def first_xy(value: Any) -> tuple[float, float]:
    if isinstance(value, list):
        if len(value) >= 2 and all(isinstance(item, (int, float)) for item in value[:2]):
            x, y = float(value[0]), float(value[1])
            if math.isfinite(x) and math.isfinite(y):
                return x, y
        for child in value:
            try:
                return first_xy(child)
            except CandidateError:
                pass
    raise CandidateError("geometry has no finite coordinate pair")


def first_feature(document: dict[str, Any]) -> dict[str, Any]:
    features = document.get("features")
    if not isinstance(features, list) or not features:
        raise CandidateError("FeatureCollection has no features")
    for feature in features:
        if isinstance(feature, dict) and isinstance(feature.get("geometry"), dict):
            return feature
    raise CandidateError("FeatureCollection has no usable geometry")


def verify_layer(slug: str, raw_path: Path, game_path: Path, origin_e: float, origin_n: float) -> dict[str, Any]:
    raw_doc = read_json(raw_path)
    game_doc = read_json(game_path)
    raw_features = raw_doc.get("features")
    game_features = game_doc.get("features")
    if not isinstance(raw_features, list) or not isinstance(game_features, list):
        raise CandidateError(f"{slug}: features missing")
    if len(raw_features) != len(game_features) or not raw_features:
        raise CandidateError(f"{slug}: raw/game feature-count mismatch")

    raw_feature = first_feature(raw_doc)
    game_feature = first_feature(game_doc)
    if raw_feature.get("id") != game_feature.get("id"):
        raise CandidateError(f"{slug}: transformation changed first feature identity")

    raw_x, raw_n = first_xy(raw_feature["geometry"].get("coordinates"))
    game_x, game_z = first_xy(game_feature["geometry"].get("coordinates"))
    expected_x = raw_x - origin_e
    expected_z = -(raw_n - origin_n)
    dx = abs(game_x - expected_x)
    dz = abs(game_z - expected_z)
    if dx > TOLERANCE_M or dz > TOLERANCE_M:
        raise CandidateError(
            f"{slug}: normalized geometry is not in global project frame "
            f"(dx={dx:.6f}m dz={dz:.6f}m)"
        )
    return {
        "features": len(raw_features),
        "first_feature_id": str(raw_feature.get("id", "")),
        "transform_error_m": max(dx, dz),
    }


def validate(candidate_path: Path) -> dict[str, Any]:
    candidate = read_json(candidate_path)
    if candidate.get("schema") != "grand-bruxelles-city-machine-zone-onboarding-candidate-v1":
        raise CandidateError("unsupported candidate schema")
    if candidate.get("zone") != "midi":
        raise CandidateError("candidate zone must be midi")
    if candidate.get("source_crs") != "EPSG:31370":
        raise CandidateError("Midi candidate source CRS must be EPSG:31370")

    source_root_raw = str(candidate.get("source_root", ""))
    source_root = project_path(source_root_raw)
    manifest = read_json(source_root / "manifest.json")
    manifest_crs = manifest.get("source_crs", manifest.get("crs"))
    if manifest_crs != "EPSG:31370":
        raise CandidateError("Midi UrbIS manifest CRS mismatch")

    coordinate = candidate.get("coordinate_contract")
    if not isinstance(coordinate, dict):
        raise CandidateError("coordinate_contract missing")
    if coordinate.get("frame") != "grand_bruxelles_project_global":
        raise CandidateError("candidate does not declare global project frame")
    origin_e = float(coordinate.get("origin_easting_m", math.nan))
    origin_n = float(coordinate.get("origin_northing_m", math.nan))
    if abs(origin_e - EXPECTED_ORIGIN_E) > 1e-9 or abs(origin_n - EXPECTED_ORIGIN_N) > 1e-9:
        raise CandidateError("candidate origin differs from canonical Grand Bruxelles origin")
    translation = coordinate.get("runtime_translation_m")
    if translation != [0.0, 0.0, 0.0]:
        raise CandidateError("Midi normalized layers require zero runtime translation")
    if bool(coordinate.get("additional_zone_offset_allowed", True)):
        raise CandidateError("additional Midi zone offset must remain forbidden")

    normalized = candidate.get("normalized_runtime_inputs")
    if not isinstance(normalized, dict) or set(normalized) != set(REQUIRED_SLUGS):
        raise CandidateError("normalized_runtime_inputs must contain exactly the required geometry families")
    forbidden = {str(value) for value in candidate.get("legacy_runtime_inputs_forbidden", [])}
    if "data/urbis/midi/midi_runtime.game.json" not in forbidden:
        raise CandidateError("legacy Midi runtime input is not explicitly forbidden")
    if any(str(value) in forbidden or "midi_runtime.game.json" in str(value) for value in normalized.values()):
        raise CandidateError("legacy Midi aggregate cannot be a normalized runtime input")

    layers: dict[str, Any] = {}
    for slug in REQUIRED_SLUGS:
        raw_path = source_root / f"{slug}.geojson"
        game_path = project_path(str(normalized[slug]))
        layers[slug] = verify_layer(slug, raw_path, game_path, origin_e, origin_n)

    activation = candidate.get("activation")
    if not isinstance(activation, dict):
        raise CandidateError("activation contract missing")
    blockers = candidate.get("blockers")
    if not isinstance(blockers, list):
        raise CandidateError("blockers must be a list")
    activatable = (
        not blockers
        and bool(activation.get("registry_mutation_authorized", False))
        and bool(activation.get("runtime_mount_authorized", False))
        and not bool(activation.get("jouable_promotion_authorized", True))
    )
    return {
        "zone": "midi",
        "coordinate_frame_proven": True,
        "runtime_translation_m": translation,
        "normalized_layers": layers,
        "legacy_runtime_forbidden": True,
        "activatable": activatable,
        "blockers": [str(value) for value in blockers],
        "jouable_promotion_authorized": False,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate fail-closed Midi City Machine onboarding candidate")
    parser.add_argument("--candidate", type=Path, default=DEFAULT_CANDIDATE)
    parser.add_argument("--require-activatable", action="store_true")
    args = parser.parse_args()
    candidate_path = args.candidate if args.candidate.is_absolute() else (Path.cwd() / args.candidate)
    try:
        result = validate(candidate_path.resolve())
    except CandidateError as exc:
        print(f"MIDI_ONBOARDING_CANDIDATE_FAIL: {exc}")
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    if args.require_activatable and not result["activatable"]:
        print("MIDI_ONBOARDING_CANDIDATE_HOLD: " + ",".join(result["blockers"]))
        return 3
    print("MIDI_ONBOARDING_CANDIDATE_OK: global_frame=true runtime_translation=zero legacy=false")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
