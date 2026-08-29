#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "validate_registered_cell_index_semantics.py"
INDEX = ROOT / "data" / "provenance" / "brussels_registered_cell_manifest_index.json"


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
    tool = load(TOOL, "registered_cell_index_semantics")
    index = json.loads(INDEX.read_text(encoding="utf-8"))
    digest = tool.validate(index)
    assert digest == index["semantic_sha256"]

    tampered = json.loads(json.dumps(index))
    tampered["entries"][0]["bbox"][0] += 1.0
    expect_fail(lambda: tool.validate(tampered), "semantic sha drift")

    tampered = json.loads(json.dumps(index))
    tampered["registered_cell_count"] += 1
    tampered["semantic_sha256"] = tool.sha256_json(tool.semantic_payload(tampered))
    expect_fail(lambda: tool.validate(tampered), "cell accounting drift")

    tampered = json.loads(json.dumps(index))
    tampered["entries"][1]["cell_id"] = tampered["entries"][0]["cell_id"]
    tampered["semantic_sha256"] = tool.sha256_json(tool.semantic_payload(tampered))
    expect_fail(lambda: tool.validate(tampered), "cell identity drift")

    rebound = json.loads(json.dumps(index))
    rebound["production_base_sha"] = "f" * 40
    assert tool.validate(rebound) == digest

    tampered = json.loads(json.dumps(index))
    tampered["runtime_mount_authorized"] = True
    tampered["semantic_sha256"] = tool.sha256_json(tool.semantic_payload(tampered))
    expect_fail(lambda: tool.validate(tampered), "authorization opened")

    print("REGISTERED_CELL_INDEX_SEMANTICS_TEST_GREEN")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
