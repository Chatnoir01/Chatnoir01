from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_evidence.lock.json"
RECEIPT_PATH = ROOT / "data/source_plans/brussels_spatial_crosswalk_origin_artifact_receipt.lock.json"

EXPECTED_EVIDENCE_SCHEMA = "grand-bruxelles-spatial-crosswalk-origin-evidence-v1"
EXPECTED_RECEIPT_SCHEMA = "grand-bruxelles-spatial-crosswalk-origin-artifact-receipt-v1"
EXPECTED_REPOSITORY = "Chatnoir01/Chatnoir01"
EXPECTED_OWNER = {
    "pr": 1562,
    "head_sha": "9fdbf01073deb311097bcc70e2e8b627a004a8b1",
    "workflow": "Grand Bruxelles City Machine Midi Runtime-Index Frame",
    "run_id": 34248313500,
    "artifact_id": 10065069360,
    "artifact_digest": "sha256:7c6dbd4e1ce3feeca476d60acfb147f97dd4cd43a0bc1063ca2d12059a230894",
    "artifact_name": "road-registered-cell-overlap-v2-candidate",
}
EXPECTED_MEASURED_CONTRACT = {
    "schema": "grand-bruxelles-road-registered-cell-overlap-measurement-v2",
    "cell_crs": "EPSG:31370",
    "frame": {
        "crs": "EPSG:31370",
        "origin_easting_m": 147868.29422791934,
        "origin_northing_m": 169538.62414926197,
        "formula": "E=origin_easting_m+x;N=origin_northing_m-z",
    },
    "registered_cell_index": "data/provenance/brussels_registered_cell_manifest_index.json",
    "registered_cell_index_semantic_sha256": "8dd6b8994160b7a22b83f8be4ce63cfa4b579f724d51b3896c0426782b259187",
    "road_runtime_index": "data/runtime/road_destination_runtime_index.json",
    "road_runtime_catalog_sha256": "7290b8272623e0cd5905224c8696d74a3015b1db9aab00ef19d1cf7676dea59f",
    "road_source": "data/osm/vertical_slice_01.game.json",
    "road_source_sha256": "899bc73ee0eea3623d7cc45455a542c1704039ef0239c13c33b3c74b4a241398",
    "road_source_provider": "OpenStreetMap contributors via Overpass API",
    "road_source_license": "ODbL-1.0",
    "raw_road_count": 140,
    "road_count": 139,
    "registered_cell_count": 5,
    "overlapping_road_count": 64,
    "semantic_sha256": "2d84dbc4d6a80e10f093f8135e2fba6e9b55b813eb42c2588be7566ae6c16f95",
}
EXPECTED_REGISTERED_CELL_ENTRIES = [
    ("bxl-e147500-n169500-s500", [147500.0, 169500.0, 148000.0, 170000.0], "data/cell_manifests/bxl-e147500-n169500-s500.json", "3ec056c3c7c8d6ecb6ca5da35a8f6a685fbb14ef9b130065c85cc511b26b7e2a"),
    ("bxl-e147500-n170000-s500", [147500.0, 170000.0, 148000.0, 170500.0], "data/cell_manifests/bxl-e147500-n170000-s500.json", "fc91d05e7a4db947edb72223f6604647a551aa9e468e82fe49d1975542dcd6a7"),
    ("bxl-e148000-n170000-s500", [148000.0, 170000.0, 148500.0, 170500.0], "data/cell_manifests/bxl-e148000-n170000-s500.json", "53cac9ef1e281b0971dc7bad44be378f8e8392cca753f9f6c2cdafa45dfddb37"),
    ("bxl-e148500-n170500-s500", [148500.0, 170500.0, 149000.0, 171000.0], "data/cell_manifests/bxl-e148500-n170500-s500.json", "ce3309947aa29fa50cf3c9b11e1a81189bf04682e68576fecd8732a3d2d2dafe"),
    ("bxl-e149000-n169000-s500", [149000.0, 169000.0, 149500.0, 169500.0], "data/cell_manifests/bxl-e149000-n169000-s500.json", "67409472171b260692f3495756c77839df79a02f05271e794f6b7db1168753cd"),
]
EXPECTED_ARTIFACT_SIZE = 2473
EXPECTED_REGISTERED_PRODUCTION_BASE_SHA = "49c62bbce71b1461da948777339e0f4d7cd101d6"
EXPECTED_EVIDENCE_SCOPE_NOTE = "Pinned measured origin/CRS/grid evidence from #1562 for Data provenance intake only. This receipt does not identify municipality road artifacts, authorize OSM-to-UrbIS semantics, assign cells, mount runtime geometry, or promote JOUABLE."
EXPECTED_RECEIPT_SCOPE_NOTE = "Immutable receipt of the exact #1562 workflow artifact metadata independently re-verified through GitHub Actions. This receipt proves artifact identity only; it does not authorize source semantics, cell assignment, runtime mounting, collision, spawn safety or JOUABLE promotion."
EXPECTED_EVIDENCE_KEYS = {"schema", "source_owner", "measured_contract", "authorization", "scope_note"}
EXPECTED_OWNER_KEYS = {"pr", "head_sha", "workflow", "run_id", "artifact_id", "artifact_digest", "artifact_name"}
EXPECTED_MEASURED_CONTRACT_KEYS = set(EXPECTED_MEASURED_CONTRACT)
EXPECTED_FRAME_KEYS = set(EXPECTED_MEASURED_CONTRACT["frame"])
EXPECTED_RECEIPT_KEYS = {"schema", "repository", "workflow_run", "artifact", "authorization", "scope_note"}
EXPECTED_RUN_KEYS = {"id", "head_sha"}
EXPECTED_ARTIFACT_KEYS = {"id", "name", "size_in_bytes", "digest"}
EXPECTED_AUTHORIZATION_KEYS = {
    "crosswalk_authorized", "road_cell_mapping_authorized", "runtime_mount_authorized",
    "rendered_geometry_authorized", "collision_authorized", "safe_spawn_authorized",
    "jouable_promotion_authorized",
}
EXPECTED_RUNTIME_KEYS = {"authorization", "catalog_sha256", "documents", "format", "source_lookup_only"}
EXPECTED_RUNTIME_AUTHORIZATION_KEYS = {
    "collision_authorized", "jouable_authorized", "render_authorized", "runtime_mount_authorized",
    "safe_spawn_authorized", "source_lookup_only",
}
EXPECTED_RUNTIME_DOCUMENT_KEYS = {"path", "road_ids", "sha256"}
EXPECTED_REGISTERED_INDEX_KEYS = {
    "collision_authorized", "destination_readiness", "entries", "jouable_promotion_authorized",
    "production_base_sha", "registered_cell_count", "rendered_geometry_authorized",
    "road_crosswalk_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized",
    "safe_spawn_authorized", "schema", "semantic_sha256",
}
EXPECTED_REGISTERED_ENTRY_KEYS = {
    "bbox", "cell_id", "collision_authorized", "crs", "evidence_only",
    "jouable_promotion_authorized", "manifest_path", "manifest_sha256", "maturity_state",
    "rendered_geometry_authorized", "runtime_mount_authorized", "safe_spawn_authorized",
}
LOWER_HEX_40 = re.compile(r"^[0-9a-f]{40}$")
SHA256_DIGEST = re.compile(r"^sha256:[0-9a-f]{64}$")
LOWER_HEX_64 = re.compile(r"^[0-9a-f]{64}$")


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    for key, value in pairs:
        if key in payload:
            raise ValueError(f"duplicate JSON key: {key}")
        payload[key] = value
    return payload


def _load_json_strict(raw: bytes, label: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8"), object_pairs_hook=_reject_duplicate_pairs)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not valid UTF-8 JSON") from exc


def _require_exact_keys(value: Any, expected: set[str], label: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != expected:
        raise ValueError(f"{label} schema drift")
    return value


def _require_closed_authorization(value: Any, label: str) -> None:
    authorization = _require_exact_keys(value, EXPECTED_AUTHORIZATION_KEYS, label)
    for key, state in authorization.items():
        if type(state) is not bool or state is not False:
            raise ValueError(f"{label}.{key} must remain false")


def _require_scope_note(value: Any, expected: str, label: str) -> None:
    if not isinstance(value, str) or value != expected:
        raise ValueError(f"{label} immutable semantics drift")


def _require_measured_contract(value: Any) -> None:
    measured = _require_exact_keys(value, EXPECTED_MEASURED_CONTRACT_KEYS, "origin evidence measured_contract")
    _require_exact_keys(measured["frame"], EXPECTED_FRAME_KEYS, "origin evidence measured_contract.frame")
    if measured != EXPECTED_MEASURED_CONTRACT:
        raise ValueError("origin evidence measured_contract immutable identity drift")


def _require_road_source_bytes(road_source_raw: bytes) -> set[int]:
    actual = hashlib.sha256(road_source_raw).hexdigest()
    expected = EXPECTED_MEASURED_CONTRACT["road_source_sha256"]
    if actual != expected:
        raise ValueError("origin evidence road_source_sha256 does not match repository bytes")
    source = _load_json_strict(road_source_raw, "origin evidence road source")
    if not isinstance(source, dict) or source.get("source") != EXPECTED_MEASURED_CONTRACT["road_source_provider"]:
        raise ValueError("origin evidence road source provider drift")
    if source.get("license") != EXPECTED_MEASURED_CONTRACT["road_source_license"]:
        raise ValueError("origin evidence road source license drift")
    roads = source.get("roads")
    if not isinstance(roads, list) or len(roads) != EXPECTED_MEASURED_CONTRACT["raw_road_count"]:
        raise ValueError("origin evidence raw road accounting drift")
    road_ids: list[int] = []
    for road in roads:
        if not isinstance(road, dict) or type(road.get("osm_id")) is not int or road["osm_id"] <= 0:
            raise ValueError("origin evidence road source contains invalid OSM road identity")
        road_ids.append(road["osm_id"])
    if len(set(road_ids)) != len(road_ids):
        raise ValueError("origin evidence road source contains duplicate OSM road identity")
    return set(road_ids)


def _require_runtime_index_bytes(runtime_index_raw: bytes, source_road_ids: set[int]) -> None:
    runtime = _load_json_strict(runtime_index_raw, "origin evidence road runtime index")
    runtime = _require_exact_keys(runtime, EXPECTED_RUNTIME_KEYS, "origin evidence road runtime index")
    if runtime["format"] != "grand-bruxelles-road-runtime-index-v1":
        raise ValueError("origin evidence road runtime index format drift")
    if runtime["source_lookup_only"] is not True:
        raise ValueError("origin evidence road runtime index must remain source-lookup-only")
    if runtime["catalog_sha256"] != EXPECTED_MEASURED_CONTRACT["road_runtime_catalog_sha256"]:
        raise ValueError("origin evidence road runtime catalog digest drift")
    authorization = _require_exact_keys(runtime["authorization"], EXPECTED_RUNTIME_AUTHORIZATION_KEYS, "origin evidence road runtime index authorization")
    for key, state in authorization.items():
        expected = True if key == "source_lookup_only" else False
        if type(state) is not bool or state is not expected:
            raise ValueError(f"origin evidence road runtime index authorization.{key} drift")
    documents = runtime["documents"]
    if not isinstance(documents, list) or len(documents) != 1:
        raise ValueError("origin evidence road runtime index document accounting drift")
    document = _require_exact_keys(documents[0], EXPECTED_RUNTIME_DOCUMENT_KEYS, "origin evidence road runtime index document")
    if document["path"] != EXPECTED_MEASURED_CONTRACT["road_source"]:
        raise ValueError("origin evidence road runtime index source path drift")
    if document["sha256"] != EXPECTED_MEASURED_CONTRACT["road_source_sha256"]:
        raise ValueError("origin evidence road runtime index source digest drift")
    road_ids = document["road_ids"]
    if not isinstance(road_ids, list) or len(road_ids) != EXPECTED_MEASURED_CONTRACT["road_count"]:
        raise ValueError("origin evidence road runtime index road accounting drift")
    if any(type(road_id) is not int or road_id <= 0 for road_id in road_ids):
        raise ValueError("origin evidence road runtime index contains invalid OSM road identity")
    if road_ids != sorted(road_ids) or len(set(road_ids)) != len(road_ids):
        raise ValueError("origin evidence road runtime index road identities must remain unique and sorted")
    if not set(road_ids).issubset(source_road_ids):
        raise ValueError("origin evidence road runtime index contains road identity absent from locked OSM source")


def _require_registered_cell_index_bytes(registered_index_raw: bytes) -> None:
    index = _load_json_strict(registered_index_raw, "origin evidence registered cell index")
    index = _require_exact_keys(index, EXPECTED_REGISTERED_INDEX_KEYS, "origin evidence registered cell index")
    if index["schema"] != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise ValueError("origin evidence registered cell index schema drift")
    if index["semantic_sha256"] != EXPECTED_MEASURED_CONTRACT["registered_cell_index_semantic_sha256"]:
        raise ValueError("origin evidence registered cell index semantic digest drift")
    if index["destination_readiness"] != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise ValueError("origin evidence registered cell index readiness drift")
    if index["registered_cell_count"] != EXPECTED_MEASURED_CONTRACT["registered_cell_count"]:
        raise ValueError("origin evidence registered cell count drift")
    if LOWER_HEX_40.fullmatch(index["production_base_sha"]) is None:
        raise ValueError("origin evidence registered cell index production_base_sha must be lowercase Git SHA-1")
    if index["production_base_sha"] != EXPECTED_REGISTERED_PRODUCTION_BASE_SHA:
        raise ValueError("origin evidence registered cell index production_base_sha repin")
    for key in (
        "collision_authorized", "jouable_promotion_authorized", "rendered_geometry_authorized",
        "road_crosswalk_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized",
        "safe_spawn_authorized",
    ):
        if type(index[key]) is not bool or index[key] is not False:
            raise ValueError(f"origin evidence registered cell index {key} must remain false")
    entries = index["entries"]
    if not isinstance(entries, list) or len(entries) != len(EXPECTED_REGISTERED_CELL_ENTRIES):
        raise ValueError("origin evidence registered cell entry accounting drift")
    for entry, expected in zip(entries, EXPECTED_REGISTERED_CELL_ENTRIES, strict=True):
        entry = _require_exact_keys(entry, EXPECTED_REGISTERED_ENTRY_KEYS, "origin evidence registered cell entry")
        cell_id, bbox, manifest_path, manifest_sha256 = expected
        if entry["cell_id"] != cell_id or entry["bbox"] != bbox or entry["crs"] != "EPSG:31370":
            raise ValueError("origin evidence registered cell identity/frame drift")
        if entry["manifest_path"] != manifest_path or entry["manifest_sha256"] != manifest_sha256:
            raise ValueError("origin evidence registered cell manifest identity drift")
        if LOWER_HEX_64.fullmatch(entry["manifest_sha256"]) is None:
            raise ValueError("origin evidence registered cell manifest digest format drift")
        if entry["maturity_state"] != "data_ready" or entry["evidence_only"] is not True:
            raise ValueError("origin evidence registered cell maturity/readiness drift")
        for key in (
            "collision_authorized", "jouable_promotion_authorized", "rendered_geometry_authorized",
            "runtime_mount_authorized", "safe_spawn_authorized",
        ):
            if type(entry[key]) is not bool or entry[key] is not False:
                raise ValueError(f"origin evidence registered cell entry {key} must remain false")
        manifest_raw = (ROOT / manifest_path).read_bytes()
        if hashlib.sha256(manifest_raw).hexdigest() != manifest_sha256:
            raise ValueError("origin evidence registered cell manifest bytes drift")
        manifest = _load_json_strict(manifest_raw, f"origin evidence cell manifest {cell_id}")
        if not isinstance(manifest, dict):
            raise ValueError("origin evidence cell manifest shape drift")
        if manifest.get("cell_id") != cell_id or manifest.get("bbox") != bbox or manifest.get("crs") != "EPSG:31370":
            raise ValueError("origin evidence cell manifest identity/frame mismatch")
        maturity = manifest.get("maturity")
        if not isinstance(maturity, dict) or maturity.get("state") != "data_ready":
            raise ValueError("origin evidence cell manifest maturity mismatch")


def validate_origin_artifact_receipt(
    evidence_raw: bytes,
    receipt_raw: bytes,
    road_source_raw: bytes | None = None,
    runtime_index_raw: bytes | None = None,
    registered_cell_index_raw: bytes | None = None,
) -> None:
    evidence = _load_json_strict(evidence_raw, "origin evidence")
    receipt = _load_json_strict(receipt_raw, "origin artifact receipt")
    evidence = _require_exact_keys(evidence, EXPECTED_EVIDENCE_KEYS, "origin evidence")
    receipt = _require_exact_keys(receipt, EXPECTED_RECEIPT_KEYS, "origin artifact receipt")
    if evidence["schema"] != EXPECTED_EVIDENCE_SCHEMA:
        raise ValueError("origin evidence schema drift")
    if receipt["schema"] != EXPECTED_RECEIPT_SCHEMA:
        raise ValueError("origin artifact receipt schema drift")
    if receipt["repository"] != EXPECTED_REPOSITORY:
        raise ValueError("origin artifact receipt repository drift")
    owner = _require_exact_keys(evidence["source_owner"], EXPECTED_OWNER_KEYS, "origin evidence source_owner")
    if owner != EXPECTED_OWNER:
        raise ValueError("origin evidence source_owner immutable identity drift")
    if LOWER_HEX_40.fullmatch(owner["head_sha"]) is None:
        raise ValueError("origin evidence source_owner.head_sha must be lowercase Git SHA-1")
    if SHA256_DIGEST.fullmatch(owner["artifact_digest"]) is None:
        raise ValueError("origin evidence source_owner.artifact_digest must be sha256:<lowerhex64>")
    _require_measured_contract(evidence["measured_contract"])
    if road_source_raw is None:
        road_source_raw = (ROOT / EXPECTED_MEASURED_CONTRACT["road_source"]).read_bytes()
    source_road_ids = _require_road_source_bytes(road_source_raw)
    if runtime_index_raw is None:
        runtime_index_raw = (ROOT / EXPECTED_MEASURED_CONTRACT["road_runtime_index"]).read_bytes()
    _require_runtime_index_bytes(runtime_index_raw, source_road_ids)
    if registered_cell_index_raw is None:
        registered_cell_index_raw = (ROOT / EXPECTED_MEASURED_CONTRACT["registered_cell_index"]).read_bytes()
    _require_registered_cell_index_bytes(registered_cell_index_raw)
    run = _require_exact_keys(receipt["workflow_run"], EXPECTED_RUN_KEYS, "origin artifact receipt workflow_run")
    artifact = _require_exact_keys(receipt["artifact"], EXPECTED_ARTIFACT_KEYS, "origin artifact receipt artifact")
    expected_run = {"id": EXPECTED_OWNER["run_id"], "head_sha": EXPECTED_OWNER["head_sha"]}
    expected_artifact = {
        "id": EXPECTED_OWNER["artifact_id"], "name": EXPECTED_OWNER["artifact_name"],
        "size_in_bytes": EXPECTED_ARTIFACT_SIZE, "digest": EXPECTED_OWNER["artifact_digest"],
    }
    if run != expected_run or artifact != expected_artifact:
        raise ValueError("origin artifact receipt does not match source_owner")
    _require_closed_authorization(evidence["authorization"], "origin evidence authorization")
    _require_closed_authorization(receipt["authorization"], "origin artifact receipt authorization")
    _require_scope_note(evidence["scope_note"], EXPECTED_EVIDENCE_SCOPE_NOTE, "origin evidence scope_note")
    _require_scope_note(receipt["scope_note"], EXPECTED_RECEIPT_SCOPE_NOTE, "origin artifact receipt scope_note")


def main() -> int:
    validate_origin_artifact_receipt(EVIDENCE_PATH.read_bytes(), RECEIPT_PATH.read_bytes())
    print("spatial crosswalk origin artifact receipt: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
