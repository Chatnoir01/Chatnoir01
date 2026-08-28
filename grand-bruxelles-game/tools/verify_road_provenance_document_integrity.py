#!/usr/bin/env python3
"""Fail-closed byte-integrity verifier for road provenance source documents."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
from pathlib import Path
from typing import Any


def is_sha256(value: Any) -> bool:
    text = str(value or "").lower()
    return len(text) == 64 and all(ch in "0123456789abcdef" for ch in text)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _safe_source_path(project_root: Path, raw_path: Any) -> tuple[str, Path]:
    text = str(raw_path or "")
    candidate = Path(text)
    if not text or candidate.is_absolute() or ".." in candidate.parts:
        raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: unsafe source document path {text!r}")
    if len(candidate.parts) < 3 or candidate.parts[0:2] != ("data", "osm"):
        raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: unsafe source document path {text!r}")
    root = project_root.resolve()
    resolved = (root / candidate).resolve()
    osm_root = (root / "data" / "osm").resolve()
    try:
        resolved.relative_to(osm_root)
    except ValueError as exc:
        raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: unsafe source document path {text!r}") from exc
    return candidate.as_posix(), resolved


def verify_binding_source_documents(binding: dict[str, Any], project_root: Path) -> dict[str, Any]:
    registry = binding.get("source_document_sha256")
    if not isinstance(registry, dict) or not registry:
        raise SystemExit("ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: missing source document registry")

    normalized: dict[str, str] = {}
    for raw_path, raw_digest in registry.items():
        path_text, source_file = _safe_source_path(project_root, raw_path)
        digest = str(raw_digest or "").lower()
        if not is_sha256(digest):
            raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: invalid source document sha {path_text}")
        if path_text in normalized:
            raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: duplicate source document path {path_text}")
        if not source_file.is_file():
            raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: missing source document {path_text}")
        actual = sha256_file(source_file)
        if actual != digest:
            raise SystemExit(
                "ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: "
                f"source document sha drift {path_text} stored={digest} actual={actual}"
            )
        normalized[path_text] = digest

    if list(registry) != sorted(registry):
        raise SystemExit("ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: source document registry order drift")

    referenced: set[str] = set()
    entries = binding.get("entries")
    if not isinstance(entries, dict) or not entries:
        raise SystemExit("ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: missing provenance entries")
    for road_id, row in entries.items():
        if not isinstance(row, dict):
            raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: malformed provenance row {road_id}")
        paths = row.get("source_paths")
        if not isinstance(paths, list) or not paths:
            raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: missing source paths {road_id}")
        for raw_path in paths:
            path_text, _ = _safe_source_path(project_root, raw_path)
            if path_text not in normalized:
                raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: unregistered source path {road_id}: {path_text}")
            referenced.add(path_text)

    if referenced != set(normalized):
        unused = sorted(set(normalized) - referenced)
        raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: unreferenced source documents {unused}")

    return {"verified": True, "document_count": len(normalized), "referenced_document_count": len(referenced)}


def load_module(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"ROAD_PROVENANCE_DOCUMENT_INTEGRITY_FAIL: cannot load {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project-root", type=Path, default=Path("."))
    parser.add_argument("--source-root", type=Path, default=Path("data/osm"))
    parser.add_argument("--readiness", type=Path, default=Path("data/provenance/brussels_road_destination_readiness_catalog.json"))
    parser.add_argument("--catalog-builder", type=Path, default=Path("tools/build_road_destination_catalog.py"))
    parser.add_argument("--binding-builder", type=Path, default=Path("tools/build_road_destination_provenance_binding.py"))
    args = parser.parse_args()

    builder = load_module(args.binding_builder, "road_binding_builder_document_integrity")
    binding = builder.build_binding(args.source_root, args.readiness, args.catalog_builder)
    builder.validate_binding(binding)
    result = verify_binding_source_documents(binding, args.project_root)
    print(
        "ROAD_PROVENANCE_DOCUMENT_INTEGRITY_GREEN: "
        f"documents={result['document_count']} referenced={result['referenced_document_count']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
