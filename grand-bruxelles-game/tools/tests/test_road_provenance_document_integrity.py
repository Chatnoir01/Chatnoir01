#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import shutil
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "verify_road_provenance_document_integrity.py"
BINDING_BUILDER = ROOT / "tools" / "build_road_destination_provenance_binding.py"
CATALOG_BUILDER = ROOT / "tools" / "build_road_destination_catalog.py"
READINESS = ROOT / "data" / "provenance" / "brussels_road_destination_readiness_catalog.json"
SOURCE_ROOT = ROOT / "data" / "osm"


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def expect_fail(fn, needle: str) -> None:
    try:
        fn()
    except SystemExit as exc:
        assert needle in str(exc), str(exc)
    else:
        raise AssertionError(f"expected failure containing {needle!r}")


def main() -> int:
    verifier = load(TOOL, "road_document_integrity")
    builder = load(BINDING_BUILDER, "road_binding_builder_for_integrity")
    binding = builder.build_binding(SOURCE_ROOT, READINESS, CATALOG_BUILDER)

    result = verifier.verify_binding_source_documents(binding, ROOT)
    assert result["document_count"] >= 1
    assert result["verified"] is True

    with tempfile.TemporaryDirectory() as tmp:
        tmp_root = Path(tmp) / "project"
        shutil.copytree(ROOT / "data", tmp_root / "data")
        tampered = json.loads(json.dumps(binding))
        source_path = sorted(tampered["source_document_sha256"])[0]
        source_file = tmp_root / source_path
        source_file.write_bytes(source_file.read_bytes() + b"\n")
        expect_fail(lambda: verifier.verify_binding_source_documents(tampered, tmp_root), "source document sha drift")

    traversal = json.loads(json.dumps(binding))
    digest = next(iter(traversal["source_document_sha256"].values()))
    traversal["source_document_sha256"] = {"data/osm/../provenance/brussels_road_destination_readiness_catalog.json": digest}
    expect_fail(lambda: verifier.verify_binding_source_documents(traversal, ROOT), "unsafe source document path")

    absolute = json.loads(json.dumps(binding))
    absolute["source_document_sha256"] = {str((ROOT / "data/osm/vertical_slice_01.game.json").resolve()): digest}
    expect_fail(lambda: verifier.verify_binding_source_documents(absolute, ROOT), "unsafe source document path")

    print("ROAD_PROVENANCE_DOCUMENT_INTEGRITY_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
