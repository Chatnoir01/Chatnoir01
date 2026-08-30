#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "tools/strip_glb_animations.py"
spec = importlib.util.spec_from_file_location("strip_glb_animations", MODULE_PATH)
module = importlib.util.module_from_spec(spec)
assert spec and spec.loader
spec.loader.exec_module(module)


def make_glb(document: dict, bin_payload: bytes = b"\x01\x02\x03\x04") -> bytes:
    json_bytes = json.dumps(document, separators=(",", ":")).encode("utf-8")
    json_bytes += b" " * ((-len(json_bytes)) % 4)
    bin_payload += b"\x00" * ((-len(bin_payload)) % 4)
    body = struct.pack("<II", len(json_bytes), module.JSON_CHUNK) + json_bytes + struct.pack("<II", len(bin_payload), module.BIN_CHUNK) + bin_payload
    return struct.pack("<4sII", module.GLB_MAGIC, module.GLB_VERSION, 12 + len(body)) + body


def test_strips_only_animation_json_and_preserves_binary_payload() -> None:
    source_document = {
        "asset": {"version": "2.0"},
        "nodes": [{"mesh": 0, "skin": 0}],
        "meshes": [{"primitives": [{"attributes": {"POSITION": 0}, "material": 0}]}],
        "skins": [{"joints": [0], "inverseBindMatrices": 1}],
        "materials": [{"name": "skin"}],
        "bufferViews": [{"buffer": 0, "byteOffset": 0, "byteLength": 4}],
        "accessors": [{"bufferView": 0, "componentType": 5126, "count": 1, "type": "VEC3"}],
        "animations": [{"name": "mixamo_walk", "samplers": [], "channels": []}],
        "buffers": [{"byteLength": 4}],
    }
    source = make_glb(source_document)
    output, removed = module.strip_animations(source)
    assert removed == 1
    result, extra_chunks = module.parse_glb(output)
    assert "animations" not in result
    for key in ("nodes", "meshes", "skins", "materials", "bufferViews", "accessors", "buffers"):
        assert result[key] == source_document[key]
    assert extra_chunks == [(module.BIN_CHUNK, b"\x01\x02\x03\x04")]


def test_output_is_deterministic() -> None:
    source = make_glb({"nodes": [], "asset": {"version": "2.0"}, "animations": [{"channels": [], "samplers": []}]})
    first, removed_first = module.strip_animations(source)
    second, removed_second = module.strip_animations(source)
    assert removed_first == removed_second == 1
    assert first == second


def test_no_animation_source_is_a_valid_noop_semantically() -> None:
    source = make_glb({"asset": {"version": "2.0"}, "nodes": []})
    output, removed = module.strip_animations(source)
    assert removed == 0
    result, _ = module.parse_glb(output)
    assert result == {"asset": {"version": "2.0"}, "nodes": []}


def test_rejects_truncated_or_wrong_version_glb() -> None:
    for bad in (b"glTF", make_glb({"asset": {"version": "2.0"}})[:4] + struct.pack("<I", 1) + make_glb({"asset": {"version": "2.0"}})[8:]):
        try:
            module.strip_animations(bad)
            raise AssertionError("invalid GLB accepted")
        except module.GlbError:
            pass


def test_rejects_malformed_animation_shape() -> None:
    source = make_glb({"asset": {"version": "2.0"}, "animations": {"bad": True}})
    try:
        module.strip_animations(source)
        raise AssertionError("malformed animations accepted")
    except module.GlbError as exc:
        assert "animations must be an array" in str(exc)


def main() -> int:
    tests = [test_strips_only_animation_json_and_preserves_binary_payload, test_output_is_deterministic, test_no_animation_source_is_a_valid_noop_semantically, test_rejects_truncated_or_wrong_version_glb, test_rejects_malformed_animation_shape]
    for test in tests:
        test(); print(f"PASS {test.__name__}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
