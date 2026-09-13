#!/usr/bin/env python3
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
import re
from pathlib import Path, PurePosixPath
from typing import Any

EXPECTED_SCHEMA = "grand-bruxelles-road-destination-readiness-catalog-v1"
ROOT_HASH_FIELDS = (
    "corrected_frame_candidate_semantic_sha256",
    "corrected_frame_source_sha256",
    "registered_cell_index_semantic_sha256",
    "road_cell_crosswalk_semantic_sha256",
    "road_runtime_catalog_sha256",
    "semantic_sha256",
)
ROW_HASH_FIELDS = (
    "cell_manifest_sha256",
    "source_points_sha256",
    "source_sha256",
)
SHA256_RE = re.compile(r"^[0-9a-f]{64}$")


def _strict_object(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for key, value in pairs:
        if key in out:
            raise ValueError(f"duplicate JSON key: {key}")
        out[key] = value
    return out


def _finite_float(value: str) -> float:
    parsed = float(value)
    if not math.isfinite(parsed):
        raise ValueError(f"non-finite JSON number: {value}")
    return parsed


def _load_strict_json(path: Path) -> Any:
    return json.loads(
        path.read_text(encoding="utf-8"),
        object_pairs_hook=_strict_object,
        parse_float=_finite_float,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"non-finite JSON number: {value}")),
    )


def load_catalog(path: Path) -> dict[str, Any]:
    parsed = _load_strict_json(path)
    if not isinstance(parsed, dict):
        raise ValueError("catalog root must be an object")
    return parsed


def _require_sha256(value: Any, label: str) -> str:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        raise ValueError(f"{label} must be canonical lowercase 64-hex SHA-256")
    return value


def _canonical_repo_path(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value or value != value.strip() or "\\" in value:
        raise ValueError(f"{label} must be a canonical repository-relative POSIX path")
    pure = PurePosixPath(value)
    if pure.is_absolute() or any(part in {".", ".."} for part in pure.parts) or str(pure) != value:
        raise ValueError(f"{label} must be a canonical repository-relative POSIX path")
    return value


def _resolve_repo_file(root: Path, relative_path: str) -> Path:
    root_resolved = root.resolve()
    candidate = (root_resolved / relative_path).resolve()
    try:
        candidate.relative_to(root_resolved)
    except ValueError as exc:
        raise ValueError(f"file path escapes repository root: {relative_path}") from exc
    if not candidate.is_file():
        raise ValueError(f"referenced file does not exist: {relative_path}")
    return candidate


def _sha256_file(root: Path, relative_path: str, cache: dict[str, str]) -> str:
    if relative_path in cache:
        return cache[relative_path]
    candidate = _resolve_repo_file(root, relative_path)
    digest = hashlib.sha256(candidate.read_bytes()).hexdigest()
    cache[relative_path] = digest
    return digest


def _source_roads_by_id(root: Path, relative_path: str, cache: dict[str, dict[int, dict[str, Any]]]) -> dict[int, dict[str, Any]]:
    if relative_path in cache:
        return cache[relative_path]
    candidate = _resolve_repo_file(root, relative_path)
    parsed = _load_strict_json(candidate)
    if not isinstance(parsed, dict):
        raise ValueError(f"source root must be an object: {relative_path}")
    roads = parsed.get("roads")
    if not isinstance(roads, list):
        raise ValueError(f"source roads must be an array: {relative_path}")
    by_id: dict[int, dict[str, Any]] = {}
    for source_index, road in enumerate(roads):
        if not isinstance(road, dict):
            raise ValueError(f"source road {source_index} must be an object: {relative_path}")
        osm_id = road.get("osm_id")
        if isinstance(osm_id, bool) or not isinstance(osm_id, int) or osm_id <= 0:
            raise ValueError(f"source road {source_index}.osm_id must be a positive integer: {relative_path}")
        if osm_id in by_id:
            raise ValueError(f"duplicate source road osm_id={osm_id}: {relative_path}")
        by_id[osm_id] = road
    cache[relative_path] = by_id
    return by_id


def _canonical_points_sha256(points: Any, label: str) -> str:
    if not isinstance(points, list) or not points:
        raise ValueError(f"{label} must be a non-empty points array")
    for point_index, point in enumerate(points):
        if not isinstance(point, list) or len(point) != 2:
            raise ValueError(f"{label}[{point_index}] must be a 2D point")
        for axis_index, value in enumerate(point):
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(float(value)):
                raise ValueError(f"{label}[{point_index}][{axis_index}] must be finite numeric")
    canonical = json.dumps(points, ensure_ascii=False, separators=(",", ":"), allow_nan=False).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def validate(catalog: dict[str, Any], *, root: Path | None = None) -> tuple[int, int]:
    if catalog.get("schema") != EXPECTED_SCHEMA:
        raise ValueError("unexpected catalog schema")

    for field in ROOT_HASH_FIELDS:
        _require_sha256(catalog.get(field), field)

    rows = catalog.get("destinations")
    if not isinstance(rows, list) or not rows:
        raise ValueError("catalog destinations missing")

    file_hash_cache: dict[str, str] = {}
    source_roads_cache: dict[str, dict[int, dict[str, Any]]] = {}
    row_hash_count = 0
    for index, row in enumerate(rows):
        if not isinstance(row, dict):
            raise ValueError(f"destination row {index} must be an object")
        for field in ROW_HASH_FIELDS:
            _require_sha256(row.get(field), f"destination row {index}.{field}")
            row_hash_count += 1

        if root is not None:
            source_path = _canonical_repo_path(row.get("source_path"), f"destination row {index}.source_path")
            manifest_path = _canonical_repo_path(
                row.get("cell_manifest_path"), f"destination row {index}.cell_manifest_path"
            )
            actual_source_hash = _sha256_file(root, source_path, file_hash_cache)
            if row["source_sha256"] != actual_source_hash:
                raise ValueError(
                    f"destination row {index}.source_sha256 does not match bytes at {source_path}"
                )
            actual_manifest_hash = _sha256_file(root, manifest_path, file_hash_cache)
            if row["cell_manifest_sha256"] != actual_manifest_hash:
                raise ValueError(
                    f"destination row {index}.cell_manifest_sha256 does not match bytes at {manifest_path}"
                )

            road_osm_id = row.get("road_osm_id")
            if isinstance(road_osm_id, bool) or not isinstance(road_osm_id, int) or road_osm_id <= 0:
                raise ValueError(f"destination row {index}.road_osm_id must be a positive integer")
            source_road = _source_roads_by_id(root, source_path, source_roads_cache).get(road_osm_id)
            if source_road is None:
                raise ValueError(
                    f"destination row {index}.road_osm_id={road_osm_id} missing from source roads at {source_path}"
                )
            actual_points_hash = _canonical_points_sha256(
                source_road.get("points"), f"source road osm_id={road_osm_id}.points"
            )
            if row["source_points_sha256"] != actual_points_hash:
                raise ValueError(
                    f"destination row {index}.source_points_sha256 does not match road osm_id={road_osm_id} points"
                )

    return len(ROOT_HASH_FIELDS), row_hash_count


def self_test(catalog: dict[str, Any], *, root: Path | None = None) -> None:
    validate(catalog, root=root)
    cases: list[tuple[str, dict[str, Any]]] = []

    root_short = copy.deepcopy(catalog)
    root_short[ROOT_HASH_FIELDS[0]] = "0" * 63
    cases.append(("short root hash", root_short))

    root_upper = copy.deepcopy(catalog)
    root_upper[ROOT_HASH_FIELDS[0]] = "A" * 64
    cases.append(("uppercase root hash", root_upper))

    root_nonhex = copy.deepcopy(catalog)
    root_nonhex[ROOT_HASH_FIELDS[0]] = "g" * 64
    cases.append(("non-hex root hash", root_nonhex))

    root_bool = copy.deepcopy(catalog)
    root_bool[ROOT_HASH_FIELDS[0]] = False
    cases.append(("boolean root hash", root_bool))

    row_empty = copy.deepcopy(catalog)
    row_empty["destinations"][0][ROW_HASH_FIELDS[0]] = ""
    cases.append(("empty row hash", row_empty))

    row_upper = copy.deepcopy(catalog)
    row_upper["destinations"][0][ROW_HASH_FIELDS[1]] = "B" * 64
    cases.append(("uppercase row hash", row_upper))

    row_nonhex = copy.deepcopy(catalog)
    row_nonhex["destinations"][0][ROW_HASH_FIELDS[2]] = "z" * 64
    cases.append(("non-hex row hash", row_nonhex))

    if root is not None:
        source_file_drift = copy.deepcopy(catalog)
        source_file_drift["destinations"][0]["source_sha256"] = "0" * 64
        cases.append(("valid-format source file hash drift", source_file_drift))

        manifest_file_drift = copy.deepcopy(catalog)
        manifest_file_drift["destinations"][0]["cell_manifest_sha256"] = "1" * 64
        cases.append(("valid-format manifest file hash drift", manifest_file_drift))

        source_points_drift = copy.deepcopy(catalog)
        source_points_drift["destinations"][0]["source_points_sha256"] = "2" * 64
        cases.append(("valid-format source points hash drift", source_points_drift))

    for label, candidate in cases:
        try:
            validate(candidate, root=root)
        except ValueError:
            continue
        raise AssertionError(f"{label} mutation was accepted")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("catalog", type=Path)
    parser.add_argument("--root", type=Path, default=None)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    catalog = load_catalog(args.catalog)
    root_hashes, row_hashes = validate(catalog, root=args.root)
    if args.self_test:
        self_test(catalog, root=args.root)

    print(
        "ROAD_DESTINATION_READINESS_HASH_IDENTITY_OK "
        f"root_hashes={root_hashes} row_hashes={row_hashes} "
        "canonical_sha256_format=true lowercase_hex_required=true "
        f"source_file_hash_bound={str(args.root is not None).lower()} "
        f"cell_manifest_hash_bound={str(args.root is not None).lower()} "
        f"source_points_hash_bound={str(args.root is not None).lower()} "
        f"self_test={str(args.self_test).lower()} hash_identity_fail_closed=true"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
