#!/usr/bin/env python3
import argparse
import hashlib
import json
import re
from pathlib import Path

HEX64 = re.compile(r"^[0-9a-f]{64}$")
MAX_EXACT_JSON_INTEGER = 9007199254740991
FORBIDDEN_AUTH = (
    "render_authorized",
    "collision_authorized",
    "runtime_mount_authorized",
    "safe_spawn_authorized",
    "jouable_authorized",
)


class ValidationError(RuntimeError):
    pass


def exact_osm_id(value):
    if isinstance(value, bool) or not isinstance(value, int):
        raise ValidationError(f"OSM id is not an exact JSON integer: {value!r}")
    if value <= 0 or value > MAX_EXACT_JSON_INTEGER:
        raise ValidationError(f"OSM id out of exact range: {value!r}")
    return value


def load_json(path: Path):
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ValidationError(f"cannot parse {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise ValidationError(f"top-level JSON must be an object: {path}")
    return value


def resolve_source(root: Path, raw_path):
    if not isinstance(raw_path, str) or not raw_path.strip():
        raise ValidationError("descriptor path must be a non-empty string")
    text = raw_path.strip()
    if text.startswith("res://"):
        text = text[len("res://"):]
    candidate = (root / text).resolve()
    try:
        candidate.relative_to(root)
    except ValueError as exc:
        raise ValidationError(f"source path escapes project root: {raw_path!r}") from exc
    if not candidate.is_file():
        raise ValidationError(f"source document missing: {raw_path!r}")
    return candidate


def validate(root: Path, index_path: Path):
    root = root.resolve()
    index_path = index_path.resolve()
    index = load_json(index_path)
    if index.get("format") != "grand-bruxelles-road-runtime-index-v1":
        raise ValidationError("unexpected runtime-index format")
    if index.get("source_lookup_only") is not True:
        raise ValidationError("runtime index must remain source_lookup_only=true")
    auth = index.get("authorization")
    if not isinstance(auth, dict) or auth.get("source_lookup_only") is not True:
        raise ValidationError("authorization.source_lookup_only must be true")
    for key in FORBIDDEN_AUTH:
        if auth.get(key) is not False:
            raise ValidationError(f"authorization.{key} must remain false")

    documents = index.get("documents")
    if not isinstance(documents, list) or not documents:
        raise ValidationError("documents must be a non-empty array")

    indexed_global = set()
    source_paths = set()
    source_document_count = 0
    for descriptor in documents:
        if not isinstance(descriptor, dict):
            raise ValidationError("document descriptor must be an object")
        source = resolve_source(root, descriptor.get("path"))
        if source in source_paths:
            raise ValidationError(f"duplicate source descriptor: {source}")
        source_paths.add(source)

        expected_sha = descriptor.get("sha256")
        if not isinstance(expected_sha, str) or not HEX64.fullmatch(expected_sha):
            raise ValidationError(f"invalid lowercase SHA-256 for {source}")
        actual_sha = hashlib.sha256(source.read_bytes()).hexdigest()
        if actual_sha != expected_sha:
            raise ValidationError(f"source SHA-256 mismatch for {source}")

        road_ids = descriptor.get("road_ids")
        if not isinstance(road_ids, list) or not road_ids:
            raise ValidationError(f"road_ids must be non-empty for {source}")
        indexed_local = set()
        for raw_id in road_ids:
            osm_id = exact_osm_id(raw_id)
            if osm_id in indexed_local or osm_id in indexed_global:
                raise ValidationError(f"duplicate indexed OSM id: {osm_id}")
            indexed_local.add(osm_id)
            indexed_global.add(osm_id)

        document = load_json(source)
        roads = document.get("roads")
        if not isinstance(roads, list):
            raise ValidationError(f"source roads must be an array: {source}")
        source_counts = {}
        for road in roads:
            if not isinstance(road, dict):
                raise ValidationError(f"source road entry must be an object: {source}")
            osm_id = exact_osm_id(road.get("osm_id"))
            source_counts[osm_id] = source_counts.get(osm_id, 0) + 1
        duplicates = sorted(osm_id for osm_id, count in source_counts.items() if count != 1)
        if duplicates:
            raise ValidationError(f"ambiguous source OSM ids in {source}: {duplicates[:8]}")
        missing = sorted(indexed_local.difference(source_counts))
        if missing:
            raise ValidationError(f"indexed OSM ids missing from {source}: {missing[:8]}")
        source_document_count += 1

    if not indexed_global:
        raise ValidationError("runtime index resolves zero roads")
    return {
        "source_document_count": source_document_count,
        "indexed_road_count": len(indexed_global),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--index", default="data/runtime/road_destination_runtime_index.json")
    args = parser.parse_args()
    root = Path(args.root)
    index_path = Path(args.index)
    if not index_path.is_absolute():
        index_path = root / index_path
    try:
        result = validate(root, index_path)
    except ValidationError as exc:
        raise SystemExit(f"AUTOMATIC_ROAD_RUNTIME_INDEX_SOURCE_IDENTITY_FAIL: {exc}")
    print(
        "AUTOMATIC_ROAD_RUNTIME_INDEX_SOURCE_IDENTITY_GREEN: "
        f"documents={result['source_document_count']} indexed_roads={result['indexed_road_count']}"
    )


if __name__ == "__main__":
    main()
