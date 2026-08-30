#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from strip_glb_animations import GlbError, parse_glb

STRUCTURAL_ARRAY_KEYS = (
    "scenes",
    "nodes",
    "meshes",
    "skins",
    "materials",
    "textures",
    "images",
    "samplers",
    "accessors",
    "bufferViews",
    "buffers",
    "cameras",
)


def build_inventory(data: bytes) -> dict:
    document, extra_chunks = parse_glb(data)
    if "animations" in document:
        raise GlbError("sanitized GLB still contains animations")

    counts: dict[str, int] = {}
    for key in STRUCTURAL_ARRAY_KEYS:
        value = document.get(key, [])
        if value is None:
            value = []
        if not isinstance(value, list):
            raise GlbError(f"{key} must be an array when present")
        counts[key] = len(value)

    asset = document.get("asset")
    if not isinstance(asset, dict) or asset.get("version") != "2.0":
        raise GlbError("glTF asset.version must be 2.0")

    return {
        "format": "grand-bruxelles-sanitized-glb-inventory-v1",
        "sha256": hashlib.sha256(data).hexdigest(),
        "size_bytes": len(data),
        "asset_version": asset["version"],
        "generator": asset.get("generator"),
        "animations_present": False,
        "counts": counts,
        "extra_chunks": [
            {"type": chunk_type, "size_bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
            for chunk_type, payload in extra_chunks
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail-closed structural inventory for a sanitized GLB")
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()

    try:
        data = args.input.read_bytes()
        inventory = build_inventory(data)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(inventory, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    except (OSError, GlbError) as exc:
        print(f"GLB_SANITIZED_INVENTORY_FAIL: {exc}", file=sys.stderr)
        return 1

    print("GLB_SANITIZED_INVENTORY_OK")
    print(f"sha256={inventory['sha256']}")
    print(f"size_bytes={inventory['size_bytes']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
