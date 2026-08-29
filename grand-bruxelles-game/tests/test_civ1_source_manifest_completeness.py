#!/usr/bin/env python3
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATUS_PATH = ROOT / "assets/characters/civilians/civ1/source_status.json"
EXPECTED_TOTAL_BYTES = 53_274_960
EXPECTED_SHOES_BYTES = 177_420


def main() -> int:
    status = json.loads(STATUS_PATH.read_text(encoding="utf-8"))
    manifest = status["source_manifest"]
    source_paths = status["source_paths"]

    assert set(manifest) == set(source_paths), "source manifest/path mismatch"
    assert len(source_paths) == 5, f"expected five pinned CIV-1 sources, got {len(source_paths)}"

    total = 0
    for rel in source_paths:
        pin = manifest[rel]
        size = pin.get("size_bytes")
        blob = pin.get("git_blob_sha1")
        assert isinstance(size, int) and size > 0, f"missing positive size pin: {rel}"
        assert isinstance(blob, str) and len(blob) == 40, f"invalid git blob pin: {rel}"
        total += size

    shoes = manifest["assets/characters/civilians/civ1/source/shoes03.obj"]
    assert shoes["size_bytes"] == EXPECTED_SHOES_BYTES, shoes
    assert total == EXPECTED_TOTAL_BYTES, f"unexpected total pinned bytes: {total}"

    print(f"CIV1_SOURCE_MANIFEST_COMPLETE files={len(source_paths)} total_bytes={total}")
    print(f"shoes03_size_bytes={shoes['size_bytes']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
