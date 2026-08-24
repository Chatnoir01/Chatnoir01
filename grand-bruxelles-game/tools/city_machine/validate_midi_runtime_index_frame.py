#!/usr/bin/env python3
"""Bind the proven Midi Lambert72 frame to the deterministic live road index.

The runtime index intentionally contains only roads eligible for deterministic
source lookup (positive OSM id, non-empty name, drivable, >=2 finite points).
That eligibility contract is shared with build_road_destination_catalog.py and
must not be confused with the raw road-record count in the OSM snapshot.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import math
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1]
DEFAULT = PROJECT / "data/qa/city_machine/midi_onboarding_runtime_index_candidate.json"
CATALOG_SCRIPT = PROJECT / "tools/build_road_destination_catalog.py"
LEGACY = HERE / "validate_midi_onboarding_candidate.py"


class Error(RuntimeError):
    pass


def load(path: Path) -> dict[str, Any]:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise Error(f"expected object: {path}")
    return value


def project(raw: str) -> Path:
    path = (PROJECT / raw).resolve()
    root = PROJECT.resolve()
    if path != root and root not in path.parents:
        raise Error(f"path escapes project: {raw}")
    return path


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise Error(f"cannot load module: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def eligible_road_ids(road_doc: dict[str, Any]) -> tuple[list[int], int]:
    roads = road_doc.get("roads")
    if not isinstance(roads, list) or not roads:
        raise Error("road source has no roads")
    catalog = load_module(CATALOG_SCRIPT, "road_destination_catalog_contract")
    eligible: list[int] = []
    rejected_drivable = 0
    for raw in roads:
        if not isinstance(raw, dict):
            continue
        signature = catalog.road_signature(raw)
        if signature is None:
            if raw.get("drivable") is True:
                rejected_drivable += 1
            continue
        eligible.append(int(signature["osm_id"]))
    if len(set(eligible)) != len(eligible):
        raise Error("eligible road IDs are not unique")
    return sorted(eligible), rejected_drivable


def verify_frame_geometry(candidate: dict[str, Any], road_doc: dict[str, Any]) -> dict[str, Any]:
    historical = load(project(str(candidate.get("historical_frame_candidate", ""))))
    coordinate = historical.get("coordinate_contract")
    if not isinstance(coordinate, dict):
        raise Error("historical coordinate contract missing")
    origin_e = float(coordinate.get("origin_easting_m", math.nan))
    origin_n = float(coordinate.get("origin_northing_m", math.nan))
    if not math.isfinite(origin_e) or not math.isfinite(origin_n):
        raise Error("canonical Lambert72 origin invalid")
    if coordinate.get("runtime_translation_m") != [0.0, 0.0, 0.0]:
        raise Error("runtime translation must remain zero")
    if coordinate.get("frame") != "grand_bruxelles_project_global":
        raise Error("global project frame contract drift")

    bridge = historical.get("road_frame_bridge")
    if not isinstance(bridge, dict):
        raise Error("historical road frame bridge missing")
    if bridge.get("lambert72_formula") != "E=origin_easting_m+x;N=origin_northing_m-z":
        raise Error("Lambert72 formula drift")
    if bridge.get("road_cell_mapping_authorized") is not False:
        raise Error("road-cell mapping must remain review-gated")

    corridor = road_doc.get("corridor")
    anchors = corridor.get("anchors") if isinstance(corridor, dict) else None
    midi = next((row for row in anchors or [] if isinstance(row, dict) and row.get("id") == "midi"), None)
    if midi is None:
        raise Error("Midi road anchor missing")
    midi_xz = [float(midi.get("x")), float(midi.get("z"))]
    expected_xz = [float(v) for v in bridge.get("expected_midi_world_xz", [])]
    if len(expected_xz) != 2 or max(abs(a - b) for a, b in zip(midi_xz, expected_xz)) > 1e-6:
        raise Error("Midi road anchor drift from proven world frame")

    evidence = load(project(str(bridge.get("official_world_frame_evidence", ""))))
    source = evidence.get("source")
    world = evidence.get("world_coordinate_evidence")
    if not isinstance(source, dict) or source.get("crs") != "EPSG:31370" or not isinstance(world, dict):
        raise Error("official Lambert72 evidence invalid")
    official_origin = [float(v) for v in world.get("lambert72_origin", [])]
    official_world = [float(v) for v in world.get("world_origin_xz", [])]
    if official_origin != [origin_e, origin_n]:
        raise Error("official Lambert72 origin drift")
    if official_world != expected_xz:
        raise Error("official world origin drift")

    return {
        "coordinate_frame_proven": True,
        "runtime_translation_m": [0.0, 0.0, 0.0],
        "lambert72_origin": [origin_e, origin_n],
        "lambert72_formula": bridge["lambert72_formula"],
        "midi_world_xz": midi_xz,
        "activatable": False,
        "blockers": list(historical.get("blockers") or []),
        "road_cell_mapping_authorized": False,
        "jouable_promotion_authorized": False,
    }


def validate(path: Path) -> dict[str, Any]:
    candidate = load(path)
    if candidate.get("schema") != "grand-bruxelles-city-machine-runtime-index-frame-candidate-v1":
        raise Error("candidate schema mismatch")
    for key, value in candidate.items():
        if key.endswith("_authorized") and value is not False:
            raise Error(f"{key} must remain false")

    source_rel = str(candidate.get("road_source", ""))
    source = project(source_rel)
    index_rel = str(candidate.get("road_runtime_index", ""))
    index = load(project(index_rel))
    if index.get("format") != "grand-bruxelles-road-runtime-index-v1" or index.get("source_lookup_only") is not True:
        raise Error("runtime index contract mismatch")
    auth = index.get("authorization")
    if not isinstance(auth, dict) or auth.get("source_lookup_only") is not True:
        raise Error("runtime index authorization missing")
    for key, value in auth.items():
        if key.endswith("_authorized") and value is not False:
            raise Error(f"runtime index must keep {key}=false")

    docs = index.get("documents")
    matches = [row for row in docs or [] if isinstance(row, dict) and row.get("path") == source_rel]
    if len(matches) != 1:
        raise Error("runtime index source descriptor cardinality mismatch")
    descriptor = matches[0]
    expected_sha = str(descriptor.get("sha256", "")).lower()
    actual_sha = hashlib.sha256(source.read_bytes()).hexdigest()
    if actual_sha != expected_sha:
        raise Error("road source bytes drift from runtime index descriptor")

    road_doc = load(source)
    if road_doc.get("format") != "grand-bruxelles-osm-v1":
        raise Error("road source format drift")
    if road_doc.get("source") != candidate.get("road_source_provider") or road_doc.get("license") != candidate.get("road_source_license") or road_doc.get("license") != "ODbL-1.0":
        raise Error("road provenance/license drift")

    indexed = descriptor.get("road_ids")
    if not isinstance(indexed, list) or not indexed or not all(isinstance(value, int) for value in indexed):
        raise Error("runtime index road IDs invalid")
    if indexed != sorted(indexed) or len(set(indexed)) != len(indexed):
        raise Error("runtime index road IDs must be unique and sorted")
    eligible, rejected_drivable = eligible_road_ids(road_doc)
    if eligible != indexed:
        raise Error("eligible road IDs drift from runtime index descriptor")

    result = verify_frame_geometry(candidate, road_doc)
    result.update({
        "production_base_sha": candidate.get("production_base_sha"),
        "runtime_index_bound": True,
        "road_runtime_index": index_rel,
        "road_runtime_catalog_sha256": index.get("catalog_sha256"),
        "road_source_sha256": actual_sha,
        "raw_road_count": len(road_doc["roads"]),
        "indexed_road_count": len(indexed),
        "rejected_drivable_road_count": rejected_drivable,
    })
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--candidate", type=Path, default=DEFAULT)
    parser.add_argument("--require-activatable", action="store_true")
    args = parser.parse_args()
    path = args.candidate if args.candidate.is_absolute() else Path.cwd() / args.candidate
    try:
        result = validate(path.resolve())
    except Exception as exc:
        print(f"MIDI_RUNTIME_INDEX_FRAME_RED: {exc}")
        return 2
    print(json.dumps(result, indent=2, sort_keys=True))
    if args.require_activatable:
        print("MIDI_RUNTIME_INDEX_FRAME_HOLD: " + ",".join(result["blockers"]))
        return 3
    print(
        "MIDI_RUNTIME_INDEX_FRAME_GREEN "
        f"indexed_roads={result['indexed_road_count']} raw_roads={result['raw_road_count']} "
        f"rejected_drivable={result['rejected_drivable_road_count']} source_sha256={result['road_source_sha256']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
