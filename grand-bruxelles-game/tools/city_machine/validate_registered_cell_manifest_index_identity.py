from __future__ import annotations

import hashlib
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
INDEX_PATH = ROOT / "data/provenance/brussels_registered_cell_manifest_index.json"
EXPECTED_SEMANTIC_SHA256 = "8dd6b8994160b7a22b83f8be4ce63cfa4b579f724d51b3896c0426782b259187"
EXPECTED_PRODUCTION_BASE_SHA = "49c62bbce71b1461da948777339e0f4d7cd101d6"
EXPECTED_ENTRIES = [
    ("bxl-e147500-n169500-s500", [147500.0, 169500.0, 148000.0, 170000.0], "data/cell_manifests/bxl-e147500-n169500-s500.json", "3ec056c3c7c8d6ecb6ca5da35a8f6a685fbb14ef9b130065c85cc511b26b7e2a"),
    ("bxl-e147500-n170000-s500", [147500.0, 170000.0, 148000.0, 170500.0], "data/cell_manifests/bxl-e147500-n170000-s500.json", "fc91d05e7a4db947edb72223f6604647a551aa9e468e82fe49d1975542dcd6a7"),
    ("bxl-e148000-n170000-s500", [148000.0, 170000.0, 148500.0, 170500.0], "data/cell_manifests/bxl-e148000-n170000-s500.json", "53cac9ef1e281b0971dc7bad44be378f8e8392cca753f9f6c2cdafa45dfddb37"),
    ("bxl-e148500-n170500-s500", [148500.0, 170500.0, 149000.0, 171000.0], "data/cell_manifests/bxl-e148500-n170500-s500.json", "ce3309947aa29fa50cf3c9b11e1a81189bf04682e68576fecd8732a3d2d2dafe"),
    ("bxl-e149000-n169000-s500", [149000.0, 169000.0, 149500.0, 169500.0], "data/cell_manifests/bxl-e149000-n169000-s500.json", "67409472171b260692f3495756c77839df79a02f05271e794f6b7db1168753cd"),
]
INDEX_KEYS = {
    "collision_authorized", "destination_readiness", "entries", "jouable_promotion_authorized",
    "production_base_sha", "registered_cell_count", "rendered_geometry_authorized",
    "road_crosswalk_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized",
    "safe_spawn_authorized", "schema", "semantic_sha256",
}
ENTRY_KEYS = {
    "bbox", "cell_id", "collision_authorized", "crs", "evidence_only",
    "jouable_promotion_authorized", "manifest_path", "manifest_sha256", "maturity_state",
    "rendered_geometry_authorized", "runtime_mount_authorized", "safe_spawn_authorized",
}
CLOSED_INDEX_KEYS = {
    "collision_authorized", "jouable_promotion_authorized", "rendered_geometry_authorized",
    "road_crosswalk_authorized", "runtime_directory_scan_authorized", "runtime_mount_authorized",
    "safe_spawn_authorized",
}
CLOSED_ENTRY_KEYS = {
    "collision_authorized", "jouable_promotion_authorized", "rendered_geometry_authorized",
    "runtime_mount_authorized", "safe_spawn_authorized",
}


def _reject_duplicate_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    payload: dict[str, Any] = {}
    for key, value in pairs:
        if key in payload:
            raise ValueError(f"duplicate JSON key: {key}")
        payload[key] = value
    return payload


def _reject_nonstandard_constant(value: str) -> Any:
    raise ValueError(f"non-standard JSON constant: {value}")


def _load(raw: bytes, label: str) -> Any:
    try:
        return json.loads(
            raw.decode("utf-8"),
            object_pairs_hook=_reject_duplicate_pairs,
            parse_constant=_reject_nonstandard_constant,
        )
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{label} is not strict UTF-8 JSON") from exc


def validate_registered_cell_manifest_index_identity(index_raw: bytes) -> None:
    index = _load(index_raw, "registered cell manifest index")
    if not isinstance(index, dict) or set(index) != INDEX_KEYS:
        raise ValueError("registered cell manifest index schema drift")
    if index["schema"] != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise ValueError("registered cell manifest index schema identity drift")
    if index["semantic_sha256"] != EXPECTED_SEMANTIC_SHA256:
        raise ValueError("registered cell manifest index semantic digest drift")
    if index["production_base_sha"] != EXPECTED_PRODUCTION_BASE_SHA:
        raise ValueError("registered cell manifest index production base drift")
    if index["destination_readiness"] != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise ValueError("registered cell manifest index readiness drift")
    if type(index["registered_cell_count"]) is not int or index["registered_cell_count"] != len(EXPECTED_ENTRIES):
        raise ValueError("registered cell manifest index count drift")
    for key in CLOSED_INDEX_KEYS:
        if type(index[key]) is not bool or index[key] is not False:
            raise ValueError(f"registered cell manifest index {key} must remain false")

    entries = index["entries"]
    if not isinstance(entries, list) or len(entries) != len(EXPECTED_ENTRIES):
        raise ValueError("registered cell manifest entry accounting drift")
    for entry, expected in zip(entries, EXPECTED_ENTRIES, strict=True):
        if not isinstance(entry, dict) or set(entry) != ENTRY_KEYS:
            raise ValueError("registered cell manifest entry schema drift")
        cell_id, bbox, manifest_path, manifest_sha256 = expected
        if entry["cell_id"] != cell_id or entry["bbox"] != bbox or entry["crs"] != "EPSG:31370":
            raise ValueError("registered cell manifest entry identity/frame drift")
        if entry["manifest_path"] != manifest_path or entry["manifest_sha256"] != manifest_sha256:
            raise ValueError("registered cell manifest entry source identity drift")
        if entry["maturity_state"] != "data_ready" or entry["evidence_only"] is not True:
            raise ValueError("registered cell manifest entry maturity drift")
        for key in CLOSED_ENTRY_KEYS:
            if type(entry[key]) is not bool or entry[key] is not False:
                raise ValueError(f"registered cell manifest entry {cell_id}.{key} must remain false")

        manifest_raw = (ROOT / manifest_path).read_bytes()
        if hashlib.sha256(manifest_raw).hexdigest() != manifest_sha256:
            raise ValueError(f"registered cell manifest bytes drift: {cell_id}")
        manifest = _load(manifest_raw, f"registered cell manifest {cell_id}")
        if not isinstance(manifest, dict):
            raise ValueError(f"registered cell manifest shape drift: {cell_id}")
        if manifest.get("cell_id") != cell_id or manifest.get("bbox") != bbox or manifest.get("crs") != "EPSG:31370":
            raise ValueError(f"registered cell manifest identity/frame mismatch: {cell_id}")
        maturity = manifest.get("maturity")
        if not isinstance(maturity, dict) or maturity.get("state") != "data_ready":
            raise ValueError(f"registered cell manifest maturity mismatch: {cell_id}")


def main() -> int:
    validate_registered_cell_manifest_index_identity(INDEX_PATH.read_bytes())
    print("registered cell manifest index identity: OK (5 exact EPSG:31370 cells / authorization CLOSED)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
