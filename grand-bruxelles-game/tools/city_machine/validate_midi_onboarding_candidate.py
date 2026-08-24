#!/usr/bin/env python3
"""Fail-closed proof for the Midi City Machine/global-road-frame candidate.

The OSM road frame is bound through the deterministic runtime road index, then
tied to existing official UrbIS Lambert72 evidence. This proof never creates a
road->cell crosswalk and never authorizes runtime mount, render, collision,
safe-spawn, or JOUABLE promotion.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
DEFAULT_CANDIDATE = PROJECT / "data/qa/city_machine/midi_onboarding_candidate.json"
DEFAULT_RUNTIME_INDEX = PROJECT / "data/runtime/road_destination_runtime_index.json"
EXPECTED_ORIGIN_E = 147868.29422791934
EXPECTED_ORIGIN_N = 169538.62414926197
TOLERANCE_M = 1e-6
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


def sha256_file(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError as exc:
        raise CandidateError(f"cannot hash {path}: {exc}") from exc


def project_path(raw: str) -> Path:
    path = (PROJECT / raw).resolve()
    root = PROJECT.resolve()
    if path != root and root not in path.parents:
        raise CandidateError(f"path escapes project: {raw}")
    return path


def finite_pair(value: Any, label: str) -> tuple[float, float]:
    if not isinstance(value, list) or len(value) != 2:
        raise CandidateError(f"{label} must contain exactly two coordinates")
    try:
        x, z = float(value[0]), float(value[1])
    except (TypeError, ValueError) as exc:
        raise CandidateError(f"{label} coordinates must be numeric") from exc
    if not math.isfinite(x) or not math.isfinite(z):
        raise CandidateError(f"{label} coordinates must be finite")
    return x, z


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
    raw_e, raw_n = first_xy(raw_feature["geometry"].get("coordinates"))
    game_x, game_z = first_xy(game_feature["geometry"].get("coordinates"))
    expected_x = raw_e - origin_e
    expected_z = -(raw_n - origin_n)
    dx = abs(game_x - expected_x)
    dz = abs(game_z - expected_z)
    if dx > 1e-4 or dz > 1e-4:
        raise CandidateError(
            f"{slug}: normalized geometry is not in global project frame "
            f"(dx={dx:.6f}m dz={dz:.6f}m)"
        )
    return {
        "features": len(raw_features),
        "first_feature_id": str(raw_feature.get("id", "")),
        "transform_error_m": max(dx, dz),
    }


def verify_runtime_index(index: dict[str, Any], bridge: dict[str, Any], road_source: Path) -> dict[str, Any]:
    expected_format = str(bridge.get("road_runtime_index_format", ""))
    if index.get("format") != expected_format or expected_format != "grand-bruxelles-road-runtime-index-v1":
        raise CandidateError("runtime road index format mismatch")
    if index.get("source_lookup_only") is not True:
        raise CandidateError("runtime road index must remain source_lookup_only")
    authorization = index.get("authorization")
    if not isinstance(authorization, dict) or authorization.get("source_lookup_only") is not True:
        raise CandidateError("runtime road index source lookup authorization missing")
    for key, value in authorization.items():
        if key.endswith("_authorized") and value is not False:
            raise CandidateError(f"runtime road index authorization rail opened: {key}")
    expected_catalog = str(bridge.get("road_runtime_catalog_sha256", ""))
    if index.get("catalog_sha256") != expected_catalog or len(expected_catalog) != 64:
        raise CandidateError("runtime road index catalog SHA-256 mismatch")

    road_rel = str(bridge.get("road_source", ""))
    documents = index.get("documents")
    if not isinstance(documents, list) or not documents:
        raise CandidateError("runtime road index has no documents")
    matches = [row for row in documents if isinstance(row, dict) and row.get("path") == road_rel]
    if len(matches) != 1:
        raise CandidateError("runtime road index must contain exactly one road source descriptor")
    descriptor = matches[0]
    descriptor_sha = str(descriptor.get("sha256", ""))
    candidate_sha = str(bridge.get("road_source_sha256", ""))
    actual_sha = sha256_file(road_source)
    if descriptor_sha != candidate_sha or actual_sha != descriptor_sha:
        raise CandidateError("road source SHA-256 mismatch")
    road_ids = descriptor.get("road_ids")
    if not isinstance(road_ids, list) or not road_ids or not all(isinstance(v, int) for v in road_ids):
        raise CandidateError("runtime road index road IDs invalid")
    if len(set(road_ids)) != len(road_ids):
        raise CandidateError("runtime road index road IDs must be unique")
    return {
        "road_runtime_index_bound": True,
        "road_runtime_catalog_sha256": expected_catalog,
        "road_runtime_indexed_road_count": len(road_ids),
        "road_source_sha256": actual_sha,
        "road_ids": road_ids,
    }


def verify_road_frame_bridge(
    bridge: dict[str, Any], origin_e: float, origin_n: float, runtime_index_path: Path
) -> dict[str, Any]:
    if bool(bridge.get("road_cell_mapping_authorized", True)):
        raise CandidateError("road-cell mapping must remain review-gated")
    if bridge.get("lambert72_formula") != "E=origin_easting_m+x;N=origin_northing_m-z":
        raise CandidateError("unsupported Lambert72 road-frame formula")

    road_source = project_path(str(bridge.get("road_source", "")))
    index_result = verify_runtime_index(read_json(runtime_index_path), bridge, road_source)
    road_doc = read_json(road_source)
    if road_doc.get("format") != "grand-bruxelles-osm-v1":
        raise CandidateError("unexpected OSM road source format")
    if road_doc.get("source") != bridge.get("road_source_provider"):
        raise CandidateError("road source provider mismatch")
    if road_doc.get("license") != bridge.get("road_source_license") or road_doc.get("license") != "ODbL-1.0":
        raise CandidateError("road source license mismatch")
    roads = road_doc.get("roads")
    if not isinstance(roads, list) or not roads:
        raise CandidateError("road source roads missing")
    source_ids = [row.get("osm_id") for row in roads if isinstance(row, dict)]
    if len(source_ids) != len(roads) or not all(isinstance(v, int) for v in source_ids):
        raise CandidateError("road source OSM IDs invalid")
    if set(source_ids) != set(index_result.pop("road_ids")):
        raise CandidateError("runtime road index membership differs from road source")

    corridor = road_doc.get("corridor")
    if not isinstance(corridor, dict):
        raise CandidateError("road source corridor missing")
    anchors = corridor.get("anchors")
    if not isinstance(anchors, list):
        raise CandidateError("road source anchors missing")
    midi = next((row for row in anchors if isinstance(row, dict) and row.get("id") == "midi"), None)
    if midi is None:
        raise CandidateError("road source Midi anchor missing")
    road_midi = finite_pair([midi.get("x"), midi.get("z")], "road Midi anchor")

    evidence_path = project_path(str(bridge.get("official_world_frame_evidence", "")))
    evidence = read_json(evidence_path)
    source = evidence.get("source")
    world_evidence = evidence.get("world_coordinate_evidence")
    if not isinstance(source, dict) or source.get("crs") != "EPSG:31370":
        raise CandidateError("official world-frame evidence must be EPSG:31370")
    if not isinstance(world_evidence, dict):
        raise CandidateError("official world-frame evidence missing")
    evidence_origin = finite_pair(world_evidence.get("lambert72_origin"), "official Lambert72 origin")
    if abs(evidence_origin[0] - origin_e) > TOLERANCE_M or abs(evidence_origin[1] - origin_n) > TOLERANCE_M:
        raise CandidateError("official Lambert72 origin differs from canonical origin")
    official_world_origin = finite_pair(world_evidence.get("world_origin_xz"), "official world origin")
    expected_world_origin = finite_pair(bridge.get("expected_midi_world_xz"), "expected Midi world anchor")
    if max(abs(official_world_origin[0] - expected_world_origin[0]), abs(official_world_origin[1] - expected_world_origin[1])) > TOLERANCE_M:
        raise CandidateError("Midi world anchor does not match official world-frame evidence")
    if max(abs(road_midi[0] - official_world_origin[0]), abs(road_midi[1] - official_world_origin[1])) > TOLERANCE_M:
        raise CandidateError("OSM Midi anchor does not match official world-frame evidence")

    result = {
        "road_frame_bridge_proven": True,
        "road_source_provider": road_doc.get("source"),
        "road_source_license": road_doc.get("license"),
        "midi_world_xz": [road_midi[0], road_midi[1]],
        "lambert72_origin": [origin_e, origin_n],
        "lambert72_formula": bridge.get("lambert72_formula"),
        "road_cell_mapping_authorized": False,
    }
    result.update(index_result)
    return result


def validate(candidate_path: Path, runtime_index_override: Path | None = None) -> dict[str, Any]:
    candidate = read_json(candidate_path)
    if candidate.get("schema") != "grand-bruxelles-city-machine-zone-onboarding-candidate-v2":
        raise CandidateError("unsupported candidate schema")
    if candidate.get("zone") != "midi":
        raise CandidateError("candidate zone must be midi")
    if candidate.get("source_crs") != "EPSG:31370":
        raise CandidateError("Midi candidate source CRS must be EPSG:31370")
    source_root = project_path(str(candidate.get("source_root", "")))
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
        layers[slug] = verify_layer(
            slug,
            source_root / f"{slug}.geojson",
            project_path(str(normalized[slug])),
            origin_e,
            origin_n,
        )

    bridge = candidate.get("road_frame_bridge")
    if not isinstance(bridge, dict):
        raise CandidateError("road_frame_bridge missing")
    declared_index = project_path(str(bridge.get("road_runtime_index", "")))
    runtime_index_path = runtime_index_override.resolve() if runtime_index_override else declared_index
    bridge_result = verify_road_frame_bridge(bridge, origin_e, origin_n, runtime_index_path)

    activation = candidate.get("activation")
    if not isinstance(activation, dict):
        raise CandidateError("activation contract missing")
    if any(bool(activation.get(key, True)) for key in (
        "registry_mutation_authorized",
        "runtime_mount_authorized",
        "jouable_promotion_authorized",
    )):
        raise CandidateError("activation rails must remain false in frame-proof lot")
    blockers = candidate.get("blockers")
    if not isinstance(blockers, list) or not blockers:
        raise CandidateError("blockers must remain explicit and non-empty")

    result = {
        "zone": "midi",
        "coordinate_frame_proven": True,
        "runtime_translation_m": translation,
        "normalized_layers": layers,
        "legacy_runtime_forbidden": True,
        "activatable": False,
        "blockers": [str(value) for value in blockers],
        "jouable_promotion_authorized": False,
    }
    result.update(bridge_result)
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate fail-closed Midi global-frame and OSM-road bridge candidate")
    parser.add_argument("--candidate", type=Path, default=DEFAULT_CANDIDATE)
    parser.add_argument("--runtime-index", type=Path)
    parser.add_argument("--require-activatable", action="store_true")
    args = parser.parse_args()
    candidate_path = args.candidate if args.candidate.is_absolute() else (Path.cwd() / args.candidate)
    runtime_index = args.runtime_index if args.runtime_index is None or args.runtime_index.is_absolute() else (Path.cwd() / args.runtime_index)
    try:
        result = validate(candidate_path.resolve(), runtime_index.resolve() if runtime_index else None)
    except CandidateError as exc:
        print(f"MIDI_ONBOARDING_CANDIDATE_FAIL: {exc}")
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    if args.require_activatable:
        print("MIDI_ONBOARDING_CANDIDATE_HOLD: " + ",".join(result["blockers"]))
        return 3
    print("MIDI_ONBOARDING_CANDIDATE_OK: global_frame=true road_runtime_index_bound=true runtime_translation=zero")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
