#!/usr/bin/env python3
import argparse
from pathlib import Path

from strict_json_evidence import load_path_strict


def canonical_source_path(raw):
    if not isinstance(raw, str) or not raw or raw.strip() != raw or "\\" in raw:
        raise ValueError(f"non-canonical source path: {raw!r}")
    text = raw[len("res://"):] if raw.startswith("res://") else raw
    if not text or text.startswith("/") or text.endswith("/") or "//" in text or "://" in text:
        raise ValueError(f"non-project source path: {raw!r}")
    parts = text.split("/")
    if any(not part or part in {".", ".."} or ":" in part for part in parts):
        raise ValueError(f"forbidden source path segment: {raw!r}")
    return text


def validate(root: Path, index_path: Path):
    root = root.resolve()
    index = load_path_strict(index_path.resolve())
    if not isinstance(index, dict):
        raise ValueError("runtime index must be an object")
    documents = index.get("documents")
    if not isinstance(documents, list) or not documents:
        raise ValueError("runtime index documents must be non-empty")
    checked = 0
    for descriptor in documents:
        if not isinstance(descriptor, dict):
            raise ValueError("runtime index descriptor must be an object")
        relative = canonical_source_path(descriptor.get("path"))
        source = (root / relative).resolve()
        source.relative_to(root)
        document = load_path_strict(source)
        if not isinstance(document, dict):
            raise ValueError(f"source document must be an object: {relative}")
        checked += 1
    return checked


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument("--index", default="data/runtime/road_destination_runtime_index.json")
    args = parser.parse_args()
    root = Path(args.root)
    index_path = Path(args.index)
    if not index_path.is_absolute():
        index_path = root / index_path
    checked = validate(root, index_path)
    print(f"AUTOMATIC_ROAD_RUNTIME_INDEX_STRICT_JSON_GREEN: documents={checked} duplicate_keys=false nonfinite=false")


if __name__ == "__main__":
    main()
