#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
from pathlib import Path

ROAD_AUTH_KEYS = (
    "collision_authorized",
    "jouable_authorized",
    "render_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
)
CELL_AUTH_KEYS = (
    "runtime_directory_scan_authorized",
    "road_crosswalk_authorized",
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)
ROW_AUTH_KEYS = (
    "runtime_mount_authorized",
    "rendered_geometry_authorized",
    "collision_authorized",
    "safe_spawn_authorized",
    "jouable_promotion_authorized",
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
LEGACY_CROSSWALK_PHASE = "ROAD_CELL_CROSSWALK_EVIDENCE_ONLY"
CORRECTED_CROSSWALK_PHASE = "CORRECTED_FRAME_ROAD_CELL_CROSSWALK_EVIDENCE_ONLY"


def _load(path: Path):
    if not path.is_file():
        raise RuntimeError(f"required evidence file missing: {path}")
    try:
        return json.loads(path.read_text())
    except Exception as exc:
        raise RuntimeError(f"invalid JSON: {path}") from exc


def _require_false(doc, keys, label):
    for key in keys:
        if doc.get(key) is not False:
            raise RuntimeError(f"{label} authorization must remain false: {key}")


def _require_all_authorizations_false(doc, label):
    if not isinstance(doc, dict):
        raise RuntimeError(f"{label} must be an object")
    for key, value in doc.items():
        if key.endswith("_authorized") and value is not False:
            raise RuntimeError(f"{label} authorization must remain false: {key}")


def _require_sha256(value, label):
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise RuntimeError(f"{label} SHA-256 missing or malformed")


def _resolve_registered_manifest(cell_index_path: Path, manifest_path: str) -> Path:
    if not isinstance(manifest_path, str) or not manifest_path:
        raise RuntimeError("registered-cell manifest path missing")
    relative = Path(manifest_path)
    if relative.is_absolute() or ".." in relative.parts:
        raise RuntimeError("registered-cell manifest path must stay repository-relative")
    repo_root = cell_index_path.resolve().parent.parent.parent
    resolved = (repo_root / relative).resolve()
    try:
        resolved.relative_to(repo_root)
    except ValueError as exc:
        raise RuntimeError("registered-cell manifest path escapes repository root") from exc
    return resolved


def _validate_registered_manifest(cell_index_path: Path, entry):
    manifest_sha = entry.get("manifest_sha256")
    _require_sha256(manifest_sha, "registered-cell manifest")
    manifest_path = _resolve_registered_manifest(cell_index_path, entry.get("manifest_path"))
    if not manifest_path.is_file():
        raise RuntimeError(f"registered-cell manifest missing: {manifest_path}")
    actual_sha = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    if actual_sha != manifest_sha:
        raise RuntimeError(
            f"registered-cell manifest SHA drift: {actual_sha} != {manifest_sha}"
        )
    manifest = _load(manifest_path)
    if manifest.get("format") != "grand-bruxelles-cell-maturity-v1":
        raise RuntimeError("unsupported registered-cell manifest format")
    cell_id = entry.get("cell_id")
    if manifest.get("cell_id") != cell_id:
        raise RuntimeError(f"registered-cell manifest identity drift: {cell_id}")
    if manifest.get("crs") != entry.get("crs"):
        raise RuntimeError(f"registered-cell manifest CRS drift: {cell_id}")
    if manifest.get("bbox") != entry.get("bbox"):
        raise RuntimeError(f"registered-cell manifest bbox drift: {cell_id}")
    maturity = manifest.get("maturity") or {}
    if maturity.get("state") != entry.get("maturity_state"):
        raise RuntimeError(f"registered-cell manifest maturity drift: {cell_id}")


def _validate_crosswalk_lifecycle(crosswalk):
    phase = crosswalk.get("destination_readiness")
    if phase == LEGACY_CROSSWALK_PHASE:
        return phase, set()
    if phase != CORRECTED_CROSSWALK_PHASE:
        raise RuntimeError(f"unsupported road-cell readiness lifecycle: {phase!r}")

    if crosswalk.get("mapping_policy") != "unique_source_coverage_cell_only_corrected_epsg31370":
        raise RuntimeError("corrected-frame crosswalk mapping policy drift")
    _require_sha256(crosswalk.get("corrected_frame_source_sha256"), "corrected-frame source")
    _require_sha256(crosswalk.get("corrected_frame_candidate_semantic_sha256"), "corrected-frame candidate semantic")

    hold = crosswalk.get("excluded_multicell_road_ids")
    if not isinstance(hold, list) or not hold:
        raise RuntimeError("corrected-frame multicell HOLD list missing")
    if any(not isinstance(road_id, int) or road_id <= 0 for road_id in hold):
        raise RuntimeError("invalid road id in corrected-frame multicell HOLD list")
    if len(set(hold)) != len(hold):
        raise RuntimeError("duplicate road id in corrected-frame multicell HOLD list")
    return phase, set(hold)


def validate_handshake(road_index_path: Path, cell_index_path: Path, crosswalk_path: Path):
    road_index_path = Path(road_index_path)
    cell_index_path = Path(cell_index_path)
    crosswalk_path = Path(crosswalk_path)
    road = _load(road_index_path)
    cells = _load(cell_index_path)
    crosswalk = _load(crosswalk_path)

    if road.get("format") != "grand-bruxelles-road-runtime-index-v1":
        raise RuntimeError("unsupported road index format")
    if road.get("source_lookup_only") is not True:
        raise RuntimeError("road index must remain source_lookup_only")
    road_auth = road.get("authorization") or {}
    if road_auth.get("source_lookup_only") is not True:
        raise RuntimeError("road index authorization must remain source_lookup_only")
    _require_false(road_auth, ROAD_AUTH_KEYS, "road index")
    _require_all_authorizations_false(road_auth, "road index")

    road_ids = set()
    for document in road.get("documents") or []:
        _require_sha256(document.get("sha256"), "road source document")
        for road_id in document.get("road_ids") or []:
            if not isinstance(road_id, int) or road_id <= 0:
                raise RuntimeError("invalid road id in source index")
            if road_id in road_ids:
                raise RuntimeError(f"duplicate road id in source index: {road_id}")
            road_ids.add(road_id)
    if not road_ids:
        raise RuntimeError("road source index is empty")

    if cells.get("schema") != "grand-bruxelles-registered-cell-manifest-index-v1":
        raise RuntimeError("unsupported registered-cell index schema")
    if cells.get("destination_readiness") != "REGISTERED_CELL_INDEX_EVIDENCE_ONLY":
        raise RuntimeError("registered-cell index readiness widened")
    _require_false(cells, CELL_AUTH_KEYS, "registered-cell index")
    _require_all_authorizations_false(cells, "registered-cell index")
    cell_ids = set()
    for entry in cells.get("entries") or []:
        cell_id = entry.get("cell_id")
        if not isinstance(cell_id, str) or not cell_id:
            raise RuntimeError("invalid registered cell id")
        if cell_id in cell_ids:
            raise RuntimeError(f"duplicate registered cell id: {cell_id}")
        if entry.get("evidence_only") is not True:
            raise RuntimeError(f"registered cell is not evidence-only: {cell_id}")
        _require_false(entry, ROW_AUTH_KEYS, f"registered cell {cell_id}")
        _require_all_authorizations_false(entry, f"registered cell {cell_id}")
        _validate_registered_manifest(cell_index_path, entry)
        cell_ids.add(cell_id)
    if len(cell_ids) != cells.get("registered_cell_count"):
        raise RuntimeError("registered-cell count mismatch")

    if crosswalk.get("schema") != "grand-bruxelles-road-registered-cell-crosswalk-v1":
        raise RuntimeError("unsupported road-cell crosswalk schema")
    phase, hold_road_ids = _validate_crosswalk_lifecycle(crosswalk)
    _require_false(crosswalk, (
        "runtime_directory_scan_authorized",
        "runtime_mount_authorized",
        "rendered_geometry_authorized",
        "collision_authorized",
        "safe_spawn_authorized",
        "jouable_promotion_authorized",
    ), "road-cell crosswalk")
    _require_all_authorizations_false(crosswalk, "road-cell crosswalk")

    seen_roads = set()
    mapped_cells = set()
    rows = crosswalk.get("rows") or []
    if not rows:
        raise RuntimeError("road-cell crosswalk has no explicit rows")
    for row in rows:
        road_id = row.get("road_osm_id")
        cell_id = row.get("cell_id")
        if road_id not in road_ids:
            raise RuntimeError(f"road is not in deterministic source index: {road_id}")
        if road_id in hold_road_ids:
            raise RuntimeError(f"multicell HOLD road leaked into unique mapping: {road_id}")
        if cell_id not in cell_ids:
            raise RuntimeError(f"cell is not in deterministic registered index: {cell_id}")
        if road_id in seen_roads:
            raise RuntimeError(f"road maps to more than one row: {road_id}")
        if row.get("mapping_evidence_only") is not True:
            raise RuntimeError(f"road-cell mapping is not evidence-only: {road_id}")
        _require_false(row, ROW_AUTH_KEYS, f"road-cell row {road_id}")
        _require_all_authorizations_false(row, f"road-cell row {road_id}")
        seen_roads.add(road_id)
        mapped_cells.add(cell_id)

    if crosswalk.get("mapped_road_count") not in (None, len(seen_roads)):
        raise RuntimeError("road-cell mapped road count drift")
    if crosswalk.get("mapped_cell_count") not in (None, len(mapped_cells)):
        raise RuntimeError("road-cell mapped cell count drift")

    return {
        "mapped_road_count": len(seen_roads),
        "mapped_cell_count": len(mapped_cells),
        "runtime_authorized": False,
        "destination_readiness": phase,
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--road-index", required=True)
    parser.add_argument("--cell-index", required=True)
    parser.add_argument("--crosswalk", required=True)
    args = parser.parse_args()
    result = validate_handshake(Path(args.road_index), Path(args.cell_index), Path(args.crosswalk))
    print(
        "ROAD_REGISTERED_CELL_HANDSHAKE_OK "
        f"roads={result['mapped_road_count']} cells={result['mapped_cell_count']} "
        f"phase={result['destination_readiness']} runtime_authorized=false"
    )


if __name__ == "__main__":
    main()
