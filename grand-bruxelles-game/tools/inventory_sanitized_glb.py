#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

from strip_glb_animations import GlbError, parse_glb

STRUCTURAL_ARRAY_KEYS = (
    "scenes", "nodes", "meshes", "skins", "materials", "textures", "images",
    "samplers", "accessors", "bufferViews", "buffers", "cameras",
)


def _index(value, size: int, label: str) -> None:
    if not isinstance(value, int) or isinstance(value, bool) or value < 0 or value >= size:
        raise GlbError(f"{label} index out of range: {value!r} / {size}")


def _validate_references(document: dict, counts: dict[str, int], extra_chunks: list[tuple[int, bytes]]) -> None:
    nodes = document.get("nodes", []) or []
    for i, node in enumerate(nodes):
        if not isinstance(node, dict):
            raise GlbError(f"nodes[{i}] must be an object")
        if "mesh" in node:
            _index(node["mesh"], counts["meshes"], f"nodes[{i}].mesh")
        if "skin" in node:
            _index(node["skin"], counts["skins"], f"nodes[{i}].skin")
        for child in node.get("children", []) or []:
            _index(child, counts["nodes"], f"nodes[{i}].children")

    for i, skin in enumerate(document.get("skins", []) or []):
        if not isinstance(skin, dict):
            raise GlbError(f"skins[{i}] must be an object")
        joints = skin.get("joints")
        if not isinstance(joints, list) or not joints:
            raise GlbError(f"skins[{i}].joints must be a non-empty array")
        for joint in joints:
            _index(joint, counts["nodes"], f"skins[{i}].joints")
        if "skeleton" in skin:
            _index(skin["skeleton"], counts["nodes"], f"skins[{i}].skeleton")
        if "inverseBindMatrices" in skin:
            _index(skin["inverseBindMatrices"], counts["accessors"], f"skins[{i}].inverseBindMatrices")

    for i, mesh in enumerate(document.get("meshes", []) or []):
        if not isinstance(mesh, dict) or not isinstance(mesh.get("primitives"), list) or not mesh["primitives"]:
            raise GlbError(f"meshes[{i}].primitives must be a non-empty array")
        for j, primitive in enumerate(mesh["primitives"]):
            if not isinstance(primitive, dict):
                raise GlbError(f"meshes[{i}].primitives[{j}] must be an object")
            attributes = primitive.get("attributes")
            if not isinstance(attributes, dict) or not attributes:
                raise GlbError(f"meshes[{i}].primitives[{j}].attributes must be a non-empty object")
            for semantic, accessor in attributes.items():
                _index(accessor, counts["accessors"], f"meshes[{i}].primitives[{j}].attributes.{semantic}")
            if "indices" in primitive:
                _index(primitive["indices"], counts["accessors"], f"meshes[{i}].primitives[{j}].indices")
            if "material" in primitive:
                _index(primitive["material"], counts["materials"], f"meshes[{i}].primitives[{j}].material")

    for i, view in enumerate(document.get("bufferViews", []) or []):
        if not isinstance(view, dict):
            raise GlbError(f"bufferViews[{i}] must be an object")
        _index(view.get("buffer"), counts["buffers"], f"bufferViews[{i}].buffer")

    for i, accessor in enumerate(document.get("accessors", []) or []):
        if not isinstance(accessor, dict):
            raise GlbError(f"accessors[{i}] must be an object")
        if "bufferView" in accessor:
            _index(accessor["bufferView"], counts["bufferViews"], f"accessors[{i}].bufferView")

    buffers = document.get("buffers", []) or []
    if len(buffers) > 1:
        raise GlbError("GLB inventory supports exactly one embedded buffer")
    if buffers:
        buffer = buffers[0]
        if not isinstance(buffer, dict) or not isinstance(buffer.get("byteLength"), int) or buffer["byteLength"] < 0:
            raise GlbError("buffers[0].byteLength must be a non-negative integer")
        bin_bytes = sum(len(payload) for chunk_type, payload in extra_chunks if chunk_type == 0x004E4942)
        if buffer["byteLength"] > bin_bytes:
            raise GlbError(f"embedded buffer byteLength {buffer['byteLength']} exceeds BIN payload {bin_bytes}")


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

    _validate_references(document, counts, extra_chunks)

    return {
        "format": "grand-bruxelles-sanitized-glb-inventory-v2",
        "sha256": hashlib.sha256(data).hexdigest(),
        "size_bytes": len(data),
        "asset_version": asset["version"],
        "generator": asset.get("generator"),
        "animations_present": False,
        "reference_integrity": "validated",
        "counts": counts,
        "extra_chunks": [
            {"type": chunk_type, "size_bytes": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}
            for chunk_type, payload in extra_chunks
        ],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Fail-closed structural + reference inventory for a sanitized GLB")
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
