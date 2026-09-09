from __future__ import annotations

import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
PRECONDITION_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_precondition.lock.json"
MIDI_CANDIDATE_PATH = ROOT / "data/qa/city_machine/midi_onboarding_candidate.json"

EXPECTED_SCHEMA = "grand-bruxelles-spatial-crosswalk-origin-evidence-v1"
EXPECTED_MEASUREMENT_SCHEMA = "grand-bruxelles-road-registered-cell-overlap-measurement-v2"
EXPECTED_OWNER = {
    "pr": 1562,
    "head_sha": "9fdbf01073deb311097bcc70e2e8b627a004a8b1",
    "workflow": "Grand Bruxelles City Machine Midi Runtime-Index Frame",
    "run_id": 34248313500,
    "artifact_id": 10065069360,
    "artifact_digest": "sha256:7c6dbd4e1ce3feeca476d60acfb147f97dd4cd43a0bc1063ca2d12059a230894",
    "artifact_name": "road-registered-cell-overlap-v2-candidate",
}
EXPECTED_FRAME = {
    "crs": "EPSG:31370",
    "origin_easting_m": 147868.29422791934,
    "origin_northing_m": 169538.62414926197,
    "formula": "E=origin_easting_m+x;N=origin_northing_m-z",
}
EXPECTED_ROAD_SOURCE = {
    "road_source": "data/osm/vertical_slice_01.game.json",
    "road_source_sha256": "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398",
    "road_source_provider": "OpenStreetMap contributors via Overpass API",
    "road_source_license": "ODbL-1.0",
}
EXPECTED_TOP_KEYS = {"schema", "source_owner", "measured_contract", "authorization", "scope_note"}
EXPECTED_OWNER_KEYS = {"pr", "head_sha", "workflow", "run_id", "artifact_id", "artifact_digest", "artifact_name"}
EXPECTED_FRAME_KEYS = {"crs", "origin_easting_m", "origin_northing_m", "formula"}
EXPECTED_AUTH_KEYS = {
    "crosswalk_authorized",
    "road_cell_mapping_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
}
EXPECTED_MEASURED_KEYS = {
    "schema", "cell_crs", "frame", "registered_cell_index", "registered_cell_index_semantic_sha256",
    "road_runtime_index", "road_runtime_catalog_sha256", "road_source", "road_source_sha256",
    "road_source_provider", "road_source_license", "raw_road_count", "road_count",
    "registered_cell_count", "overlapping_road_count", "semantic_sha256",
}
LOWER_HEX_40 = re.compile(r"^[0-9a-f]{40}$")
LOWER_HEX_64 = re.compile(r"^[0-9a-f]{64}$")
SHA256_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate JSON key: {key}")
        value[key] = item
    return value


def _load(path: Path, label: str) -> Any:
    try:
        return json.loads(path.read_bytes().decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not valid UTF-8 JSON") from exc


def _exact(value: Any, keys: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError(f"{label} schema drift")
    return value


def validate() -> None:
    evidence = _exact(_load(EVIDENCE_PATH, "origin evidence"), EXPECTED_TOP_KEYS, "origin evidence")
    precondition = _load(PRECONDITION_PATH, "spatial crosswalk precondition")
    midi = _load(MIDI_CANDIDATE_PATH, "Midi onboarding candidate")

    if evidence["schema"] != EXPECTED_SCHEMA:
        raise ValueError("origin evidence schema drift")
    if not isinstance(evidence["scope_note"], str) or not evidence["scope_note"] or evidence["scope_note"] != evidence["scope_note"].strip():
        raise ValueError("origin evidence scope_note must be a non-empty trimmed string")

    owner = _exact(evidence["source_owner"], EXPECTED_OWNER_KEYS, "origin evidence source_owner")
    if owner != EXPECTED_OWNER:
        raise ValueError("origin evidence source_owner immutable identity drift")
    if LOWER_HEX_40.fullmatch(owner["head_sha"]) is None or SHA256_DIGEST.fullmatch(owner["artifact_digest"]) is None:
        raise ValueError("origin evidence source_owner digest identity is malformed")
    for key in ("pr", "run_id", "artifact_id"):
        if type(owner[key]) is not int or owner[key] <= 0:
            raise ValueError(f"origin evidence source_owner.{key} must be a positive integer")

    measured = _exact(evidence["measured_contract"], EXPECTED_MEASURED_KEYS, "origin evidence measured_contract")
    if measured["schema"] != EXPECTED_MEASUREMENT_SCHEMA or measured["cell_crs"] != "EPSG:31370":
        raise ValueError("origin evidence measured contract identity drift")
    frame = _exact(measured["frame"], EXPECTED_FRAME_KEYS, "origin evidence frame")
    if frame != EXPECTED_FRAME:
        raise ValueError("origin evidence frame drift")
    for key in ("registered_cell_index_semantic_sha256", "road_runtime_catalog_sha256", "road_source_sha256", "semantic_sha256"):
        if not isinstance(measured[key], str) or LOWER_HEX_64.fullmatch(measured[key]) is None:
            raise ValueError(f"origin evidence {key} must be lowercase SHA-256")
    if any(measured[key] != expected for key, expected in EXPECTED_ROAD_SOURCE.items()):
        raise ValueError("origin evidence road source immutable identity drift")
    expected_counts = {"raw_road_count": 140, "road_count": 139, "registered_cell_count": 5, "overlapping_road_count": 64}
    for key, expected in expected_counts.items():
        if type(measured[key]) is not int or measured[key] != expected:
            raise ValueError(f"origin evidence {key} drift")
    if not (measured["overlapping_road_count"] <= measured["road_count"] <= measured["raw_road_count"]):
        raise ValueError("origin evidence road accounting is inconsistent")

    auth = _exact(evidence["authorization"], EXPECTED_AUTH_KEYS, "origin evidence authorization")
    if any(type(value) is not bool or value is not False for value in auth.values()):
        raise ValueError("origin evidence authorization rails must remain false")

    bridge = midi.get("road_frame_bridge")
    coordinate = midi.get("coordinate_contract")
    if not isinstance(bridge, dict) or not isinstance(coordinate, dict):
        raise ValueError("Midi origin bridge contract missing")
    if coordinate.get("origin_easting_m") != frame["origin_easting_m"] or coordinate.get("origin_northing_m") != frame["origin_northing_m"]:
        raise ValueError("Midi coordinate origin does not match locked origin evidence")
    if bridge.get("lambert72_formula") != frame["formula"] or bridge.get("road_runtime_index") != measured["road_runtime_index"] or bridge.get("road_runtime_catalog_sha256") != measured["road_runtime_catalog_sha256"] or bridge.get("road_source") != measured["road_source"] or bridge.get("road_source_sha256") != measured["road_source_sha256"] or bridge.get("road_source_provider") != measured["road_source_provider"] or bridge.get("road_source_license") != measured["road_source_license"]:
        raise ValueError("Midi road-frame bridge does not match locked origin evidence")

    crosswalk = precondition.get("crosswalk")
    if not isinstance(crosswalk, dict) or crosswalk.get("status") != "UNRESOLVED_PROVENANCE" or crosswalk.get("authorized") is not False:
        raise ValueError("spatial crosswalk precondition must remain unresolved and unauthorized")
    for key in ("target_grid_contract", "target_crs", "transform_source", "transform_revision", "transform_license", "transform_sha256"):
        if crosswalk.get(key) is not None:
            raise ValueError(f"spatial crosswalk precondition {key} must remain unresolved")


def main() -> int:
    validate()
    print("spatial crosswalk origin evidence: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
